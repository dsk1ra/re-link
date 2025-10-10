use serde::{Deserialize, Serialize};
use std::time::Duration;
use uuid::Uuid;

pub type ClientId = Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterRequest {
    pub device_label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterResponse {
    pub client_id: ClientId,
    pub session_token: String,
    pub heartbeat_interval_secs: u64,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatRequest {
    pub client_id: ClientId,
    pub session_token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatResponse {
    pub next_heartbeat_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalEnvelope {
    pub from: ClientId,
    pub to: ClientId,
    pub payload: String,
    pub created_at_epoch_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalSubmitRequest {
    pub session_token: String,
    pub envelope: SignalEnvelope,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalFetchRequest {
    pub client_id: ClientId,
    pub session_token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SignalFetchResponse {
    pub messages: Vec<SignalEnvelope>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalingClientConfigDto {
    pub base_url: String,
    pub heartbeat_interval_secs: u64,
}

impl SignalingClientConfigDto {
    pub fn new(base_url: impl Into<String>, heartbeat_interval: Duration) -> Self {
        Self {
            base_url: base_url.into(),
            heartbeat_interval_secs: heartbeat_interval.as_secs(),
        }
    }
}

// ---------- Chat/Clients Models ----------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientInfoDto {
    pub client_id: ClientId,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientsListResponse {
    pub clients: Vec<ClientInfoDto>,
}

// ---------- Global Chat Models ----------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatSendRequest {
    pub client_id: ClientId,
    pub session_token: String,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatListRequest {
    pub client_id: ClientId,
    pub session_token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessageDto {
    pub id: u64,
    pub from_client_id: ClientId,
    pub from_display_name: String,
    pub text: String,
    pub created_at_epoch_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatListResponse {
    pub messages: Vec<ChatMessageDto>,
}
