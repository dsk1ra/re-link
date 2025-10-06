use crate::shared::{
    HeartbeatRequest, RegisterRequest, SignalFetchRequest, SignalFetchResponse, SignalSubmitRequest,
    QueueProduceRequest, QueueConsumeRequest, QueueListRequest, QueueConsumeResponse, QueueListResponse,
};
use crate::signaling::{RegistryError, SessionRegistry, SignalingServerConfig};
use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::Serialize;
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::{info, instrument};

#[derive(Clone)]
struct AppState {
    registry: Arc<SessionRegistry>,
    config: Arc<SignalingServerConfig>,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    message: String,
}

pub async fn run_server(config: SignalingServerConfig) -> anyhow::Result<()> {
    let registry = Arc::new(SessionRegistry::new(config.session_ttl, config.heartbeat_interval));
    let state = AppState {
        registry,
        config: Arc::new(config),
    };

    let router = Router::new()
        .route("/", get(root))
        .route("/health", get(healthcheck))
        .route("/register", post(register))
        .route("/heartbeat", post(heartbeat))
        .route("/signal", post(send_signal))
        .route("/signal/fetch", post(fetch_signal))
    // queue endpoints
    .route("/queue/produce", post(queue_produce))
    .route("/queue/consume", post(queue_consume))
    .route("/queue/list", post(queue_list))
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
async fn register(State(state): State<AppState>, Json(payload): Json<RegisterRequest>) -> impl IntoResponse {
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

// -------- Queue handlers --------
#[instrument(skip(state, payload))]
async fn queue_produce(
    State(state): State<AppState>,
    Json(payload): Json<QueueProduceRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    state
        .registry
        .queue_produce(payload)
        .await
        .map(|()| StatusCode::ACCEPTED)
        .map_err(registry_err)
}

#[instrument(skip(state, payload))]
async fn queue_consume(
    State(state): State<AppState>,
    Json(payload): Json<QueueConsumeRequest>,
) -> Result<(StatusCode, Json<QueueConsumeResponse>), (StatusCode, Json<ErrorResponse>)> {
    state
        .registry
        .queue_consume(payload)
        .await
        .map(|resp| (StatusCode::OK, Json(resp)))
        .map_err(registry_err)
}

#[instrument(skip(state, payload))]
async fn queue_list(
    State(state): State<AppState>,
    Json(payload): Json<QueueListRequest>,
) -> Result<(StatusCode, Json<QueueListResponse>), (StatusCode, Json<ErrorResponse>)> {
    state
        .registry
        .queue_list(payload)
        .await
        .map(|resp| (StatusCode::OK, Json(resp)))
        .map_err(registry_err)
}

fn registry_err(err: RegistryError) -> (StatusCode, Json<ErrorResponse>) {
    let status = match err {
        RegistryError::ClientNotFound => StatusCode::NOT_FOUND,
        RegistryError::InvalidToken => StatusCode::UNAUTHORIZED,
    };
    (status, Json(ErrorResponse { message: err.to_string() }))
}

// Root handler for "/"
async fn root() -> impl IntoResponse {
    (StatusCode::OK, "Server OK!")
}
