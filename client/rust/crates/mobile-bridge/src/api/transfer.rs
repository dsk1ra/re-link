use crate::api::file_transfer;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
pub use webrtc::data_channel::RTCDataChannel;
pub use webrtc::peer_connection::RTCPeerConnection;

pub struct PeerConnectionHandle {
    pub pc: Arc<RTCPeerConnection>,
    pub data_channels: HashMap<String, Arc<RTCDataChannel>>,
}

pub(crate) static CONNECTIONS: Lazy<Mutex<HashMap<String, PeerConnectionHandle>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub async fn upsert_connection(
    connection_id: String,
    pc: Arc<RTCPeerConnection>,
) -> anyhow::Result<()> {
    let mut connections = CONNECTIONS.lock().await;
    connections
        .entry(connection_id)
        .and_modify(|handle| {
            handle.pc = Arc::clone(&pc);
        })
        .or_insert(PeerConnectionHandle {
            pc,
            data_channels: HashMap::new(),
        });
    Ok(())
}

pub async fn set_data_channel(
    connection_id: String,
    label: String,
    dc: Arc<RTCDataChannel>,
) -> anyhow::Result<()> {
    let mut connections = CONNECTIONS.lock().await;
    if let Some(handle) = connections.get_mut(&connection_id) {
        handle.data_channels.insert(label, dc);
    }
    Ok(())
}

pub async fn remove_connection(connection_id: &str) {
    let mut connections = CONNECTIONS.lock().await;
    connections.remove(connection_id);
}

#[flutter_rust_bridge::frb(sync)]
pub fn start_file_transfer(connection_id: String, file_path: String) -> anyhow::Result<()> {
    let runtime = tokio::runtime::Handle::current();

    runtime.spawn(async move {
        if let Err(error) = file_transfer::send_offer(connection_id.clone(), file_path).await {
            tracing::warn!(connection_id = %connection_id, error = %error, "file transfer send failed");
        }
    });

    Ok(())
}

pub async fn register_connection(
    connection_id: String,
    pc: Arc<RTCPeerConnection>,
) -> anyhow::Result<()> {
    upsert_connection(connection_id, pc).await
}

#[flutter_rust_bridge::frb(sync)]
pub fn start_file_receive(connection_id: String, save_dir: String) -> anyhow::Result<()> {
    let _ = save_dir;
    file_transfer::init_transfer(connection_id);

    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn add_data_channel(
    connection_id: String,
    label: String,
    dc: Arc<RTCDataChannel>,
) -> anyhow::Result<()> {
    // Note: This might need careful locking if called from different threads
    let runtime = tokio::runtime::Handle::current();
    runtime.spawn(async move {
        let _ = set_data_channel(connection_id, label, dc).await;
    });
    Ok(())
}
