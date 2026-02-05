use std::time::Duration;

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
