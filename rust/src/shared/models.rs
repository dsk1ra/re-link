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

// ---------- Ephemeral Room Models ----------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomCreateRequest {
    pub client_id: ClientId,
    pub session_token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomCreateResponse {
    pub room_id: String,         // 32-char hex
    pub password: String,        // 32-char base64
    pub initiator_token: String, // 64-char hex
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ttl_seconds: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at_epoch_ms: Option<u128>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomJoinRequest {
    pub client_id: ClientId,
    pub session_token: String,
    pub room_id: String,
    pub password: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomJoinResponse {
    pub initiator_token: String, // 64-char hex
    pub receiver_token: String,  // 64-char hex
}
