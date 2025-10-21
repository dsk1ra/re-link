use crate::shared::{
    ClientId, HeartbeatRequest, HeartbeatResponse, RegisterRequest, RegisterResponse, SignalEnvelope,
    SignalFetchRequest, SignalFetchResponse, SignalSubmitRequest
};
use std::{
    collections::HashMap,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use thiserror::Error;
use tokio::sync::RwLock;
use tracing::{debug, warn};
use uuid::Uuid;

#[derive(Debug)]
struct ClientRecord {
    #[allow(dead_code)]
    device_label: String,
    session_token: String,
    #[allow(dead_code)]
    registered_at: Instant,
    last_heartbeat: Instant
}

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("client not found")]
    ClientNotFound,
    #[error("session token rejected")]
    InvalidToken,
}

#[derive(Debug)]
pub struct SessionRegistry {
    clients: RwLock<HashMap<ClientId, ClientRecord>>,
    messages: RwLock<Vec<SignalEnvelope>>,
    session_ttl: Duration,
    heartbeat_interval: Duration,
}

impl SessionRegistry {
    pub fn new(session_ttl: Duration, heartbeat_interval: Duration) -> Self {
        Self {
            clients: RwLock::new(HashMap::new()),
            messages: RwLock::new(Vec::new()),
            session_ttl,
            heartbeat_interval,
        }
    }

    fn verify_client<'a>(&'a self, clients: &'a HashMap<ClientId, ClientRecord>, client_id: &ClientId, session_token: &str) -> Result<&'a ClientRecord, RegistryError> {
        let record = clients.get(client_id).ok_or(RegistryError::ClientNotFound)?;
        if record.session_token != session_token { return Err(RegistryError::InvalidToken); }
        Ok(record)
    }

    pub async fn register(&self, request: RegisterRequest) -> RegisterResponse {
        self.prune_expired().await;

        let client_id = Uuid::new_v4();
        let session_token = Uuid::new_v4().to_string();
        // Assign incremental display name based on current active clients count + 1
        let display_name = {
            let clients = self.clients.read().await;
            let n = clients.len() + 1;
            format!("Client {}", n)
        };
        let new_record = ClientRecord {
            device_label: request.device_label,
            session_token: session_token.clone(),
            registered_at: Instant::now(),
            last_heartbeat: Instant::now(),
        };

        self.clients.write().await.insert(client_id, new_record);

        RegisterResponse {
            client_id,
            session_token,
            heartbeat_interval_secs: self.heartbeat_interval.as_secs(),
            display_name,
        }
    }

    pub async fn heartbeat(&self, request: HeartbeatRequest) -> Result<HeartbeatResponse, RegistryError> {
        self.prune_expired().await;

        let mut clients = self.clients.write().await;
        let record = clients.get_mut(&request.client_id).ok_or(RegistryError::ClientNotFound)?;
        if record.session_token != request.session_token {
            return Err(RegistryError::InvalidToken);
        }
        record.last_heartbeat = Instant::now();

        Ok(HeartbeatResponse {
            next_heartbeat_secs: self.heartbeat_interval.as_secs(),
        })
    }

    pub async fn enqueue_signal(&self, submit: SignalSubmitRequest) -> Result<(), RegistryError> {
        self.prune_expired().await;

        let clients = self.clients.read().await;
        let record = clients.get(&submit.envelope.from).ok_or(RegistryError::ClientNotFound)?;
        if record.session_token != submit.session_token {
            return Err(RegistryError::InvalidToken);
        }
        drop(clients);

        let mut envelope = submit.envelope;
        envelope.created_at_epoch_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or_default();

        let mut messages = self.messages.write().await;
        messages.push(envelope);
        Ok(())
    }

    pub async fn fetch_signals(&self, request: SignalFetchRequest) -> Result<SignalFetchResponse, RegistryError> {
        self.prune_expired().await;

        let clients = self.clients.read().await;
        let record = clients.get(&request.client_id).ok_or(RegistryError::ClientNotFound)?;
        if record.session_token != request.session_token {
            return Err(RegistryError::InvalidToken);
        }
        drop(clients);

        let mut messages = self.messages.write().await;
        let mut collected = Vec::new();
        messages.retain(|msg| {
            if msg.to == request.client_id {
                collected.push(msg.clone());
                false
            } else {
                true
            }
        });

        Ok(SignalFetchResponse { messages: collected })
    }

    pub async fn verify_session(&self, client_id: &ClientId, session_token: &str) -> Result<(), RegistryError> {
        let clients = self.clients.read().await;
        let _ = self.verify_client(&clients, client_id, session_token)?;
        Ok(())
    }

    async fn prune_expired(&self) {
        let expiration_threshold = self.session_ttl;

        let mut clients = self.clients.write().await;
        let mut stale_clients = Vec::new();
        for (client_id, record) in clients.iter() {
            if record.last_heartbeat.elapsed() >= expiration_threshold {
                stale_clients.push(*client_id);
            }
        }
        if !stale_clients.is_empty() {
            for client_id in &stale_clients {
                clients.remove(client_id);
            }
            debug!(?stale_clients, "pruned expired clients");

            let mut messages = self.messages.write().await;
            messages.retain(|msg| {
                let drop_msg = stale_clients.contains(&msg.from) || stale_clients.contains(&msg.to);
                if drop_msg {
                    warn!(from = %msg.from, to = %msg.to, "dropping signal for expired client");
                }
                !drop_msg
            });
        }
    }
}
