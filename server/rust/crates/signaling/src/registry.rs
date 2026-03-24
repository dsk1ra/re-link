use crate::repository::session_repository::{ClientRecord, InMemorySessionRepository};
use shared::models::{
    ClientId, HeartbeatRequest, HeartbeatResponse, RegisterRequest, RegisterResponse,
    SignalFetchRequest, SignalFetchResponse, SignalSubmitRequest,
};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use thiserror::Error;
use tracing::debug;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("client not found")]
    ClientNotFound,
    #[error("session token rejected")]
    InvalidToken,
}

#[derive(Debug)]
pub struct SessionRegistry {
    repository: InMemorySessionRepository,
    session_ttl: Duration,
    heartbeat_interval: Duration,
}

impl SessionRegistry {
    fn normalize_device_label(device_label: &str) -> String {
        let trimmed = device_label.trim();
        if trimmed.is_empty() {
            return "Peer".to_string();
        }

        // Keep display labels compact for status banners.
        let mut normalized = trimmed.chars().take(24).collect::<String>();
        if normalized.is_empty() {
            normalized = "Peer".to_string();
        }
        normalized
    }

    fn build_display_name(device_label: &str, client_id: &ClientId) -> String {
        let label = Self::normalize_device_label(device_label);
        let id = client_id.to_string();
        let short = id.split('-').next().unwrap_or("unknown");
        format!("{}-{}", label, short)
    }

    pub fn new(session_ttl: Duration, heartbeat_interval: Duration) -> Self {
        Self {
            repository: InMemorySessionRepository::new(),
            session_ttl,
            heartbeat_interval,
        }
    }

    async fn verify_client(
        &self,
        client_id: &ClientId,
        session_token: &str,
    ) -> Result<ClientRecord, RegistryError> {
        let record = self
            .repository
            .get_client(client_id)
            .await
            .ok_or(RegistryError::ClientNotFound)?;
        if record.session_token != session_token {
            return Err(RegistryError::InvalidToken);
        }
        Ok(record)
    }

    pub async fn register(&self, request: RegisterRequest) -> RegisterResponse {
        self.prune_expired().await;

        let client_id = Uuid::new_v4();
        let session_token = Uuid::new_v4().to_string();
        let display_name = Self::build_display_name(&request.device_label, &client_id);
        let new_record = ClientRecord {
            device_label: request.device_label,
            session_token: session_token.clone(),
            registered_at: Instant::now(),
            last_heartbeat: Instant::now(),
        };

        self.repository.insert_client(client_id, new_record).await;

        RegisterResponse {
            client_id,
            session_token,
            heartbeat_interval_secs: self.heartbeat_interval.as_secs(),
            display_name,
        }
    }

    pub async fn heartbeat(
        &self,
        request: HeartbeatRequest,
    ) -> Result<HeartbeatResponse, RegistryError> {
        self.prune_expired().await;

        // Verify first
        self.verify_client(&request.client_id, &request.session_token)
            .await?;

        // Update
        if !self
            .repository
            .update_client_heartbeat(&request.client_id, Instant::now())
            .await
        {
            return Err(RegistryError::ClientNotFound);
        }

        Ok(HeartbeatResponse {
            next_heartbeat_secs: self.heartbeat_interval.as_secs(),
        })
    }

    pub async fn enqueue_signal(&self, submit: SignalSubmitRequest) -> Result<(), RegistryError> {
        self.prune_expired().await;

        self.verify_client(&submit.envelope.from, &submit.session_token)
            .await?;

        let mut envelope = submit.envelope;
        envelope.created_at_epoch_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or_default();

        self.repository.add_message(envelope).await;
        Ok(())
    }

    pub async fn fetch_signals(
        &self,
        request: SignalFetchRequest,
    ) -> Result<SignalFetchResponse, RegistryError> {
        self.prune_expired().await;

        self.verify_client(&request.client_id, &request.session_token)
            .await?;

        let collected = self
            .repository
            .get_messages_for_client(&request.client_id)
            .await;

        Ok(SignalFetchResponse {
            messages: collected,
        })
    }

    pub async fn verify_session(
        &self,
        client_id: &ClientId,
        session_token: &str,
    ) -> Result<(), RegistryError> {
        self.verify_client(client_id, session_token).await?;
        Ok(())
    }

    async fn prune_expired(&self) {
        let expiration_threshold = self.session_ttl;
        let stale_clients = self
            .repository
            .prune_stale_clients(expiration_threshold)
            .await;

        if !stale_clients.is_empty() {
            debug!(?stale_clients, "pruned expired clients");
            // Messages pruning is now handled by the repository helper or we can do it explicitly
            // Ideally the repository handles the cascade delete or similar logic.
            // I added `prune_messages_for_clients` to the repository.
            self.repository
                .prune_messages_for_clients(&stale_clients)
                .await;
        }
    }
}
