use crate::shared::SignalingClientConfigDto;
use std::{
    env,
    net::{IpAddr, Ipv4Addr, SocketAddr},
    time::Duration,
};
use base64::Engine as _;

const DEFAULT_LISTEN_PORT: u16 = 8080;
const DEFAULT_PUBLIC_URL: &str = "http://127.0.0.1:8080";
const DEFAULT_SESSION_TTL_SECS: u64 = 300;
const DEFAULT_HEARTBEAT_INTERVAL_SECS: u64 = 30;
const DEFAULT_REDIS_URL: &str = "redis://127.0.0.1/";
const DEFAULT_ROOM_TTL_SECS: u64 = 30;
const DEFAULT_REDIS_REQUIRE_TLS: bool = true;
const DEFAULT_REDIS_KEY_PREFIX: &str = "sig";
const DEFAULT_JOINED_FLAG_TTL_SECS: u64 = 60;
const DEFAULT_REDIS_ENCRYPT: bool = false;

#[derive(Debug, Clone)]
pub struct SignalingServerConfig {
    pub listen_addr: SocketAddr,
    pub public_base_url: String,
    pub session_ttl: Duration,
    pub heartbeat_interval: Duration,
    pub redis_url: String,
    pub room_ttl: Duration,
    pub redis_require_tls: bool,
    pub redis_key_prefix: String,
    pub joined_flag_ttl: Duration,
    pub redis_encrypt_payloads: bool,
    pub redis_encryption_key: Option<[u8; 32]>,
}

impl SignalingServerConfig {
    pub fn from_env() -> anyhow::Result<Self> {
        let listen_port = env::var("SIGNALING_PORT")
            .ok()
            .and_then(|raw| raw.parse::<u16>().ok())
            .unwrap_or(DEFAULT_LISTEN_PORT);

        let listen_addr = env::var("SIGNALING_ADDR")
            .ok()
            .and_then(|raw| raw.parse::<IpAddr>().ok())
            .map(|ip| SocketAddr::new(ip, listen_port))
            .unwrap_or(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), listen_port));

        let public_base_url = env::var("SIGNALING_PUBLIC_URL").unwrap_or_else(|_| DEFAULT_PUBLIC_URL.to_string());

        let session_ttl = env::var("SIGNALING_SESSION_TTL_SECS")
            .ok()
            .and_then(|raw| raw.parse::<u64>().ok())
            .map(Duration::from_secs)
            .unwrap_or_else(|| Duration::from_secs(DEFAULT_SESSION_TTL_SECS));

        let heartbeat_interval = env::var("SIGNALING_HEARTBEAT_SECS")
            .ok()
            .and_then(|raw| raw.parse::<u64>().ok())
            .map(Duration::from_secs)
            .unwrap_or_else(|| Duration::from_secs(DEFAULT_HEARTBEAT_INTERVAL_SECS));

        let redis_url = env::var("SIGNALING_REDIS_URL").unwrap_or_else(|_| DEFAULT_REDIS_URL.to_string());
        let room_ttl = env::var("SIGNALING_ROOM_TTL_SECS")
            .ok()
            .and_then(|raw| raw.parse::<u64>().ok())
            .map(Duration::from_secs)
            .unwrap_or_else(|| Duration::from_secs(DEFAULT_ROOM_TTL_SECS));

        // SECURITY: Require TLS for Redis by default. Can be disabled for local dev only.
        let redis_require_tls = env::var("SIGNALING_REDIS_REQUIRE_TLS")
            .ok()
            .and_then(|raw| match raw.to_lowercase().as_str() {
                "1" | "true" | "yes" => Some(true),
                "0" | "false" | "no" => Some(false),
                _ => None,
            })
            .unwrap_or(DEFAULT_REDIS_REQUIRE_TLS);

        // Namespace all keys so Redis ACLs can be scoped safely
        let redis_key_prefix = env::var("SIGNALING_REDIS_KEY_PREFIX")
            .unwrap_or_else(|_| DEFAULT_REDIS_KEY_PREFIX.to_string());

        // TTL for the short-lived "joined" flag
        let joined_flag_ttl = env::var("SIGNALING_JOINED_FLAG_TTL_SECS")
            .ok()
            .and_then(|raw| raw.parse::<u64>().ok())
            .map(Duration::from_secs)
            .unwrap_or_else(|| Duration::from_secs(DEFAULT_JOINED_FLAG_TTL_SECS));

        // Application-level encryption (optional)
        let redis_encrypt_payloads = env::var("SIGNALING_REDIS_ENCRYPT")
            .ok()
            .and_then(|raw| match raw.to_lowercase().as_str() {
                "1" | "true" | "yes" => Some(true),
                "0" | "false" | "no" => Some(false),
                _ => None,
            })
            .unwrap_or(DEFAULT_REDIS_ENCRYPT);

        let redis_encryption_key = env::var("SIGNALING_REDIS_ENC_KEY_B64")
            .ok()
            .and_then(|b64| base64::engine::general_purpose::STANDARD.decode(b64).ok())
            .and_then(|bytes| bytes.try_into().ok());

        Ok(Self {
            listen_addr,
            public_base_url,
            session_ttl,
            heartbeat_interval,
            redis_url,
            room_ttl,
            redis_require_tls,
            redis_key_prefix,
            joined_flag_ttl,
            redis_encrypt_payloads,
            redis_encryption_key,
        })
    }

    pub fn client_config(&self) -> SignalingClientConfigDto {
        SignalingClientConfigDto::new(&self.public_base_url, self.heartbeat_interval)
    }
}

impl Default for SignalingServerConfig {
    fn default() -> Self {
        Self::from_env().unwrap_or_else(|_| Self {
            listen_addr: SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), DEFAULT_LISTEN_PORT),
            public_base_url: DEFAULT_PUBLIC_URL.to_string(),
            session_ttl: Duration::from_secs(DEFAULT_SESSION_TTL_SECS),
            heartbeat_interval: Duration::from_secs(DEFAULT_HEARTBEAT_INTERVAL_SECS),
            redis_url: DEFAULT_REDIS_URL.to_string(),
            room_ttl: Duration::from_secs(DEFAULT_ROOM_TTL_SECS),
            redis_require_tls: DEFAULT_REDIS_REQUIRE_TLS,
            redis_key_prefix: DEFAULT_REDIS_KEY_PREFIX.to_string(),
            joined_flag_ttl: Duration::from_secs(DEFAULT_JOINED_FLAG_TTL_SECS),
            redis_encrypt_payloads: DEFAULT_REDIS_ENCRYPT,
            redis_encryption_key: None,
        })
    }
}
