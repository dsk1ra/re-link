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
// ---------- Connection Link Models (Blind Rendezvous) ----------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionInitRequest {
    pub client_id: ClientId,
    pub session_token: String,
    pub rendezvous_id_b64: String,  // high-entropy random ID from initiator
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionInitResponse {
    pub mailbox_id: String,          // opaque ID for initiator
    pub expires_at_epoch_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionJoinRequest {
    pub token_b64: String,  // rendezvous_id_b64 extracted from link
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionJoinResponse {
    pub mailbox_id: String,          // opaque ID for responder
    pub expires_at_epoch_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MailboxSendRequest {
    pub mailbox_id: String,
    pub ciphertext_b64: String,  // opaque encrypted blob from client
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MailboxMessage {
    pub from_mailbox_id: String,
    pub ciphertext_b64: String,
    pub sequence: u64,
    pub timestamp_epoch_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MailboxRecvResponse {
    pub messages: Vec<MailboxMessage>,
    pub last_sequence: u64,
}
