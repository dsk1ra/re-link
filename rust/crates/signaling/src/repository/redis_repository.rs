use anyhow::Result;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct MailboxState {
    pub mailbox_id: String,
    pub peer_mailbox_id: Option<String>,
    pub created_at_epoch_ms: u128,
    pub expires_at_epoch_ms: u128,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct MailboxMessageStored {
    pub from_mailbox_id: String,
    pub ciphertext_b64: String,
    pub sequence: u64,
    pub timestamp_epoch_ms: u128,
}

#[derive(Clone)]
pub struct RedisRepository {
    conn_manager: redis::aio::ConnectionManager,
    key_prefix: String,
}

impl RedisRepository {
    pub fn new(conn_manager: redis::aio::ConnectionManager, key_prefix: String) -> Self {
        Self {
            conn_manager,
            key_prefix,
        }
    }

    fn meta_key(&self, mailbox_id: &str) -> String {
        format!("{}:mailbox_meta:{}", self.key_prefix, mailbox_id)
    }

    fn list_key(&self, mailbox_id: &str) -> String {
        format!("{}:mailbox_msgs:{}", self.key_prefix, mailbox_id)
    }

    fn rendezvous_key(&self, token: &str) -> String {
        format!("{}:rendezvous:{}", self.key_prefix, token)
    }

    pub async fn save_mailbox_meta(&self, state: &MailboxState, ttl_secs: u64) -> Result<()> {
        let mut conn = self.conn_manager.clone();
        let key = self.meta_key(&state.mailbox_id);
        let json = serde_json::to_string(state)?;
        conn.set_ex::<_, _, ()>(key, json, ttl_secs).await?;
        Ok(())
    }

    pub async fn get_mailbox_meta(&self, mailbox_id: &str) -> Result<Option<MailboxState>> {
        let mut conn = self.conn_manager.clone();
        let key = self.meta_key(mailbox_id);
        let json: Option<String> = conn.get(key).await?;
        match json {
            Some(s) => Ok(Some(serde_json::from_str(&s)?)),
            None => Ok(None),
        }
    }

    pub async fn clear_mailbox_messages(&self, mailbox_id: &str) -> Result<()> {
        let mut conn = self.conn_manager.clone();
        let key = self.list_key(mailbox_id);
        conn.del::<_, ()>(key).await?;
        Ok(())
    }

    pub async fn save_rendezvous(&self, token: &str, mailbox_id: &str, ttl_secs: u64) -> Result<()> {
        let mut conn = self.conn_manager.clone();
        let key = self.rendezvous_key(token);
        conn.set_ex::<_, _, ()>(key, mailbox_id, ttl_secs).await?;
        Ok(())
    }

    pub async fn get_and_delete_rendezvous(&self, token: &str) -> Result<Option<String>> {
        let mut conn = self.conn_manager.clone();
        let key = self.rendezvous_key(token);
        let val: Option<String> = conn.get(&key).await?;
        if val.is_some() {
            conn.del::<_, ()>(&key).await?;
        }
        Ok(val)
    }

    pub async fn get_message_count(&self, mailbox_id: &str) -> Result<u64> {
        let mut conn = self.conn_manager.clone();
        let key = self.list_key(mailbox_id);
        Ok(conn.llen(key).await?)
    }

    pub async fn push_message(&self, mailbox_id: &str, message: &MailboxMessageStored, ttl_secs: u64) -> Result<()> {
        let mut conn = self.conn_manager.clone();
        let key = self.list_key(mailbox_id);
        let json = serde_json::to_string(message)?;
        conn.rpush::<_, _, ()>(&key, &json).await?;
        conn.expire::<_, ()>(&key, ttl_secs as i64).await?;
        Ok(())
    }

    pub async fn get_messages(&self, mailbox_id: &str) -> Result<Vec<MailboxMessageStored>> {
        let mut conn = self.conn_manager.clone();
        let key = self.list_key(mailbox_id);
        let jsons: Vec<String> = conn.lrange(key, 0, -1).await?;
        let messages = jsons.into_iter()
            .filter_map(|j| serde_json::from_str(&j).ok())
            .collect();
        Ok(messages)
    }
}
