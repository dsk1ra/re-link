use crate::api::models::SignalingClientConfigDto;
use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::time::Duration;

// Defaults copied from server config for decoupling
const DEFAULT_PUBLIC_URL: &str = "http://127.0.0.1:8080";
const DEFAULT_HEARTBEAT_INTERVAL_SECS: u64 = 30;

static CLIENT_CONFIG: Lazy<Mutex<SignalingClientConfigDto>> = Lazy::new(|| {
    let config = SignalingClientConfigDto::new(DEFAULT_PUBLIC_URL, Duration::from_secs(DEFAULT_HEARTBEAT_INTERVAL_SECS));
    Mutex::new(config)
});

#[flutter_rust_bridge::frb(sync)]
pub fn load_signaling_client_config() -> SignalingClientConfigDto {
    let guard = CLIENT_CONFIG.lock().expect("client config mutex poisoned");
    SignalingClientConfigDto {
        base_url: guard.base_url.clone(),
        heartbeat_interval_secs: guard.heartbeat_interval_secs,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn override_signaling_base_url(url: String) -> SignalingClientConfigDto {
    let mut guard = CLIENT_CONFIG.lock().expect("client config mutex poisoned");
    guard.base_url = url.clone();
    SignalingClientConfigDto {
        base_url: url,
        heartbeat_interval_secs: guard.heartbeat_interval_secs,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn reset_signaling_client_config() -> SignalingClientConfigDto {
    let mut guard = CLIENT_CONFIG.lock().expect("client config mutex poisoned");
    *guard = SignalingClientConfigDto::new(DEFAULT_PUBLIC_URL, Duration::from_secs(DEFAULT_HEARTBEAT_INTERVAL_SECS));
    SignalingClientConfigDto {
        base_url: guard.base_url.clone(),
        heartbeat_interval_secs: guard.heartbeat_interval_secs,
    }
}