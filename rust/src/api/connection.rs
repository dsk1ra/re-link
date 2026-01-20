use crate::connection;

/// Initialize a connection link (Client A)
/// Returns a mailbox ID and generates a rendezvous token
#[flutter_rust_bridge::frb(sync)]
pub fn connection_init_local() -> ConnectionInitLocalResult {
    // Generate high-entropy rendezvous ID locally (will be shared via link)
    let rendezvous_id = connection::gen_rendezvous_id();
    
    // Generate mailbox ID locally
    let mailbox_id = connection::gen_mailbox_id();
    
    // Generate a secret (in real client, user would generate this)
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
        secret: hex::encode(secret),
        k_sig: hex::encode(keys.k_sig),
        k_mac: hex::encode(keys.k_mac),
        sas: hex::encode(keys.sas),
    }
}

/// Derive keys from a shared secret (Client B)
#[flutter_rust_bridge::frb(sync)]
pub fn connection_derive_keys(secret_hex: String) -> anyhow::Result<ConnectionInitLocalResult> {
    let secret_bytes = hex::decode(secret_hex).map_err(|e| anyhow::anyhow!("Invalid secret hex: {}", e))?;
    let secret: [u8; 32] = secret_bytes.try_into().map_err(|_| anyhow::anyhow!("Invalid secret length"))?;

    let keys = connection::derive_keys(&secret)?;

    Ok(ConnectionInitLocalResult {
        rendezvous_id: "".to_string(), // Not needed for derivation
        mailbox_id: "".to_string(),    // Not needed for derivation
        secret: hex::encode(secret),
        k_sig: hex::encode(keys.k_sig),
        k_mac: hex::encode(keys.k_mac),
        sas: hex::encode(keys.sas),
    })
}

#[derive(Debug, Clone)]
pub struct ConnectionInitLocalResult {
    pub rendezvous_id: String,
    pub mailbox_id: String,
    pub secret: String,     // Hex-encoded shared secret
    pub k_sig: String,      // Hex-encoded signaling key
    pub k_mac: String,      // Hex-encoded MAC key
    pub sas: String,        // Hex-encoded short auth string
}

/// Generate a connection link URL
#[flutter_rust_bridge::frb(sync)]
pub fn generate_connection_link(
    base_url: String,
    rendezvous_id: String,
    secret: String,
) -> String {
    format!("{}/connection/join?token={}#{}", base_url, rendezvous_id, secret)
}

/// Encrypt signaling payload using the shared session key (AES-GCM)
#[flutter_rust_bridge::frb(sync)]
pub fn connection_encrypt(key_hex: String, plaintext: Vec<u8>) -> anyhow::Result<String> {
    let key_bytes = hex::decode(key_hex).map_err(|e| anyhow::anyhow!("Invalid key hex: {}", e))?;
    let key: [u8; 32] = key_bytes.try_into().map_err(|_| anyhow::anyhow!("Invalid key length"))?;
    connection::encrypt_payload(&key, &plaintext)
}

/// Decrypt signaling payload using the shared session key (AES-GCM)
#[flutter_rust_bridge::frb(sync)]
pub fn connection_decrypt(key_hex: String, ciphertext_b64: String) -> anyhow::Result<Vec<u8>> {
    let key_bytes = hex::decode(key_hex).map_err(|e| anyhow::anyhow!("Invalid key hex: {}", e))?;
    let key: [u8; 32] = key_bytes.try_into().map_err(|_| anyhow::anyhow!("Invalid key length"))?;
    connection::decrypt_payload(&key, &ciphertext_b64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_init_local() {
        let result = connection_init_local();
        assert!(!result.rendezvous_id.is_empty());
        assert!(!result.mailbox_id.is_empty());
        assert_eq!(result.secret.len(), 64);
        assert_eq!(result.k_sig.len(), 64); // 32 bytes = 64 hex chars
        assert_eq!(result.k_mac.len(), 64);
        assert_eq!(result.sas.len(), 64);
    }

    #[test]
    fn test_generate_connection_link() {
        let link = generate_connection_link(
            "https://example.com".to_string(),
            "test_rendezvous_id".to_string(),
            "test_secret".to_string(),
        );
        assert!(link.contains("https://example.com/connection/join"));
        assert!(link.contains("token=test_rendezvous_id"));
        assert!(link.contains("#test_secret"));
    }
}
