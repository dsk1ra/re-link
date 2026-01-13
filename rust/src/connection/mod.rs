use hmac::{Hmac, Mac};
use rand::RngCore;
use sha2::Sha256;
use base64::Engine as _;

type HmacSha256 = Hmac<Sha256>;

/// Derived keys from a shared secret for end-to-end encrypted signaling
#[derive(Debug, Clone)]
pub struct DerivedKeys {
    pub k_sig: [u8; 32],  // Signaling encryption key
    pub k_mac: [u8; 32],  // Message authentication key
    pub sas: [u8; 32],    // Short authentication string for out-of-band verification
}

/// Derive keys from a shared secret using HMAC-based KDF
pub fn derive_keys(secret: &[u8; 32]) -> anyhow::Result<DerivedKeys> {
    // Simple HMAC-KDF: derive multiple keys by HMACing with different info strings
    let mut k_sig = [0u8; 32];
    let mut mac = HmacSha256::new_from_slice(secret)
        .map_err(|e| anyhow::anyhow!("HMAC init failed: {}", e))?;
    mac.update(b"sig");
    k_sig.copy_from_slice(&mac.finalize().into_bytes()[..32]);

    let mut k_mac = [0u8; 32];
    let mut mac = HmacSha256::new_from_slice(secret)
        .map_err(|e| anyhow::anyhow!("HMAC init failed: {}", e))?;
    mac.update(b"mac");
    k_mac.copy_from_slice(&mac.finalize().into_bytes()[..32]);

    let mut sas = [0u8; 32];
    let mut mac = HmacSha256::new_from_slice(secret)
        .map_err(|e| anyhow::anyhow!("HMAC init failed: {}", e))?;
    mac.update(b"sas");
    sas.copy_from_slice(&mac.finalize().into_bytes()[..32]);

    Ok(DerivedKeys { k_sig, k_mac, sas })
}

/// Generate a high-entropy non-guessable rendezvous ID
/// Uses 32 bytes of random data, encoded in URL-safe base64
pub fn gen_rendezvous_id() -> String {
    let mut bytes = [0u8; 32];
    let mut rng = rand::rng();
    rng.fill_bytes(&mut bytes);
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// Generate an opaque mailbox ID for blind storage
pub fn gen_mailbox_id() -> String {
    let mut bytes = [0u8; 16];
    let mut rng = rand::rng();
    rng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_derive_keys() {
        let secret = [42u8; 32];
        let keys = derive_keys(&secret).expect("derivation failed");
        
        // Keys should be deterministic
        let keys2 = derive_keys(&secret).expect("derivation failed");
        assert_eq!(keys.k_sig, keys2.k_sig);
        assert_eq!(keys.k_mac, keys2.k_mac);
        assert_eq!(keys.sas, keys2.sas);
    }

    #[test]
    fn test_gen_rendezvous_id() {
        let id1 = gen_rendezvous_id();
        let id2 = gen_rendezvous_id();
        
        // Should be different (with overwhelming probability)
        assert_ne!(id1, id2);
        // Should decode without error
        assert!(base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(&id1).is_ok());
        assert!(base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(&id2).is_ok());
    }

    #[test]
    fn test_gen_mailbox_id() {
        let id1 = gen_mailbox_id();
        let id2 = gen_mailbox_id();
        
        assert_ne!(id1, id2);
        assert_eq!(id1.len(), 32);  // 16 bytes = 32 hex chars
    }
}