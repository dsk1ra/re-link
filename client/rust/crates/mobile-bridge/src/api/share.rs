use crate::api::transfer::CONNECTIONS;
use crate::capture::provider::CaptureProvider;
use once_cell::sync::Lazy;
use std::sync::{Arc, Mutex};

#[cfg(not(windows))]
use crate::capture::stub::StubCaptureAdapter;
#[cfg(windows)]
use crate::capture::windows::WindowsCaptureAdapter;

static PLATFORM_INITIALIZED: Lazy<Mutex<bool>> = Lazy::new(|| Mutex::new(false));
static CAPTURE_PROVIDER: Lazy<Mutex<Option<Arc<dyn CaptureProvider>>>> =
    Lazy::new(|| Mutex::new(None));

#[derive(Debug, Clone)]
pub enum SourceKind {
    Display,
    Window,
}

#[derive(Debug, Clone)]
pub enum BitratePreset {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone)]
pub struct SourceDescriptor {
    pub source_id: String,
    pub kind: SourceKind,
    pub name: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct ShareConfig {
    pub fps: u32,
    pub bitrate_preset: BitratePreset,
}

#[derive(Debug, Clone)]
pub struct ShareStartResult {
    pub track_prepared: bool,
    pub renegotiation_required: bool,
    pub data_channel_available: bool,
}

#[flutter_rust_bridge::frb(sync)]
pub fn init() -> anyhow::Result<()> {
    let mut init_guard = PLATFORM_INITIALIZED
        .lock()
        .map_err(|_| anyhow::anyhow!("platform init state lock poisoned"))?;

    if *init_guard {
        return Ok(());
    }

    #[cfg(windows)]
    {
        WindowsCaptureAdapter::init_platform_services()?;
    }

    let provider: Arc<dyn CaptureProvider> = {
        #[cfg(windows)]
        {
            Arc::new(WindowsCaptureAdapter::new())
        }

        #[cfg(not(windows))]
        {
            Arc::new(StubCaptureAdapter::new())
        }
    };

    let mut provider_guard = CAPTURE_PROVIDER
        .lock()
        .map_err(|_| anyhow::anyhow!("capture provider state lock poisoned"))?;
    *provider_guard = Some(provider);

    *init_guard = true;
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_share_sources() -> anyhow::Result<Vec<SourceDescriptor>> {
    init()?;
    let provider = get_provider()?;
    provider.list_sources()
}

#[flutter_rust_bridge::frb(sync)]
pub fn start_share(
    connection_id: String,
    source_id: String,
    config: ShareConfig,
) -> anyhow::Result<ShareStartResult> {
    init()?;

    let (track_prepared, renegotiation_required, data_channel_available) =
        if let Ok(connections) = CONNECTIONS.try_lock() {
            if let Some(handle) = connections.get(&connection_id) {
                (true, true, handle.data_channels.contains_key("control"))
            } else {
                (false, false, false)
            }
        } else {
            (false, false, false)
        };

    let provider = get_provider()?;
    provider.start_capture(&source_id, &config)?;

    Ok(ShareStartResult {
        track_prepared,
        renegotiation_required,
        data_channel_available,
    })
}

fn get_provider() -> anyhow::Result<Arc<dyn CaptureProvider>> {
    let guard = CAPTURE_PROVIDER
        .lock()
        .map_err(|_| anyhow::anyhow!("capture provider state lock poisoned"))?;

    guard
        .as_ref()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("capture provider not initialised"))
}
