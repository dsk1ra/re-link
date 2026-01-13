pub mod client;
pub mod connection;
pub mod simple;

// Re-export shared types for FRB (only those without complex types like Uuid)
pub use crate::shared::{
    ConnectionInitResponse, ConnectionJoinRequest, ConnectionJoinResponse,
    MailboxSendRequest, MailboxRecvResponse, MailboxMessage,
};
