use crate::{
    shared::SignalingClientConfigDto,
    signaling::SignalingServerConfig,
};
use once_cell::sync::Lazy;
use std::sync::Mutex;

static CLIENT_CONFIG: Lazy<Mutex<SignalingClientConfigDto>> = Lazy::new(|| {
    let config = SignalingServerConfig::default().client_config();
    Mutex::new(config)
});

#[flutter_rust_bridge::frb(sync)]
pub fn load_signaling_client_config() -> SignalingClientConfigDto {
    CLIENT_CONFIG.lock().expect("client config mutex poisoned").clone()
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
    *guard = SignalingServerConfig::default().client_config();
    guard.clone()
}
