use crate::shared::{
    HeartbeatRequest, RegisterRequest, RoomCreateRequest, RoomCreateResponse, RoomJoinRequest,
    RoomJoinResponse, SignalFetchRequest, SignalFetchResponse, SignalSubmitRequest,
};
use crate::signaling::{RegistryError, SessionRegistry, SignalingServerConfig};
use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use rand::rngs::OsRng;
use rand_core::RngCore as _;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::{info, instrument};

use argon2::{password_hash::SaltString, Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use hex::ToHex;
use redis::AsyncCommands;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone)]
struct AppState {
    registry: Arc<SessionRegistry>,
    config: Arc<SignalingServerConfig>,
    redis: redis::Client,
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
    let redis = redis::Client::open(config.redis_url.clone())?;
    let state = AppState {
        registry,
        config: Arc::new(config),
        redis,
    };

    let router = Router::new()
        .route("/", get(root))
        .route("/health", get(healthcheck))
        .route("/register", post(register))
        .route("/heartbeat", post(heartbeat))
        .route("/signal", post(send_signal))
        .route("/signal/fetch", post(fetch_signal))
        // room pairing endpoints
        .route("/room/create", post(room_create))
        .route("/room/join", post(room_join))
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

// -------- Ephemeral Room (Redis) --------

#[derive(Debug, Deserialize, Serialize, Clone)]
struct RoomStored {
    hashed_password: String,
    initiator_token: String,
    created_at_epoch_ms: u128,
    expires_at_epoch_ms: u128,
    state: String,
    participants: u8,
}

fn gen_hex(len_bytes: usize) -> String {
    let mut buf = vec![0u8; len_bytes];
    let mut rng = OsRng;
    rng.fill_bytes(&mut buf);
    buf.encode_hex::<String>()
}

fn gen_b64(len_bytes: usize) -> String {
    let mut buf = vec![0u8; len_bytes];
    let mut rng = OsRng;
    rng.fill_bytes(&mut buf);
    B64.encode(buf)
}

#[instrument(skip(state, payload))]
async fn room_create(
    State(state): State<AppState>,
    Json(payload): Json<RoomCreateRequest>,
) -> Result<(StatusCode, Json<RoomCreateResponse>), (StatusCode, Json<ErrorResponse>)> {
    // verify client/session
    state
        .registry
        .verify_session(&payload.client_id, &payload.session_token)
        .await
        .map_err(registry_err)?;

    // generate credentials
    let room_id = gen_hex(16); // 32 hex chars
    let password_plain = gen_b64(24); // will be ~32 base64 chars
    let initiator_token = gen_hex(32); // 64 hex chars

    // hash password
    let mut rng = OsRng;
    let salt = SaltString::generate(&mut rng);
    let argon = Argon2::default();
    let hashed_password = argon
        .hash_password(password_plain.as_bytes(), &salt)
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("hash error: {e}"),
                }),
            )
        })?
        .to_string();

    // store in Redis with TTL
    let ttl_secs = state.config.room_ttl.as_secs();
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let expires_ms = now_ms + (state.config.room_ttl.as_millis() as u128);
    let store = RoomStored {
        hashed_password,
        initiator_token: initiator_token.clone(),
        created_at_epoch_ms: now_ms,
        expires_at_epoch_ms: expires_ms,
        state: "WAITING".to_string(),
        participants: 1,
    };
    let key = format!("room:{room_id}");
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
    let payload_json = serde_json::to_string(&store).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;
    let _: () = conn
        .set_ex(key, payload_json, ttl_secs)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: e.to_string(),
                }),
            )
        })?;

    let resp = RoomCreateResponse {
        room_id,
        password: password_plain,
        initiator_token,
        ttl_seconds: Some(state.config.room_ttl.as_secs()),
        expires_at_epoch_ms: Some(expires_ms),
    };
    Ok((StatusCode::OK, Json(resp)))
}

#[instrument(skip(state, payload))]
async fn room_join(
    State(state): State<AppState>,
    Json(payload): Json<RoomJoinRequest>,
) -> Result<(StatusCode, Json<RoomJoinResponse>), (StatusCode, Json<ErrorResponse>)> {
    // verify session
    state
        .registry
        .verify_session(&payload.client_id, &payload.session_token)
        .await
        .map_err(registry_err)?;

    let key = format!("room:{}", payload.room_id);
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

    let json: Option<String> = conn.get(&key).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;
    let Some(json) = json else {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                message: "Room not found".to_string(),
            }),
        ));
    };
    let room: RoomStored = serde_json::from_str(&json).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;

    // expiry check
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    if now_ms >= room.expires_at_epoch_ms {
        // try to delete and return Gone
        let _: () = redis::cmd("DEL")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .unwrap_or(());
        return Err((
            StatusCode::GONE,
            Json(ErrorResponse {
                message: "Room expired".to_string(),
            }),
        ));
    }

    // state checks
    if room.state != "WAITING" || room.participants >= 2 {
        return Err((
            StatusCode::CONFLICT,
            Json(ErrorResponse {
                message: "Room not available".to_string(),
            }),
        ));
    }

    // verify password
    let parsed_hash = PasswordHash::new(&room.hashed_password).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;
    Argon2::default()
        .verify_password(payload.password.as_bytes(), &parsed_hash)
        .map_err(|_| {
            (
                StatusCode::UNAUTHORIZED,
                Json(ErrorResponse {
                    message: "Invalid password".to_string(),
                }),
            )
        })?;

    // generate receiver token and delete room (privacy)
    let receiver_token = gen_hex(32);
    let _: () = redis::cmd("DEL")
        .arg(&key)
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

    let resp = RoomJoinResponse {
        initiator_token: room.initiator_token,
        receiver_token,
    };
    Ok((StatusCode::OK, Json(resp)))
}

// Root handler for "/"
async fn root() -> impl IntoResponse {
    (StatusCode::OK, "Server OK!")
}
