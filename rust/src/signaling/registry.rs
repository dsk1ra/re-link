use crate::shared::{
    ClientId, HeartbeatRequest, HeartbeatResponse, RegisterRequest, RegisterResponse, SignalEnvelope,
    SignalFetchRequest, SignalFetchResponse, SignalSubmitRequest, QueueProduceRequest, QueueConsumeRequest,
    QueueListRequest, QueueConsumeResponse, QueueListResponse, QueueItemDto, ClientInfoDto, ClientsListResponse, ChatSendRequest, ChatListRequest, ChatListResponse, ChatMessageDto,
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
    last_heartbeat: Instant,
    display_name: String,
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
    queue_items: RwLock<Vec<QueueStoredItem>>,
    chat_messages: RwLock<Vec<ChatStoredMsg>>,
    session_ttl: Duration,
    heartbeat_interval: Duration,
}

impl SessionRegistry {
    pub fn new(session_ttl: Duration, heartbeat_interval: Duration) -> Self {
        Self {
            clients: RwLock::new(HashMap::new()),
            messages: RwLock::new(Vec::new()),
            queue_items: RwLock::new(Vec::new()),
            chat_messages: RwLock::new(Vec::new()),
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
            display_name: display_name.clone(),
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

    // -------- Queue API --------
    pub async fn queue_produce(&self, req: QueueProduceRequest) -> Result<(), RegistryError> {
        self.prune_expired().await;
        let clients = self.clients.read().await;
        self.verify_client(&clients, &req.client_id, &req.session_token)?;
        drop(clients);
        let mut items = self.queue_items.write().await;
        let id = items.len() as u64 + 1;
        let created_at_ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or_default();
        items.push(QueueStoredItem { id, payload: req.payload, created_at_epoch_ms: created_at_ms });
        Ok(())
    }

    pub async fn queue_consume(&self, req: QueueConsumeRequest) -> Result<QueueConsumeResponse, RegistryError> {
        self.prune_expired().await;
        let clients = self.clients.read().await;
        self.verify_client(&clients, &req.client_id, &req.session_token)?;
        drop(clients);
        let mut items = self.queue_items.write().await;
        if items.is_empty() {
            return Ok(QueueConsumeResponse { item: None });
        }
        // FIFO: remove first
        let first = items.remove(0);
        Ok(QueueConsumeResponse { item: Some(first.into_dto()) })
    }

    pub async fn queue_list(&self, req: QueueListRequest) -> Result<QueueListResponse, RegistryError> {
        self.prune_expired().await;
        let clients = self.clients.read().await;
        self.verify_client(&clients, &req.client_id, &req.session_token)?;
        drop(clients);
        let items = self.queue_items.read().await;
        let dtos = items.iter().map(|i| i.clone().into_dto()).collect();
        Ok(QueueListResponse { items: dtos })
    }

    // -------- Chat helpers --------
    pub async fn list_clients(&self) -> ClientsListResponse {
        let clients = self.clients.read().await;
        let mut list: Vec<ClientInfoDto> = clients
            .iter()
            .map(|(id, rec)| ClientInfoDto { client_id: *id, display_name: rec.display_name.clone() })
            .collect();
        // Deterministic ordering for UI
        list.sort_by_key(|c| c.display_name.clone());
        ClientsListResponse { clients: list }
    }

    // -------- Global chat API --------
    pub async fn chat_send(&self, req: ChatSendRequest) -> Result<(), RegistryError> {
        self.prune_expired().await;
        let clients = self.clients.read().await;
        let rec = self.verify_client(&clients, &req.client_id, &req.session_token)?;
        let from_display_name = rec.display_name.clone();
        drop(clients);
        let mut messages = self.chat_messages.write().await;
        let id = messages.len() as u64 + 1;
        let created_at_ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or_default();
        messages.push(ChatStoredMsg {
            id,
            from_client_id: req.client_id,
            from_display_name,
            text: req.text,
            created_at_epoch_ms: created_at_ms,
        });
        Ok(())
    }

    pub async fn chat_list(&self, req: ChatListRequest) -> Result<ChatListResponse, RegistryError> {
        self.prune_expired().await;
        let clients = self.clients.read().await;
        self.verify_client(&clients, &req.client_id, &req.session_token)?;
        drop(clients);
        let messages = self.chat_messages.read().await;
        let list = messages.iter().cloned().map(|m| m.into_dto()).collect();
        Ok(ChatListResponse { messages: list })
    }
}

#[derive(Debug, Clone)]
struct QueueStoredItem { id: u64, payload: String, created_at_epoch_ms: u128 }

impl QueueStoredItem { fn into_dto(self) -> QueueItemDto { QueueItemDto { id: self.id, payload: self.payload, created_at_epoch_ms: self.created_at_epoch_ms } } }

#[derive(Debug, Clone)]
struct ChatStoredMsg {
    id: u64,
    from_client_id: ClientId,
    from_display_name: String,
    text: String,
    created_at_epoch_ms: u128,
}

impl ChatStoredMsg {
    fn into_dto(self) -> ChatMessageDto {
        ChatMessageDto {
            id: self.id,
            from_client_id: self.from_client_id,
            from_display_name: self.from_display_name,
            text: self.text,
            created_at_epoch_ms: self.created_at_epoch_ms,
        }
    }
}
