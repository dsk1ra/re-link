use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use client_core::file_transfer::FileTransferService;
use webrtc::data_channel::RTCDataChannel;
use webrtc::peer_connection::RTCPeerConnection;
use tracing::info;

pub struct PeerConnectionHandle {
    pub pc: Arc<RTCPeerConnection>,
    pub data_channels: HashMap<String, Arc<RTCDataChannel>>,
}

static CONNECTIONS: Lazy<Mutex<HashMap<String, PeerConnectionHandle>>> = 
    Lazy::new(|| Mutex::new(HashMap::new()));

#[flutter_rust_bridge::frb(sync)]
pub fn start_file_transfer(connection_id: String, file_path: String) -> anyhow::Result<()> {
    // This is a sync wrapper that spawns the async task
    let runtime = tokio::runtime::Handle::current();
    
    runtime.spawn(async move {
        let connections = CONNECTIONS.lock().await;
        if let Some(handle) = connections.get(&connection_id) {
            if let Some(dc) = handle.data_channels.get("file_transfer") {
                let dc_clone = Arc::clone(dc);
                if let Err(e) = FileTransferService::send_file(dc_clone, PathBuf::from(file_path)).await {
                    info!("File transfer error: {}", e);
                }
            } else {
                info!("No file_transfer data channel found for connection {}", connection_id);
            }
        } else {
            info!("Connection {} not found", connection_id);
        }
    });

    Ok(())
}

pub async fn register_connection(connection_id: String, pc: Arc<RTCPeerConnection>) -> anyhow::Result<()> {
    let mut connections = CONNECTIONS.lock().await;
    connections.insert(connection_id, PeerConnectionHandle {
        pc,
        data_channels: HashMap::new(),
    });
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn start_file_receive(connection_id: String, save_dir: String) -> anyhow::Result<()> {
    let runtime = tokio::runtime::Handle::current();
    
    runtime.spawn(async move {
        let connections = CONNECTIONS.lock().await;
        if let Some(handle) = connections.get(&connection_id) {
            if let Some(dc) = handle.data_channels.get("file_transfer") {
                let dc_clone = Arc::clone(dc);
                if let Err(e) = FileTransferService::receive_file(dc_clone, PathBuf::from(save_dir)).await {
                    info!("File receive error: {}", e);
                }
            }
        }
    });

    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn add_data_channel(connection_id: String, label: String, dc: Arc<RTCDataChannel>) -> anyhow::Result<()> {
    // Note: This might need careful locking if called from different threads
    let runtime = tokio::runtime::Handle::current();
    runtime.spawn(async move {
        let mut connections = CONNECTIONS.lock().await;
        if let Some(handle) = connections.get_mut(&connection_id) {
            handle.data_channels.insert(label, dc);
        }
    });
    Ok(())
}
