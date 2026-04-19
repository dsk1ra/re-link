use crate::api::transfer::CONNECTIONS;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::Mutex;

const CONTROL_CHANNEL_LABEL: &str = "control";
const MIN_FPS: u32 = 1;
const MAX_FPS: u32 = 120;
const MIN_BITRATE_KBPS: u32 = 100;

static PLATFORM_INITIALIZED: AtomicBool = AtomicBool::new(false);
static ACTIVE_SHARES: Lazy<Mutex<HashMap<String, ActiveShare>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

#[derive(Debug, Clone)]
pub enum SourceKind {
    Display,
    Window,
}

#[derive(Debug, Clone)]
pub struct SourceDescriptor {
    pub source_id: String,
    pub kind: SourceKind,
    pub name: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShareConfig {
    pub fps: u32,
    pub target_bitrate_kbps: u32,
}

#[derive(Debug, Clone)]
struct ActiveShare {
    source_id: String,
    config: ShareConfig,
}

fn validate_non_empty(value: &str, field_name: &str) -> anyhow::Result<()> {
    if value.trim().is_empty() {
        anyhow::bail!("{field_name} must not be empty");
    }

    Ok(())
}

fn validate_config(config: &ShareConfig) -> anyhow::Result<()> {
    if !(MIN_FPS..=MAX_FPS).contains(&config.fps) {
        anyhow::bail!(
            "fps must be between {MIN_FPS} and {MAX_FPS}, got {}",
            config.fps
        );
    }

    if config.target_bitrate_kbps < MIN_BITRATE_KBPS {
        anyhow::bail!(
            "target_bitrate_kbps must be at least {MIN_BITRATE_KBPS}, got {}",
            config.target_bitrate_kbps
        );
    }

    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_screen_capture() -> anyhow::Result<()> {
    if PLATFORM_INITIALIZED
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
        tracing::info!("screen capture bridge initialized");
    }

    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_share_sources() -> anyhow::Result<Vec<SourceDescriptor>> {
    init_screen_capture()?;
    tracing::debug!("share source enumeration delegated to Flutter WebRTC desktop capturer");

    Ok(Vec::new())
}

#[flutter_rust_bridge::frb]
pub async fn start_share(
    connection_id: String,
    source_id: String,
    config: ShareConfig,
) -> anyhow::Result<()> {
    init_screen_capture()?;
    validate_non_empty(&connection_id, "connection_id")?;
    validate_non_empty(&source_id, "source_id")?;
    validate_config(&config)?;

    let has_control_channel = {
        let connections = CONNECTIONS.lock().await;
        let Some(handle) = connections.get(&connection_id) else {
            anyhow::bail!("unknown connection_id: {connection_id}");
        };

        handle.data_channels.contains_key(CONTROL_CHANNEL_LABEL)
    };

    if !has_control_channel {
        anyhow::bail!(
            "connection {connection_id} is missing required \"{CONTROL_CHANNEL_LABEL}\" data channel"
        );
    }

    let mut active_shares = ACTIVE_SHARES.lock().await;
    if let Some(existing) = active_shares.get(&connection_id) {
        if existing.source_id == source_id && existing.config == config {
            tracing::debug!(
                connection_id = %connection_id,
                source_id = %source_id,
                "share already active with matching source/config; treating start as idempotent"
            );
            return Ok(());
        }

        anyhow::bail!(
            "share already active for connection {connection_id}; stop existing share before starting a new one"
        );
    }

    active_shares.insert(
        connection_id.clone(),
        ActiveShare {
            source_id: source_id.clone(),
            config,
        },
    );

    tracing::info!(
        connection_id = %connection_id,
        source_id = %source_id,
        "share session registered on Rust bridge"
    );

    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn stop_share(connection_id: String) -> anyhow::Result<()> {
    init_screen_capture()?;
    validate_non_empty(&connection_id, "connection_id")?;

    let mut active_shares = ACTIVE_SHARES.lock().await;
    if active_shares.remove(&connection_id).is_none() {
        tracing::debug!(
            connection_id = %connection_id,
            "stop_share called without an active share; treating as no-op"
        );
        return Ok(());
    }

    tracing::info!(
        connection_id = %connection_id,
        "share session removed from Rust bridge"
    );

    Ok(())
}
