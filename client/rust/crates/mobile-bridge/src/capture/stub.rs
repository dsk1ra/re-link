use crate::api::share::{ShareConfig, SourceDescriptor};
use crate::capture::provider::CaptureProvider;

#[derive(Default)]
pub struct StubCaptureAdapter {}

impl StubCaptureAdapter {
    pub fn new() -> Self {
        Self {}
    }
}

impl CaptureProvider for StubCaptureAdapter {
    fn list_sources(&self) -> anyhow::Result<Vec<SourceDescriptor>> {
        Ok(Vec::new())
    }

    fn start_capture(&self, _source_id: &str, _config: &ShareConfig) -> anyhow::Result<()> {
        Err(anyhow::anyhow!(
            "Screen capture adapter is only available on Windows for this build"
        ))
    }
}
