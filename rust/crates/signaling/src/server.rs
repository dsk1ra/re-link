use shared::models::{
    HeartbeatRequest, RegisterRequest, SignalFetchRequest,
    SignalFetchResponse, SignalSubmitRequest, ConnectionInitRequest, ConnectionInitResponse,
    ConnectionJoinRequest, ConnectionJoinResponse, MailboxSendRequest, MailboxRecvResponse,
};
use crate::registry::{RegistryError, SessionRegistry};
use crate::config::SignalingServerConfig;
use crate::repository::redis_repository::RedisRepository;
use crate::services::rendezvous_service::{RendezvousService, RendezvousError};

use axum::{
    extract::{Path, State, WebSocketUpgrade},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use axum::extract::ws::{Message, WebSocket};
use serde::Serialize;
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::{info, instrument};

#[derive(Clone)]
struct PushHub {
    inner: Arc<tokio::sync::Mutex<std::collections::HashMap<String, tokio::sync::broadcast::Sender<String>>>>,
}

impl PushHub {
    fn new() -> Self {
        Self { inner: Arc::new(tokio::sync::Mutex::new(std::collections::HashMap::new())) }
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

#[derive(Clone)]
struct AppState {
    registry: Arc<SessionRegistry>,
    config: Arc<SignalingServerConfig>,
    push: Arc<PushHub>,
    rendezvous_service: Arc<RendezvousService>,
}

pub async fn run_server(config: SignalingServerConfig) -> anyhow::Result<()> {
    let registry = Arc::new(SessionRegistry::new(
        config.session_ttl,
        config.heartbeat_interval,
    ));
    
    if config.redis_require_tls && !config.redis_url.starts_with("rediss://") {
        anyhow::bail!(
            "Redis TLS required but URL is not rediss:// (got: {}). Set SIGNALING_REDIS_REQUIRE_TLS=false only for local development.",
            config.redis_url
        );
    }
    
    let redis_client = redis::Client::open(config.redis_url.clone())?;
    let redis_conn = redis_client.get_connection_manager().await?;
    let redis_repo = RedisRepository::new(redis_conn, config.redis_key_prefix.clone());
    let rendezvous_service = Arc::new(RendezvousService::new(redis_repo, config.mailbox_ttl.as_secs()));

    let state = AppState {
        registry,
        config: Arc::new(config),
        push: Arc::new(PushHub::new()),
        rendezvous_service,
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
        .route("/ws/:mailbox_id", get(ws_upgrade))
        .with_state(state.clone());

    let listen_addr = state.config.listen_addr;
    let listener = TcpListener::bind(listen_addr).await?;
    info!(address = %listen_addr, "Starting signaling server");
    axum::serve(listener, router.into_make_service_with_connect_info::<std::net::SocketAddr>()).await?;
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

fn rendezvous_err(err: RendezvousError) -> (StatusCode, Json<ErrorResponse>) {
    let status = match err {
        RendezvousError::MailboxNotFound => StatusCode::NOT_FOUND,
        RendezvousError::SessionExpired => StatusCode::GONE,
        RendezvousError::InvalidToken => StatusCode::NOT_FOUND,
        RendezvousError::SessionAlreadyPaired => StatusCode::CONFLICT,
        RendezvousError::NoPeerConnected => StatusCode::CONFLICT,
        RendezvousError::Redis(_) => StatusCode::INTERNAL_SERVER_ERROR,
    };
    (
        status,
        Json(ErrorResponse {
            message: err.to_string(),
        }),
    )
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

    let response = state.rendezvous_service.init_connection(payload.rendezvous_id_b64)
        .await
        .map_err(rendezvous_err)?;

    Ok((StatusCode::OK, Json(response)))
}

#[instrument(skip(state, payload))]
async fn connection_join(
    State(state): State<AppState>,
    Json(payload): Json<ConnectionJoinRequest>,
) -> Result<(StatusCode, Json<ConnectionJoinResponse>), (StatusCode, Json<ErrorResponse>)> {
    
    let (response, initiator_mailbox_id, join_json) = state.rendezvous_service.join_connection(payload.token_b64)
        .await
        .map_err(rendezvous_err)?;

    // Notify initiator subscribers via WS
    state.push.notify(&initiator_mailbox_id, join_json).await;

    Ok((StatusCode::OK, Json(response)))
}

#[instrument(skip(state, payload))]
async fn mailbox_send(
    State(state): State<AppState>,
    Json(payload): Json<MailboxSendRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    
    let (peer_mailbox_id, msg_json) = state.rendezvous_service.send_message(payload.mailbox_id, payload.ciphertext_b64)
        .await
        .map_err(rendezvous_err)?;

    // Push notify subscribers of peer mailbox
    info!(mailbox_id = %peer_mailbox_id, "Pushing notification to mailbox");
    state.push.notify(&peer_mailbox_id, msg_json).await;

    Ok(StatusCode::ACCEPTED)
}

#[instrument(skip(state, payload))]
async fn mailbox_recv(
    State(state): State<AppState>,
    Json(payload): Json<MailboxSendRequest>,
) -> Result<(StatusCode, Json<MailboxRecvResponse>), (StatusCode, Json<ErrorResponse>)> {
    
    let response = state.rendezvous_service.recv_messages(payload.mailbox_id)
        .await
        .map_err(rendezvous_err)?;

    Ok((StatusCode::OK, Json(response)))
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
    if state.rendezvous_service.verify_mailbox(&mailbox_id).await.is_err() {
        return StatusCode::NOT_FOUND.into_response();
    }

    ws.on_upgrade(move |socket| handle_ws(socket, state, mailbox_id))
}

async fn handle_ws(mut socket: WebSocket, state: AppState, mailbox_id: String) {
    let mut rx = state.push.subscribe(&mailbox_id).await;
    // Forward broadcast events to WebSocket client
    while let Ok(msg) = rx.recv().await {
        if socket.send(Message::Text(msg)).await.is_err() {
            break;
        }
    }
}
