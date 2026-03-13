use crate::api::share::{ShareConfig, SourceDescriptor, SourceKind};
use crate::capture::provider::CaptureProvider;
use std::sync::Mutex;
use windows::core::Result as WinResult;
use windows::Win32::Foundation::RPC_E_CHANGED_MODE;
use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
use windows::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSCREEN, SM_CYSCREEN};

#[derive(Default)]
pub struct WindowsCaptureAdapter {
    active_source: Mutex<Option<String>>,
}

impl WindowsCaptureAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn init_platform_services() -> anyhow::Result<()> {
        initialize_apartment().map_err(|e| anyhow::anyhow!("WinRT apartment init failed: {e}"))?;
        Ok(())
    }
}

impl CaptureProvider for WindowsCaptureAdapter {
    fn list_sources(&self) -> anyhow::Result<Vec<SourceDescriptor>> {
        let (width, height) = primary_display_size();
        Ok(vec![SourceDescriptor {
            source_id: "display:primary".to_string(),
            kind: SourceKind::Display,
            name: "Primary Display".to_string(),
            width: Some(width),
            height: Some(height),
        }])
    }

    fn start_capture(&self, source_id: &str, _config: &ShareConfig) -> anyhow::Result<()> {
        let mut guard = self
            .active_source
            .lock()
            .map_err(|_| anyhow::anyhow!("capture adapter state lock poisoned"))?;
        *guard = Some(source_id.to_string());
        Ok(())
    }
}

fn initialize_apartment() -> WinResult<()> {
    let hr = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    if hr.is_ok() || hr == RPC_E_CHANGED_MODE {
        Ok(())
    } else {
        Err(hr.into())
    }
}

fn primary_display_size() -> (u32, u32) {
    let width = unsafe { GetSystemMetrics(SM_CXSCREEN) };
    let height = unsafe { GetSystemMetrics(SM_CYSCREEN) };
    (width.max(0) as u32, height.max(0) as u32)
}
