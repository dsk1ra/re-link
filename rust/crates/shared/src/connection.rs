use hmac::{Hmac, Mac};
use rand::RngCore;
use sha2::Sha256;
use base64::Engine as _;
use aes_gcm::{aead::{Aead, KeyInit}, Aes256Gcm, Nonce};

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
    let mut mac = <HmacSha256 as Mac>::new_from_slice(secret)
        .map_err(|e| anyhow::anyhow!("HMAC init failed: {}", e))?;
    mac.update(b"sig");
    k_sig.copy_from_slice(&mac.finalize().into_bytes()[..32]);

    let mut k_mac = [0u8; 32];
    let mut mac = <HmacSha256 as Mac>::new_from_slice(secret)
        .map_err(|e| anyhow::anyhow!("HMAC init failed: {}", e))?;
    mac.update(b"mac");
    k_mac.copy_from_slice(&mac.finalize().into_bytes()[..32]);

    let mut sas = [0u8; 32];
    let mut mac = <HmacSha256 as Mac>::new_from_slice(secret)
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

/// Encrypts a payload using AES-256-GCM.
/// Returns base64-encoded string containing [nonce + ciphertext + tag].
pub fn encrypt_payload(key: &[u8; 32], plaintext: &[u8]) -> anyhow::Result<String> {
    let cipher = Aes256Gcm::new(key.into());
    let mut nonce_bytes = [0u8; 12];
    rand::rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    
    let ciphertext = cipher.encrypt(nonce, plaintext)
        .map_err(|e| anyhow::anyhow!("Encryption failed: {}", e))?;
    
    // Prepend nonce to ciphertext
    let mut payload = nonce_bytes.to_vec();
    payload.extend(ciphertext);
    
    Ok(base64::engine::general_purpose::STANDARD.encode(payload))
}

/// Decrypts a base64-encoded payload [nonce + ciphertext + tag] using AES-256-GCM.
pub fn decrypt_payload(key: &[u8; 32], ciphertext_b64: &str) -> anyhow::Result<Vec<u8>> {
    let payload = base64::engine::general_purpose::STANDARD.decode(ciphertext_b64)
        .map_err(|e| anyhow::anyhow!("Base64 decode failed: {}", e))?;
        
    if payload.len() < 12 {
        anyhow::bail!("Payload too short");
    }
    
    let (nonce_bytes, ciphertext) = payload.split_at(12);
    let cipher = Aes256Gcm::new(key.into());
    let nonce = Nonce::from_slice(nonce_bytes);
    
    cipher.decrypt(nonce, ciphertext)
        .map_err(|e| anyhow::anyhow!("Decryption failed: {}", e))
}
