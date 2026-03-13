use signaling_server::{run_server, SignalingServerConfig};
use tracing::info;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load environment variables from a .env file if present (local dev)
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_target(false)
        .compact()
        .init();

    let config = SignalingServerConfig::from_env()?;
    info!(configuration = ?config, "Loaded signaling server configuration");
    run_server(config).await
}
