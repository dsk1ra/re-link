use crate::api::models::SignalingClientConfigDto;
use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::time::Duration;

// Empty by default; app UI must provide a domain before making connections.
const DEFAULT_PUBLIC_URL: &str = "";
const DEFAULT_HEARTBEAT_INTERVAL_SECS: u64 = 30;

static CLIENT_CONFIG: Lazy<Mutex<SignalingClientConfigDto>> = Lazy::new(|| {
    let config = SignalingClientConfigDto::new(
        DEFAULT_PUBLIC_URL,
        Duration::from_secs(DEFAULT_HEARTBEAT_INTERVAL_SECS),
    );
    Mutex::new(config)
});

#[flutter_rust_bridge::frb(sync)]
pub fn load_signaling_client_config() -> SignalingClientConfigDto {
    CLIENT_CONFIG
        .lock()
        .expect("client config mutex poisoned")
        .clone()
}

#[flutter_rust_bridge::frb(sync)]
pub fn override_signaling_base_url(url: String) -> SignalingClientConfigDto {
    let mut guard = CLIENT_CONFIG.lock().expect("client config mutex poisoned");
    guard.base_url = url;
    guard.clone()
}

#[flutter_rust_bridge::frb(sync)]
pub fn reset_signaling_client_config() -> SignalingClientConfigDto {
    let mut guard = CLIENT_CONFIG.lock().expect("client config mutex poisoned");
    *guard = SignalingClientConfigDto::new(
        DEFAULT_PUBLIC_URL,
        Duration::from_secs(DEFAULT_HEARTBEAT_INTERVAL_SECS),
    );
    guard.clone()
}
