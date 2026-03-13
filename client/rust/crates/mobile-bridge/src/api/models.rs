use std::time::Duration;

// FRB requires this type to be locally owned (orphan rule).
// Keep in sync with shared::models::SignalingClientConfigDto via the From impls below.
#[derive(Debug, Clone)]
pub struct SignalingClientConfigDto {
    pub base_url: String,
    pub heartbeat_interval_secs: u64,
}

impl SignalingClientConfigDto {
    pub fn new(base_url: impl Into<String>, heartbeat_interval: Duration) -> Self {
        Self {
            base_url: base_url.into(),
            heartbeat_interval_secs: heartbeat_interval.as_secs(),
        }
    }
}

impl From<shared::models::SignalingClientConfigDto> for SignalingClientConfigDto {
    fn from(s: shared::models::SignalingClientConfigDto) -> Self {
        Self {
            base_url: s.base_url,
            heartbeat_interval_secs: s.heartbeat_interval_secs,
        }
    }
}

impl From<SignalingClientConfigDto> for shared::models::SignalingClientConfigDto {
    fn from(s: SignalingClientConfigDto) -> Self {
        Self::new(s.base_url, Duration::from_secs(s.heartbeat_interval_secs))
    }
}
