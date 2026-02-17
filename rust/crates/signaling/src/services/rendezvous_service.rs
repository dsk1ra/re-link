use crate::repository::redis_repository::{RedisRepository, MailboxState, MailboxMessageStored};
use shared::models::{
    ConnectionInitResponse, ConnectionJoinResponse, MailboxMessage, MailboxRecvResponse
};
use shared::connection;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone)]
pub struct RendezvousService {
    repo: RedisRepository,
    mailbox_ttl_secs: u64,
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
    pub fn new(repo: RedisRepository, mailbox_ttl_secs: u64) -> Self {
        Self {
            repo,
            mailbox_ttl_secs,
        }
    }

    pub async fn init_connection(&self, rendezvous_id_b64: String) -> Result<ConnectionInitResponse, RendezvousError> {
        let mailbox_id = connection::gen_mailbox_id();
        
        let now_ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis();
        let expires_ms = now_ms + (self.mailbox_ttl_secs as u128 * 1000);

        let mailbox_state = MailboxState {
            mailbox_id: mailbox_id.clone(),
            peer_mailbox_id: None,
            created_at_epoch_ms: now_ms,
            expires_at_epoch_ms: expires_ms,
        };

        self.repo.save_mailbox_meta(&mailbox_state, self.mailbox_ttl_secs).await.map_err(RendezvousError::Redis)?;
        self.repo.clear_mailbox_messages(&mailbox_id).await.map_err(RendezvousError::Redis)?;
        
        // Store rendezvous mapping (5 mins TTL)
        self.repo.save_rendezvous(&rendezvous_id_b64, &mailbox_id, 300).await.map_err(RendezvousError::Redis)?;

        Ok(ConnectionInitResponse {
            mailbox_id,
            expires_at_epoch_ms: expires_ms,
        })
    }

    pub async fn join_connection(&self, token_b64: String) -> Result<(ConnectionJoinResponse, String, String), RendezvousError> {
        // Returns (Response, InitiatorMailboxId, JoinMessageJson)
        
        let initiator_mailbox_id = self.repo.get_and_delete_rendezvous(&token_b64).await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::InvalidToken)?;

        let mut initiator_state = self.repo.get_mailbox_meta(&initiator_mailbox_id).await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::MailboxNotFound)?;

        if initiator_state.peer_mailbox_id.is_some() {
            return Err(RendezvousError::SessionAlreadyPaired);
        }

        let responder_mailbox_id = connection::gen_mailbox_id();
        
        // Link them
        initiator_state.peer_mailbox_id = Some(responder_mailbox_id.clone());
        self.repo.save_mailbox_meta(&initiator_state, self.mailbox_ttl_secs).await.map_err(RendezvousError::Redis)?;

        let responder_state = MailboxState {
            mailbox_id: responder_mailbox_id.clone(),
            peer_mailbox_id: Some(initiator_mailbox_id.clone()),
            created_at_epoch_ms: initiator_state.created_at_epoch_ms,
            expires_at_epoch_ms: initiator_state.expires_at_epoch_ms,
        };
        self.repo.save_mailbox_meta(&responder_state, self.mailbox_ttl_secs).await.map_err(RendezvousError::Redis)?;
        self.repo.clear_mailbox_messages(&responder_mailbox_id).await.map_err(RendezvousError::Redis)?;

        // Create join message for initiator
        let seq = self.repo.get_message_count(&initiator_mailbox_id).await.map_err(RendezvousError::Redis)?;
        let join_msg = MailboxMessageStored {
            from_mailbox_id: responder_mailbox_id.clone(),
            ciphertext_b64: "".to_string(),
            sequence: seq,
            timestamp_epoch_ms: SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis(),
        };

        self.repo.push_message(&initiator_mailbox_id, &join_msg, self.mailbox_ttl_secs).await.map_err(RendezvousError::Redis)?;

        let join_json = serde_json::to_string(&join_msg).unwrap_or_default();
        
        Ok((
            ConnectionJoinResponse {
                mailbox_id: responder_mailbox_id,
                expires_at_epoch_ms: responder_state.expires_at_epoch_ms,
            },
            initiator_mailbox_id,
            join_json
        ))
    }

    pub async fn send_message(&self, mailbox_id: String, ciphertext_b64: String) -> Result<(String, String), RendezvousError> {
        // Returns (PeerMailboxId, MessageJson)
        
        let mailbox_state = self.repo.get_mailbox_meta(&mailbox_id).await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::MailboxNotFound)?;

        let peer_mailbox_id = mailbox_state.peer_mailbox_id.ok_or(RendezvousError::NoPeerConnected)?;

        let now_ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis();
        if now_ms >= mailbox_state.expires_at_epoch_ms {
            return Err(RendezvousError::SessionExpired);
        }

        let seq = self.repo.get_message_count(&peer_mailbox_id).await.map_err(RendezvousError::Redis)?;

        let msg = MailboxMessageStored {
            from_mailbox_id: mailbox_id,
            ciphertext_b64,
            sequence: seq,
            timestamp_epoch_ms: now_ms,
        };

        self.repo.push_message(&peer_mailbox_id, &msg, self.mailbox_ttl_secs).await.map_err(RendezvousError::Redis)?;
        
        let msg_json = serde_json::to_string(&msg).unwrap_or_default();
        Ok((peer_mailbox_id, msg_json))
    }

    pub async fn recv_messages(&self, mailbox_id: String) -> Result<MailboxRecvResponse, RendezvousError> {
         let _ = self.repo.get_mailbox_meta(&mailbox_id).await
            .map_err(RendezvousError::Redis)?
            .ok_or(RendezvousError::MailboxNotFound)?;

         let stored_msgs = self.repo.get_messages(&mailbox_id).await.map_err(RendezvousError::Redis)?;
         
         let messages: Vec<MailboxMessage> = stored_msgs.into_iter().map(|s| MailboxMessage {
             from_mailbox_id: s.from_mailbox_id,
             ciphertext_b64: s.ciphertext_b64,
             sequence: s.sequence,
             timestamp_epoch_ms: s.timestamp_epoch_ms,
         }).collect();

         let last_sequence = messages.last().map(|m| m.sequence).unwrap_or(0);

         Ok(MailboxRecvResponse {
             messages,
             last_sequence,
         })
    }

    pub async fn verify_mailbox(&self, mailbox_id: &str) -> Result<(), RendezvousError> {
        if (self.repo.get_mailbox_meta(mailbox_id).await.map_err(RendezvousError::Redis)?).is_none() {
            return Err(RendezvousError::MailboxNotFound);
        }
        Ok(())
    }
}
