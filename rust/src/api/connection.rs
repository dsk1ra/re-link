use crate::connection;

/// Initialize a connection link (Client A)
/// Returns a mailbox ID and generates a rendezvous token
#[flutter_rust_bridge::frb(sync)]
pub fn connection_init_local() -> ConnectionInitLocalResult {
    // Generate high-entropy rendezvous ID locally (will be shared via link)
    let rendezvous_id = connection::gen_rendezvous_id();
    
    // Generate mailbox ID locally
    let mailbox_id = connection::gen_mailbox_id();
    
    // Generate a dummy secret (in real client, user would generate this)
    // This secret is kept local and NOT sent to server
    let mut secret = [0u8; 32];
    let mut rng = rand::rng();
    use rand::RngCore;
    rng.fill_bytes(&mut secret);
    
    // Derive keys from secret
    let keys = connection::derive_keys(&secret)
        .expect("key derivation failed");
    
    ConnectionInitLocalResult {
        rendezvous_id,
        mailbox_id,
        k_sig: hex::encode(keys.k_sig),
        k_mac: hex::encode(keys.k_mac),
        sas: hex::encode(keys.sas),
    }
}

#[derive(Debug, Clone)]
pub struct ConnectionInitLocalResult {
    pub rendezvous_id: String,
    pub mailbox_id: String,
    pub k_sig: String,      // Hex-encoded signaling key
    pub k_mac: String,      // Hex-encoded MAC key
    pub sas: String,        // Hex-encoded short auth string
}

/// Generate a connection link URL
#[flutter_rust_bridge::frb(sync)]
pub fn generate_connection_link(
    base_url: String,
    rendezvous_id: String,
) -> String {
    format!("{}/connection/join?token={}", base_url, rendezvous_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_init_local() {
        let result = connection_init_local();
        assert!(!result.rendezvous_id.is_empty());
        assert!(!result.mailbox_id.is_empty());
        assert_eq!(result.k_sig.len(), 64); // 32 bytes = 64 hex chars
        assert_eq!(result.k_mac.len(), 64);
        assert_eq!(result.sas.len(), 64);
    }

    #[test]
    fn test_generate_connection_link() {
        let link = generate_connection_link(
            "https://example.com".to_string(),
            "test_rendezvous_id".to_string(),
        );
        assert!(link.contains("https://example.com/connection/join"));
        assert!(link.contains("test_rendezvous_id"));
    }
}
