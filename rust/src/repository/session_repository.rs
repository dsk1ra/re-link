use crate::shared::{ClientId, SignalEnvelope};
use std::collections::HashMap;
use std::time::Instant;
use tokio::sync::RwLock;

#[derive(Debug, Clone)]
pub struct ClientRecord {
    pub device_label: String,
    pub session_token: String,
    pub registered_at: Instant,
    pub last_heartbeat: Instant,
}

#[derive(Debug)]
pub struct InMemorySessionRepository {
    clients: RwLock<HashMap<ClientId, ClientRecord>>,
    messages: RwLock<Vec<SignalEnvelope>>,
}

impl InMemorySessionRepository {
    pub fn new() -> Self {
        Self {
            clients: RwLock::new(HashMap::new()),
            messages: RwLock::new(Vec::new()),
        }
    }

    pub async fn insert_client(&self, client_id: ClientId, record: ClientRecord) {
        self.clients.write().await.insert(client_id, record);
    }

    pub async fn get_client(&self, client_id: &ClientId) -> Option<ClientRecord> {
        self.clients.read().await.get(client_id).cloned()
    }

    pub async fn update_client_heartbeat(&self, client_id: &ClientId, timestamp: Instant) -> bool {
        if let Some(record) = self.clients.write().await.get_mut(client_id) {
            record.last_heartbeat = timestamp;
            true
        } else {
            false
        }
    }

    pub async fn remove_client(&self, client_id: &ClientId) {
        self.clients.write().await.remove(client_id);
    }

    pub async fn get_client_count(&self) -> usize {
        self.clients.read().await.len()
    }

    pub async fn add_message(&self, message: SignalEnvelope) {
        self.messages.write().await.push(message);
    }

    pub async fn get_messages_for_client(&self, client_id: &ClientId) -> Vec<SignalEnvelope> {
        // This is a "consume" operation effectively for the client (fetch signals)
        // But the original implementation kept them in the main vec until pruned?
        // Wait, fetch_signals in registry.rs did:
        // messages.retain(|msg| if msg.to == client_id { collected.push(); false } else { true });
        // So it removes them.
        let mut messages = self.messages.write().await;
        let mut collected = Vec::new();
        messages.retain(|msg| {
            if &msg.to == client_id {
                collected.push(msg.clone());
                false
            } else {
                true
            }
        });
        collected
    }

    pub async fn prune_stale_clients(&self, expiration_threshold: std::time::Duration) -> Vec<ClientId> {
        let mut clients = self.clients.write().await;
        let mut stale_clients = Vec::new();
        for (client_id, record) in clients.iter() {
            if record.last_heartbeat.elapsed() >= expiration_threshold {
                stale_clients.push(*client_id);
            }
        }
        
        for client_id in &stale_clients {
            clients.remove(client_id);
        }
        stale_clients
    }

    pub async fn prune_messages_for_clients(&self, client_ids: &[ClientId]) {
        if client_ids.is_empty() { return; }
        let mut messages = self.messages.write().await;
        messages.retain(|msg| {
            !client_ids.contains(&msg.from) && !client_ids.contains(&msg.to)
        });
    }
}
