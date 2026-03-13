use crate::api::share::{ShareConfig, SourceDescriptor};

pub trait CaptureProvider: Send + Sync {
    fn list_sources(&self) -> anyhow::Result<Vec<SourceDescriptor>>;

    fn start_capture(&self, source_id: &str, config: &ShareConfig) -> anyhow::Result<()>;
}
