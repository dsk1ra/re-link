use crate::shared::{
    HeartbeatRequest, RegisterRequest, RoomCreateRequest, RoomCreateResponse, RoomJoinRequest,
    RoomJoinResponse, RoomStatusRequest, RoomStatusResponse, SignalFetchRequest,
    SignalFetchResponse, SignalSubmitRequest,
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
use rand::RngCore as _;
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
use aes_gcm::{Aes256Gcm, aead::{Aead, KeyInit}};
use aes_gcm::aead::generic_array::GenericArray;

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
    .route("/room/status", post(room_status))
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

#[derive(Debug, Deserialize, Serialize, Clone)]
struct EncryptedValueV1 {
    enc: bool,
    v: u8,
    nonce_b64: String,
    ct_b64: String,
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

fn encrypt_maybe(plain: &str, cfg: &SignalingServerConfig) -> anyhow::Result<String> {
    if !cfg.redis_encrypt_payloads {
        return Ok(plain.to_string());
    }
    let key_bytes = cfg.redis_encryption_key.as_ref().ok_or_else(|| anyhow::anyhow!(
        "SIGNALING_REDIS_ENCRYPT is true but SIGNALING_REDIS_ENC_KEY_B64 is missing or invalid (needs 32 bytes)"
    ))?;
    let key = GenericArray::from_slice(key_bytes);
    let cipher = Aes256Gcm::new(key);
    let mut nonce = [0u8; 12];
    let mut rng = OsRng;
    rng.fill_bytes(&mut nonce);
    let ct = cipher
        .encrypt(GenericArray::from_slice(&nonce), plain.as_bytes())
        .map_err(|e| anyhow::anyhow!("encrypt error: {e}"))?;
    let wrap = EncryptedValueV1 {
        enc: true,
        v: 1,
        nonce_b64: B64.encode(nonce),
        ct_b64: B64.encode(ct),
    };
    Ok(serde_json::to_string(&wrap)?)
}

fn try_decrypt(loaded: &str, cfg: &SignalingServerConfig) -> anyhow::Result<Option<String>> {
    // Best-effort: if looks like encrypted wrapper and encryption enabled with key, decrypt
    if !cfg.redis_encrypt_payloads {
        return Ok(None);
    }
    let key_bytes = match cfg.redis_encryption_key.as_ref() {
        Some(k) => k,
        None => return Ok(None),
    };
    let wrap: EncryptedValueV1 = match serde_json::from_str::<EncryptedValueV1>(loaded) {
        Ok(w) if w.enc && w.v == 1 => w,
        _ => return Ok(None),
    };
    let nonce = base64::engine::general_purpose::STANDARD
        .decode(wrap.nonce_b64)
        .map_err(|e| anyhow::anyhow!("nonce decode: {e}"))?;
    let ct = base64::engine::general_purpose::STANDARD
        .decode(wrap.ct_b64)
        .map_err(|e| anyhow::anyhow!("ct decode: {e}"))?;
    let key = GenericArray::from_slice(key_bytes);
    let cipher = Aes256Gcm::new(key);
    let pt = cipher
        .decrypt(GenericArray::from_slice(&nonce), ct.as_ref())
        .map_err(|e| anyhow::anyhow!("decrypt error: {e}"))?;
    let plain = String::from_utf8(pt).map_err(|e| anyhow::anyhow!("utf8 error: {e}"))?;
    Ok(Some(plain))
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
    let key = format!("{}:{}", state.config.redis_key_prefix, key);
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
    let payload_json_plain = serde_json::to_string(&store).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: e.to_string(),
            }),
        )
    })?;
    let payload_json = encrypt_maybe(&payload_json_plain, &state.config).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse { message: e.to_string() }),
        )
    })?;
    // Prefer SET with EX and NX to avoid accidental overwrite on extremely unlikely collision
    let set_res: Option<String> = redis::cmd("SET")
        .arg(&key)
        .arg(&payload_json)
        .arg("EX")
        .arg(ttl_secs)
        .arg("NX")
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
    if set_res.is_none() {
        // NX failed (key already exists) -> treat as conflict
        return Err((
            StatusCode::CONFLICT,
            Json(ErrorResponse {
                message: "Room allocation conflict, please retry".to_string(),
            }),
        ));
    }

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

    let key = format!("{}:room:{}", state.config.redis_key_prefix, payload.room_id);
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
    // Try plaintext parse; if it fails, attempt decrypt-then-parse
    let room: RoomStored = match serde_json::from_str(&json) {
        Ok(r) => r,
        Err(_) => {
            if let Ok(Some(plain)) = try_decrypt(&json, &state.config) {
                serde_json::from_str(&plain).map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(ErrorResponse { message: e.to_string() }),
                    )
                })?
            } else {
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse { message: "Invalid room payload".to_string() }),
                ));
            }
        }
    };

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

    // generate receiver token, mark as joined and delete room payload (privacy)
    let receiver_token = gen_hex(32);
    // set a joined flag with short TTL to reflect connection status to initiator
    let joined_key = format!(
        "{}:room_joined:{}",
        state.config.redis_key_prefix, payload.room_id
    );
    let _: () = redis::cmd("SETEX")
        .arg(&joined_key)
        .arg(state.config.joined_flag_ttl.as_secs())
        .arg("1")
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
    // delete the room data
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

#[instrument(skip(state, payload))]
async fn room_status(
    State(state): State<AppState>,
    Json(payload): Json<RoomStatusRequest>,
) -> Result<(StatusCode, Json<RoomStatusResponse>), (StatusCode, Json<ErrorResponse>)> {
    // verify session
    state
        .registry
        .verify_session(&payload.client_id, &payload.session_token)
        .await
        .map_err(registry_err)?;

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

    let key = format!("{}:room:{}", state.config.redis_key_prefix, payload.room_id);
    let joined_key = format!(
        "{}:room_joined:{}",
        state.config.redis_key_prefix, payload.room_id
    );

    // if joined flag exists -> connected
    let joined: Option<String> = redis::cmd("GET")
        .arg(&joined_key)
        .query_async(&mut conn)
        .await
        .unwrap_or(None);
    if joined.is_some() {
        return Ok((
            StatusCode::OK,
            Json(RoomStatusResponse {
                status: "joined".to_string(),
                ttl_seconds: None,
            }),
        ));
    }

    // check if room exists
    let json: Option<String> = redis::cmd("GET")
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

    if json.is_some() {
        // Not joined yet; return waiting with approximate TTL using PTTL
        let ttl_ms: i64 = redis::cmd("PTTL")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .unwrap_or(-2);
        let ttl_seconds = if ttl_ms >= 0 { Some((ttl_ms as u64) / 1000) } else { None };
        return Ok((
            StatusCode::OK,
            Json(RoomStatusResponse {
                status: "waiting".to_string(),
                ttl_seconds,
            }),
        ));
    }

    // No room and no joined flag -> expired
    Ok((
        StatusCode::OK,
        Json(RoomStatusResponse {
            status: "expired".to_string(),
            ttl_seconds: None,
        }),
    ))
}

// Root handler for "/"
async fn root() -> impl IntoResponse {
    (StatusCode::OK, "Server OK!")
}
