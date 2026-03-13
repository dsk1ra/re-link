use crate::repository::redis_repository::{MailboxMessageStored, MailboxState, RedisRepository};
use shared::connection;
use shared::models::{
    ConnectionInitResponse, ConnectionJoinResponse, MailboxMessage, MailboxRecvResponse,
};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Clone)]
pub struct RendezvousService {
    repo: RedisRepository,
    mailbox_ttl: Duration,
    rendezvous_ttl: Duration,
}

#[derive(Debug, thiserror::Error)]
pub enum RendezvousError {
    #[error("Redis error: {0}")]
    Redis(#[from] anyhow::Error),
    #[error("Mailbox not found")]
    MailboxNotFound,
    #[error("Session expired")]
    SessionExpired,
    #[error("Invalid or expired token")]
    InvalidToken,
    #[error("Session already has a peer")]
    SessionAlreadyPaired,
    #[error("No peer connected")]
    NoPeerConnected,
}

impl RendezvousService {
    pub fn new(repo: RedisRepository, mailbox_ttl: Duration, rendezvous_ttl: Duration) -> Self {
        Self {
            repo,
            mailbox_ttl,
            rendezvous_ttl,
        }
    }

    pub async fn init_connection(
        &self,
        rendezvous_id_b64: String,
    ) -> Result<ConnectionInitResponse, RendezvousError> {
        let mailbox_id = connection::gen_mailbox_id();

        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| RendezvousError::Redis(anyhow::Error::new(e)))?
            .as_millis();
        let expires_ms = now_ms + self.mailbox_ttl.as_millis();

        let mailbox_state = MailboxState {
            mailbox_id: mailbox_id.clone(),
            peer_mailbox_id: None,
            created_at_epoch_ms: now_ms,
            expires_at_epoch_ms: expires_ms,
        };

        self.repo
            .save_mailbox_meta(&mailbox_state, self.mailbox_ttl.as_secs())
            .await
            .map_err(RendezvousError::Redis)?;
        self.repo
            .clear_mailbox_messages(&mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;

        // Store rendezvous mapping
        self.repo
            .save_rendezvous(
                &rendezvous_id_b64,
                &mailbox_id,
                self.rendezvous_ttl.as_secs(),
            )
            .await
            .map_err(RendezvousError::Redis)?;

        Ok(ConnectionInitResponse {
            mailbox_id,
            expires_at_epoch_ms: expires_ms,
        })
    }

    pub async fn join_connection(
        &self,
        token_b64: String,
    ) -> Result<(ConnectionJoinResponse, String, String), RendezvousError> {
        // Returns (Response, InitiatorMailboxId, JoinMessageJson)

        let initiator_mailbox_id = self
            .repo
            .get_and_delete_rendezvous(&token_b64)
            .await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::InvalidToken)?;

        let mut initiator_state = self
            .repo
            .get_mailbox_meta(&initiator_mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::MailboxNotFound)?;

        if initiator_state.peer_mailbox_id.is_some() {
            return Err(RendezvousError::SessionAlreadyPaired);
        }

        let responder_mailbox_id = connection::gen_mailbox_id();

        // Link them
        initiator_state.peer_mailbox_id = Some(responder_mailbox_id.clone());
        self.repo
            .save_mailbox_meta(&initiator_state, self.mailbox_ttl.as_secs())
            .await
            .map_err(RendezvousError::Redis)?;

        let responder_state = MailboxState {
            mailbox_id: responder_mailbox_id.clone(),
            peer_mailbox_id: Some(initiator_mailbox_id.clone()),
            created_at_epoch_ms: initiator_state.created_at_epoch_ms,
            expires_at_epoch_ms: initiator_state.expires_at_epoch_ms,
        };
        self.repo
            .save_mailbox_meta(&responder_state, self.mailbox_ttl.as_secs())
            .await
            .map_err(RendezvousError::Redis)?;
        self.repo
            .clear_mailbox_messages(&responder_mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;

        // Create join message for initiator
        let seq = self
            .repo
            .get_message_count(&initiator_mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;
        let join_msg = MailboxMessageStored {
            from_mailbox_id: responder_mailbox_id.clone(),
            ciphertext_b64: "".to_string(),
            sequence: seq,
            timestamp_epoch_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("SystemTime is before UNIX_EPOCH when creating join message timestamp")
                .as_millis(),
        };

        self.repo
            .push_message(&initiator_mailbox_id, &join_msg, self.mailbox_ttl.as_secs())
            .await
            .map_err(RendezvousError::Redis)?;

        let join_json = match serde_json::to_string(&join_msg) {
            Ok(json) => json,
            Err(err) => {
                eprintln!(
                    "Failed to serialize join message for initiator '{}': {}",
                    initiator_mailbox_id, err
                );
                String::new()
            }
        };

        Ok((
            ConnectionJoinResponse {
                mailbox_id: responder_mailbox_id,
                expires_at_epoch_ms: responder_state.expires_at_epoch_ms,
            },
            initiator_mailbox_id,
            join_json,
        ))
    }

    pub async fn send_message(
        &self,
        mailbox_id: String,
        ciphertext_b64: String,
    ) -> Result<(String, String), RendezvousError> {
        // Returns (PeerMailboxId, MessageJson)

        let mailbox_state = self
            .repo
            .get_mailbox_meta(&mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::MailboxNotFound)?;

        let peer_mailbox_id = mailbox_state
            .peer_mailbox_id
            .ok_or(RendezvousError::NoPeerConnected)?;

        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("SystemTime before UNIX_EPOCH when computing now_ms in send_message")
            .as_millis();
        if now_ms >= mailbox_state.expires_at_epoch_ms {
            return Err(RendezvousError::SessionExpired);
        }

        let seq = self
            .repo
            .get_message_count(&peer_mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;

        let msg = MailboxMessageStored {
            from_mailbox_id: mailbox_id,
            ciphertext_b64,
            sequence: seq,
            timestamp_epoch_ms: now_ms,
        };
        self.repo
            .push_message(&peer_mailbox_id, &msg, self.mailbox_ttl.as_secs())
            .await
            .map_err(RendezvousError::Redis)?;

        let msg_json = serde_json::to_string(&msg).unwrap_or_default();
        Ok((peer_mailbox_id, msg_json))
    }

    pub async fn recv_messages(
        &self,
        mailbox_id: String,
    ) -> Result<MailboxRecvResponse, RendezvousError> {
        let _ = self
            .repo
            .get_mailbox_meta(&mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::MailboxNotFound)?;

        let stored_msgs = self
            .repo
            .get_messages(&mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;

        let last_sequence = stored_msgs.last().map(|m| m.sequence).unwrap_or(0);

        let messages: Vec<MailboxMessage> = stored_msgs
            .into_iter()
            .map(|s| MailboxMessage {
                from_mailbox_id: s.from_mailbox_id,
                ciphertext_b64: s.ciphertext_b64,
                sequence: s.sequence,
                timestamp_epoch_ms: s.timestamp_epoch_ms,
            })
            .collect();

        Ok(MailboxRecvResponse {
            messages,
            last_sequence,
        })
    }

    pub async fn verify_mailbox(&self, mailbox_id: &str) -> Result<bool, RendezvousError> {
        let mailbox_state = self
            .repo
            .get_mailbox_meta(mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;

        let Some(state) = mailbox_state else {
            return Ok(false);
        };

        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("SystemTime before UNIX_EPOCH when verifying mailbox")
            .as_millis();

        Ok(now_ms < state.expires_at_epoch_ms)
    }

    pub async fn close_connection(&self, mailbox_id: String) -> Result<(), RendezvousError> {
        let mailbox_state = self
            .repo
            .get_mailbox_meta(&mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;

        let Some(state) = mailbox_state else {
            return Ok(());
        };

        self.repo
            .delete_mailbox(&state.mailbox_id)
            .await
            .map_err(RendezvousError::Redis)?;

        if let Some(peer_id) = state.peer_mailbox_id.as_ref() {
            self.repo
                .delete_mailbox(peer_id)
                .await
                .map_err(RendezvousError::Redis)?;
        }

        Ok(())
    }
}
