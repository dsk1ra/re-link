use crate::shared::{
    HeartbeatRequest, RegisterRequest, SignalFetchRequest,
    SignalFetchResponse, SignalSubmitRequest, ConnectionInitRequest, ConnectionInitResponse,
    ConnectionJoinRequest, ConnectionJoinResponse, MailboxSendRequest, MailboxRecvResponse,
    MailboxMessage,
};
use crate::signaling::{RegistryError, SessionRegistry, SignalingServerConfig};
use crate::connection;
use axum::{
    extract::{Path, State, WebSocketUpgrade},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use axum::extract::ws::{Message, WebSocket};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::{info, instrument};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone)]
struct AppState {
    registry: Arc<SessionRegistry>,
    config: Arc<SignalingServerConfig>,
    redis: redis::Client,
    push: Arc<PushHub>,
}

struct PushHub {
    inner: tokio::sync::Mutex<std::collections::HashMap<String, tokio::sync::broadcast::Sender<String>>>,
}

impl PushHub {
    fn new() -> Self {
        Self { inner: tokio::sync::Mutex::new(std::collections::HashMap::new()) }
    }
    async fn subscribe(&self, mailbox_id: &str) -> tokio::sync::broadcast::Receiver<String> {
        let mut guard = self.inner.lock().await;
        let tx = guard.entry(mailbox_id.to_string()).or_insert_with(|| {
            let (tx, _rx) = tokio::sync::broadcast::channel(100);
            tx
        });
        tx.subscribe()
    }
    async fn notify(&self, mailbox_id: &str, msg: String) {
        let guard = self.inner.lock().await;
        if let Some(tx) = guard.get(mailbox_id) {
            let _ = tx.send(msg);
        }
    }
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    message: String,
}

pub async fn run_server(config: SignalingServerConfig) -> anyhow::Result<()> {
    let registry = Arc::new(SessionRegistry::new(
        config.session_ttl,
        config.heartbeat_interval,
    ));
    // Enforce TLS for Redis unless explicitly disabled for local dev
    if config.redis_require_tls && !config.redis_url.starts_with("rediss://") {
        anyhow::bail!(
            "Redis TLS required but URL is not rediss:// (got: {}). Set SIGNALING_REDIS_REQUIRE_TLS=false only for local development.",
            config.redis_url
        );
    }
    let redis = redis::Client::open(config.redis_url.clone())?;
    let state = AppState {
        registry,
        config: Arc::new(config),
        redis,
        push: Arc::new(PushHub::new()),
    };

    let router = Router::new()
        .route("/", get(root))
        .route("/health", get(healthcheck))
        .route("/register", post(register))
        .route("/heartbeat", post(heartbeat))
        .route("/signal", post(send_signal))
        .route("/signal/fetch", post(fetch_signal))
        // connection-based blind rendezvous endpoints
        .route("/connection/init", post(connection_init))
        .route("/connection/join", post(connection_join))
        .route("/connection/send", post(mailbox_send))
        .route("/connection/recv", post(mailbox_recv))
        // websocket push for mailbox
        .route("/ws/{mailbox_id}", get(ws_upgrade))
        .with_state(state.clone());

    let listen_addr = state.config.listen_addr;
    let listener = TcpListener::bind(listen_addr).await?;
    info!(address = %listen_addr, "Starting signaling server");
    axum::serve(listener, router.into_make_service()).await?;
    Ok(())
}

async fn healthcheck(State(state): State<AppState>) -> impl IntoResponse {
    let body = SignalingServerInfo {
        public_base_url: state.config.public_base_url.clone(),
        heartbeat_interval_secs: state.config.heartbeat_interval.as_secs(),
    };
    (StatusCode::OK, Json(body))
}

#[derive(Serialize)]
struct SignalingServerInfo {
    public_base_url: String,
    heartbeat_interval_secs: u64,
}

#[instrument(skip(state, payload))]
async fn register(
    State(state): State<AppState>,
    Json(payload): Json<RegisterRequest>,
) -> impl IntoResponse {
    let response = state.registry.register(payload).await;
    (StatusCode::OK, Json(response))
}

#[instrument(skip(state, payload))]
async fn heartbeat(
    State(state): State<AppState>,
    Json(payload): Json<HeartbeatRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    state
        .registry
        .heartbeat(payload)
        .await
        .map(|resp| (StatusCode::OK, Json(resp)))
        .map_err(registry_err)
}

#[instrument(skip(state, payload))]
async fn send_signal(
    State(state): State<AppState>,
    Json(payload): Json<SignalSubmitRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    state
        .registry
        .enqueue_signal(payload)
        .await
        .map(|()| StatusCode::ACCEPTED)
        .map_err(registry_err)
}

#[instrument(skip(state, payload))]
async fn fetch_signal(
    State(state): State<AppState>,
    Json(payload): Json<SignalFetchRequest>,
) -> Result<(StatusCode, Json<SignalFetchResponse>), (StatusCode, Json<ErrorResponse>)> {
    state
        .registry
        .fetch_signals(payload)
        .await
        .map(|messages| (StatusCode::OK, Json(messages)))
        .map_err(registry_err)
}

fn registry_err(err: RegistryError) -> (StatusCode, Json<ErrorResponse>) {
    let status = match err {
        RegistryError::ClientNotFound => StatusCode::NOT_FOUND,
        RegistryError::InvalidToken => StatusCode::UNAUTHORIZED,
    };
    (
        status,
        Json(ErrorResponse {
            message: err.to_string(),
        }),
    )
}

// -------- Connection Link (Blind Rendezvous) --------

#[derive(Debug, Deserialize, Serialize, Clone)]
struct MailboxState {
    mailbox_id: String,
    peer_mailbox_id: Option<String>,
    created_at_epoch_ms: u128,
    expires_at_epoch_ms: u128,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
struct MailboxMessageStored {
    from_mailbox_id: String,
    ciphertext_b64: String,
    sequence: u64,
    timestamp_epoch_ms: u128,
}

// -------- Connection Link Handlers (Blind Rendezvous) --------

#[instrument(skip(state, payload))]
async fn connection_init(
    State(state): State<AppState>,
    Json(payload): Json<ConnectionInitRequest>,
) -> Result<(StatusCode, Json<ConnectionInitResponse>), (StatusCode, Json<ErrorResponse>)> {
    // verify client/session
    state
        .registry
        .verify_session(&payload.client_id, &payload.session_token)
        .await
        .map_err(registry_err)?;

    // Generate opaque mailbox ID for initiator
    let mailbox_id = connection::gen_mailbox_id();
    
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let expires_ms = now_ms + (state.config.room_ttl.as_millis() as u128);

    // Store mailbox metadata
    let mailbox_state = MailboxState {
        mailbox_id: mailbox_id.clone(),
        peer_mailbox_id: None,
        created_at_epoch_ms: now_ms,
        expires_at_epoch_ms: expires_ms,
    };
    
    let mut conn = state
        .redis
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let ttl_secs = state.config.room_ttl.as_secs();
    let meta_key = format!("{}:mailbox_meta:{}", state.config.redis_key_prefix, mailbox_id);
    let mailbox_list_key = format!("{}:mailbox_msgs:{}", state.config.redis_key_prefix, mailbox_id);
    let rendezvous_key = format!("{}:rendezvous:{}", state.config.redis_key_prefix, payload.rendezvous_id_b64);

    // Store mailbox metadata
    let meta_json = serde_json::to_string(&mailbox_state).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;
    let _: () = redis::cmd("SET")
        .arg(&meta_key)
        .arg(meta_json)
        .arg("EX")
        .arg(ttl_secs)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    // Initialize empty message list
    let _: () = redis::cmd("DEL")
        .arg(&mailbox_list_key)
        .query_async(&mut conn)
        .await
        .unwrap_or(());

    // Store mapping: rendezvous_id -> mailbox_id (TTL: short, single-use)
    let rendezvous_ttl_secs = 300u64; // 5 minutes for link generation
    let _: () = redis::cmd("SET")
        .arg(&rendezvous_key)
        .arg(&mailbox_id)
        .arg("EX")
        .arg(rendezvous_ttl_secs)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    Ok((
        StatusCode::OK,
        Json(ConnectionInitResponse {
            mailbox_id,
            expires_at_epoch_ms: expires_ms,
        }),
    ))
}

#[instrument(skip(state, payload))]
async fn connection_join(
    State(state): State<AppState>,
    Json(payload): Json<ConnectionJoinRequest>,
) -> Result<(StatusCode, Json<ConnectionJoinResponse>), (StatusCode, Json<ErrorResponse>)> {
    // Lookup mailbox_id from rendezvous token
    let mut conn = state
        .redis
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let rendezvous_key = format!("{}:rendezvous:{}", state.config.redis_key_prefix, payload.token_b64);
    let initiator_mailbox_id: Option<String> = redis::cmd("GET")
        .arg(&rendezvous_key)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let Some(initiator_mailbox_id) = initiator_mailbox_id else {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                message: "Invalid or expired token".to_string(),
            }),
        ));
    };

    // Delete token to prevent reuse (single-use)
    let _: () = redis::cmd("DEL")
        .arg(&rendezvous_key)
        .query_async(&mut conn)
        .await
        .unwrap_or(());

    // Generate mailbox for responder
    let responder_mailbox_id = connection::gen_mailbox_id();

    // Verify initiator mailbox exists and not yet joined
    let initiator_meta_key = format!("{}:mailbox_meta:{}", state.config.redis_key_prefix, initiator_mailbox_id);
    let initiator_meta_json: Option<String> = redis::cmd("GET")
        .arg(&initiator_meta_key)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let Some(meta_json) = initiator_meta_json else {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                message: "Initiator session not found or expired".to_string(),
            }),
        ));
    };

    let mut initiator_state: MailboxState = serde_json::from_str(&meta_json).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;

    // Check if already joined (peer_mailbox_id set)
    if initiator_state.peer_mailbox_id.is_some() {
        return Err((
            StatusCode::CONFLICT,
            Json(ErrorResponse {
                message: "Session already has a peer".to_string(),
            }),
        ));
    }

    // Link the two mailboxes
    initiator_state.peer_mailbox_id = Some(responder_mailbox_id.clone());
    let updated_meta = serde_json::to_string(&initiator_state).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;

    let ttl_secs = state.config.room_ttl.as_secs();
    let _: () = redis::cmd("SET")
        .arg(&initiator_meta_key)
        .arg(updated_meta)
        .arg("EX")
        .arg(ttl_secs)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    // Store responder mailbox metadata
    let responder_meta_key = format!("{}:mailbox_meta:{}", state.config.redis_key_prefix, responder_mailbox_id);
    let responder_state = MailboxState {
        mailbox_id: responder_mailbox_id.clone(),
        peer_mailbox_id: Some(initiator_mailbox_id),
        created_at_epoch_ms: initiator_state.created_at_epoch_ms,
        expires_at_epoch_ms: initiator_state.expires_at_epoch_ms,
    };
    let responder_meta_json = serde_json::to_string(&responder_state).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;
    let _: () = redis::cmd("SET")
        .arg(&responder_meta_key)
        .arg(responder_meta_json)
        .arg("EX")
        .arg(ttl_secs)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    // Initialize responder message list
    let responder_list_key = format!("{}:mailbox_msgs:{}", state.config.redis_key_prefix, responder_mailbox_id);
    let _: () = redis::cmd("DEL")
        .arg(&responder_list_key)
        .query_async(&mut conn)
        .await
        .unwrap_or(());

    // Also push a 'join' event into initiator's mailbox for immediate notification
    let initiator_list_key = format!("{}:mailbox_msgs:{}", state.config.redis_key_prefix, initiator_state.mailbox_id);
    let initiator_msg_count: u64 = redis::cmd("LLEN")
        .arg(&initiator_list_key)
        .query_async(&mut conn)
        .await
        .unwrap_or(0);

    let join_msg = MailboxMessageStored {
        from_mailbox_id: responder_mailbox_id.clone(),
        ciphertext_b64: "".to_string(),
        sequence: initiator_msg_count,
        timestamp_epoch_ms: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or_default(),
    };
    let join_json = serde_json::to_string(&join_msg).unwrap_or_else(|_| "{}".to_string());
    let _: () = redis::cmd("RPUSH")
        .arg(&initiator_list_key)
        .arg(&join_json)
        .query_async(&mut conn)
        .await
        .unwrap_or(());
    let _: () = redis::cmd("EXPIRE")
        .arg(&initiator_list_key)
        .arg(ttl_secs)
        .query_async(&mut conn)
        .await
        .unwrap_or(());

    // Notify initiator subscribers via WS
    state.push.notify(&initiator_state.mailbox_id, join_json).await;

    Ok((
        StatusCode::OK,
        Json(ConnectionJoinResponse {
            mailbox_id: responder_mailbox_id,
            expires_at_epoch_ms: responder_state.expires_at_epoch_ms,
        }),
    ))
}

#[instrument(skip(state, payload))]
async fn mailbox_send(
    State(state): State<AppState>,
    Json(payload): Json<MailboxSendRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    let mut conn = state
        .redis
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    // Get mailbox metadata
    let meta_key = format!("{}:mailbox_meta:{}", state.config.redis_key_prefix, payload.mailbox_id);
    let meta_json: Option<String> = redis::cmd("GET")
        .arg(&meta_key)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let Some(meta_json) = meta_json else {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                message: "Mailbox not found".to_string(),
            }),
        ));
    };

    let mailbox_state: MailboxState = serde_json::from_str(&meta_json).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;

    let Some(peer_mailbox_id) = mailbox_state.peer_mailbox_id else {
        return Err((
            StatusCode::CONFLICT,
            Json(ErrorResponse {
                message: "No peer connected".to_string(),
            }),
        ));
    };

    // Check expiry
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    if now_ms >= mailbox_state.expires_at_epoch_ms {
        return Err((
            StatusCode::GONE,
            Json(ErrorResponse {
                message: "Session expired".to_string(),
            }),
        ));
    }

    // Get current message count for sequence number
    let peer_list_key = format!("{}:mailbox_msgs:{}", state.config.redis_key_prefix, peer_mailbox_id);
    let msg_count: u64 = redis::cmd("LLEN")
        .arg(&peer_list_key)
        .query_async(&mut conn)
        .await
        .unwrap_or(0);

    // Store message in peer's mailbox
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    
    let msg = MailboxMessageStored {
        from_mailbox_id: payload.mailbox_id.clone(),
        ciphertext_b64: payload.ciphertext_b64,
        sequence: msg_count,
        timestamp_epoch_ms: timestamp,
    };

    let msg_json = serde_json::to_string(&msg).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;

    let ttl_secs = state.config.room_ttl.as_secs();
    let _: () = redis::cmd("RPUSH")
        .arg(&peer_list_key)
        .arg(&msg_json)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    // Push notify subscribers of peer mailbox
    state.push.notify(&peer_mailbox_id, msg_json).await;

    // Ensure TTL is set
    let _: () = redis::cmd("EXPIRE")
        .arg(&peer_list_key)
        .arg(ttl_secs)
        .query_async(&mut conn)
        .await
        .unwrap_or(());

    Ok(StatusCode::ACCEPTED)
}

#[instrument(skip(state, payload))]
async fn mailbox_recv(
    State(state): State<AppState>,
    Json(payload): Json<MailboxSendRequest>,
) -> Result<(StatusCode, Json<MailboxRecvResponse>), (StatusCode, Json<ErrorResponse>)> {
    let mut conn = state
        .redis
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    // Get mailbox metadata to verify it exists
    let meta_key = format!("{}:mailbox_meta:{}", state.config.redis_key_prefix, payload.mailbox_id);
    let meta_json: Option<String> = redis::cmd("GET")
        .arg(&meta_key)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let Some(meta_json) = meta_json else {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                message: "Mailbox not found".to_string(),
            }),
        ));
    };

    let _mailbox_state: MailboxState = serde_json::from_str(&meta_json).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;

    // Fetch messages from this mailbox
    let list_key = format!("{}:mailbox_msgs:{}", state.config.redis_key_prefix, payload.mailbox_id);
    let msg_jsons: Vec<String> = redis::cmd("LRANGE")
        .arg(&list_key)
        .arg(0)
        .arg(-1)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let messages: Vec<MailboxMessage> = msg_jsons
        .iter()
        .filter_map(|json| {
            serde_json::from_str::<MailboxMessageStored>(json)
                .ok()
                .map(|stored| MailboxMessage {
                    from_mailbox_id: stored.from_mailbox_id,
                    ciphertext_b64: stored.ciphertext_b64,
                    sequence: stored.sequence,
                    timestamp_epoch_ms: stored.timestamp_epoch_ms,
                })
        })
        .collect();

    let last_sequence = messages.last().map(|m| m.sequence).unwrap_or(0);

    Ok((
        StatusCode::OK,
        Json(MailboxRecvResponse {
            messages,
            last_sequence,
        }),
    ))
}

// Root handler for "/"
async fn root() -> impl IntoResponse {
    (StatusCode::OK, "Server OK!")
}

// WebSocket endpoint: subscribe to mailbox events
async fn ws_upgrade(
    State(state): State<AppState>,
    Path(mailbox_id): Path<String>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    // Verify mailbox exists before upgrading
    let mut conn = match state.redis.get_multiplexed_async_connection().await {
        Ok(c) => c,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let meta_key = format!("{}:mailbox_meta:{}", state.config.redis_key_prefix, mailbox_id);
    let meta_json: Option<String> = match redis::cmd("GET").arg(&meta_key).query_async(&mut conn).await {
        Ok(v) => v,
        Err(_) => None,
    };

    if meta_json.is_none() {
        return StatusCode::NOT_FOUND.into_response();
    }

    ws.on_upgrade(move |socket| handle_ws(socket, state, mailbox_id))
}

async fn handle_ws(mut socket: WebSocket, state: AppState, mailbox_id: String) {
    let mut rx = state.push.subscribe(&mailbox_id).await;
    // Forward broadcast events to WebSocket client
    loop {
        match rx.recv().await {
            Ok(msg) => {
                if socket.send(Message::Text(msg.into())).await.is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}
