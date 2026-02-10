use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, Notify, Mutex, oneshot};
use tokio::time::{timeout, Duration};
use webrtc::data_channel::RTCDataChannel;
use webrtc::data_channel::data_channel_state::RTCDataChannelState;
use serde::{Serialize, Deserialize};
use sha2::{Digest, Sha256};
use hex::encode as hex_encode;
use tracing::{info, error, debug};
use once_cell::sync::Lazy;
use uuid::Uuid;

const CHUNK_SIZE: usize = 64 * 1024; // 64KB
const HIGH_WATER_MARK: usize = 1024 * 1024; // 1MB
const BUFFERED_LOW_THRESHOLD: usize = 64 * 1024; // 64KB
const MAX_FILE_SIZE: u64 = 512 * 1024 * 1024; // 512MB
const ACCEPT_TIMEOUT: Duration = Duration::from_secs(30);
const INACTIVITY_TIMEOUT: Duration = Duration::from_secs(30);
static TRANSFER_SEMAPHORE: Lazy<tokio::sync::Semaphore> =
    Lazy::new(|| tokio::sync::Semaphore::new(1));

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct FileMetadata {
    pub name: String,
    pub size: u64,
    pub sha256: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum TransferMessage {
    Metadata {
        id: String,
        name: String,
        size: u64,
        sha256: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        mime: Option<String>,
    },
    Accept { id: String },
    Reject { id: String, reason: Option<String> },
    Cancel { id: String, reason: Option<String> },
    Chunk { data: Vec<u8> },
    Eof { id: String },
}

pub struct FileTransferService;

impl FileTransferService {
    pub async fn send_file(
        data_channel: Arc<RTCDataChannel>,
        file_path: PathBuf,
    ) -> anyhow::Result<()> {
        let _permit = TRANSFER_SEMAPHORE.acquire().await?;
        let file_name = file_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();
        
        let file = File::open(&file_path).await?;
        let metadata = file.metadata().await?;
        let file_size = metadata.len();

        if file_size > MAX_FILE_SIZE {
            anyhow::bail!("File exceeds max size ({} bytes)", MAX_FILE_SIZE);
        }

        let transfer_id = Uuid::new_v4().to_string();

        info!("Starting file transfer: {} ({} bytes)", file_name, file_size);

        let mut hasher = Sha256::new();
        let mut file_for_hash = File::open(&file_path).await?;
        let mut buffer = vec![0u8; CHUNK_SIZE];
        while let Ok(n) = file_for_hash.read(&mut buffer).await {
            if n == 0 { break; }
            hasher.update(&buffer[..n]);
        }
        let global_hash = hex_encode(hasher.finalize());

        let metadata = FileMetadata {
            name: file_name,
            size: file_size,
            sha256: global_hash,
        };

        // Send Metadata
        let metadata_json = serde_json::to_string(&TransferMessage::Metadata {
            id: transfer_id.clone(),
            name: metadata.name.clone(),
            size: metadata.size,
            sha256: metadata.sha256.clone(),
            mime: None,
        })?;
        data_channel.send_text(metadata_json).await?;

        let cancelled = Arc::new(AtomicBool::new(false));
        let (accept_tx, accept_rx) = oneshot::channel::<Result<(), String>>();
        let accept_tx = Arc::new(Mutex::new(Some(accept_tx)));

        let accept_tx_clone = Arc::clone(&accept_tx);
        let cancel_flag = Arc::clone(&cancelled);
        let accept_id = transfer_id.clone();
        data_channel.on_message(Box::new(move |msg| {
            let accept_tx = Arc::clone(&accept_tx_clone);
            let cancel_flag = Arc::clone(&cancel_flag);
            let accept_id = accept_id.clone();
            Box::pin(async move {
                if msg.is_string {
                    if let Ok(text) = std::str::from_utf8(&msg.data) {
                        if let Ok(message) = serde_json::from_str::<TransferMessage>(text) {
                            let mut tx_guard = accept_tx.lock().await;
                            if let TransferMessage::Cancel { id, reason } = message {
                                if id == accept_id {
                                    cancel_flag.store(true, Ordering::SeqCst);
                                    if let Some(tx) = tx_guard.take() {
                                        let _ = tx.send(Err(reason.unwrap_or("cancelled".to_string())));
                                    }
                                }
                                return;
                            }

                            if let Some(tx) = tx_guard.take() {
                                match message {
                                    TransferMessage::Accept { id } if id == accept_id => {
                                        let _ = tx.send(Ok(()));
                                    }
                                    TransferMessage::Reject { id, reason } if id == accept_id => {
                                        let _ = tx.send(Err(reason.unwrap_or("rejected".to_string())));
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                }
            })
        }));

        match timeout(ACCEPT_TIMEOUT, accept_rx).await {
            Ok(Ok(Ok(()))) => {}
            Ok(Ok(Err(reason))) => anyhow::bail!("Transfer rejected: {}", reason),
            Ok(Err(_)) => anyhow::bail!("Transfer accept channel closed"),
            Err(_) => anyhow::bail!("Transfer accept timeout"),
        }

        if cancelled.load(Ordering::SeqCst) {
            anyhow::bail!("Transfer cancelled by peer");
        }

        // CSP Channel with capacity 1 (Rendezvous)
        let (tx, mut rx) = mpsc::channel::<Vec<u8>>(1);

        // Notify for backpressure
        let notify = Arc::new(Notify::new());
        let notify_clone = Arc::clone(&notify);
        let cancel_flag_reader = Arc::clone(&cancelled);
        let cancel_flag_writer = Arc::clone(&cancelled);
        
        data_channel.set_buffered_amount_low_threshold(BUFFERED_LOW_THRESHOLD).await;
        data_channel.on_buffered_amount_low(Box::new(move || {
            debug!("Buffered amount low, notifying writer");
            let n = Arc::clone(&notify_clone);
            Box::pin(async move {
                n.notify_one();
            })
        })).await;

        // Reader Task (Producer)
        let reader_handle = tokio::spawn(async move {
            let mut file = File::open(&file_path).await?;

            loop {
                let mut buffer = vec![0u8; CHUNK_SIZE];
                let n = file.read(&mut buffer).await?;

                if n == 0 {
                    break;
                }

                buffer.truncate(n);

                if tx.send(buffer).await.is_err() {
                    error!("Reader failed to send chunk to channel");
                    if cancel_flag_reader.load(Ordering::SeqCst) {
                        anyhow::bail!("Transfer cancelled by peer");
                    }
                    break;
                }
            }
            Ok::<(), anyhow::Error>(())
        });

        // Writer Task (Consumer)
        let dc = Arc::clone(&data_channel);
        let writer_handle = tokio::spawn(async move {
            while let Some(chunk) = rx.recv().await {
                if cancel_flag_writer.load(Ordering::SeqCst) {
                    anyhow::bail!("Transfer cancelled by peer");
                }
                // Backpressure Guard
                loop {
                    let state = dc.ready_state();
                    if state != RTCDataChannelState::Open {
                        anyhow::bail!("DataChannel closed during transfer");
                    }

                    let buffered = dc.buffered_amount().await;
                    if buffered <= HIGH_WATER_MARK {
                        break;
                    }
                    
                    debug!("High buffered amount ({}), waiting...", buffered);
                    notify.notified().await;
                }

                // Send chunk
                dc.send(&chunk.into()).await.map_err(|e| anyhow::anyhow!("DC send failed: {}", e))?;
            }
            
            // Send EOF or equivalent
            let eof_json = serde_json::to_string(&TransferMessage::Eof { id: transfer_id })?;
            dc.send_text(eof_json).await.map_err(|e| anyhow::anyhow!("DC send EOF failed: {}", e))?;
            
            Ok::<(), anyhow::Error>(())
        });

        // Wait for tasks to complete
        reader_handle.await.map_err(|e| anyhow::anyhow!("Reader task panicked: {}", e))?
            .map_err(|e| anyhow::anyhow!("Reader error: {}", e))?;
        writer_handle.await.map_err(|e| anyhow::anyhow!("Writer task panicked: {}", e))??;

        info!("File transfer completed successfully");
        Ok(())
    }

    pub async fn receive_file(
        data_channel: Arc<RTCDataChannel>,
        save_dir: PathBuf,
    ) -> anyhow::Result<()> {
        let _permit = TRANSFER_SEMAPHORE.acquire().await?;
        let (tx, mut rx) = mpsc::channel::<TransferMessage>(100);
        
        data_channel.on_message(Box::new(move |msg| {
            let tx = tx.clone();
            Box::pin(async move {
                if msg.is_string {
                    if let Ok(text) = std::str::from_utf8(&msg.data) {
                        if let Ok(message) = serde_json::from_str::<TransferMessage>(text) {
                            let _ = tx.send(message).await;
                        }
                    }
                } else {
                    // Binary chunk
                    let _ = tx.send(TransferMessage::Chunk { data: msg.data.to_vec() }).await;
                }
            })
        }));

        let mut file: Option<File> = None;
        let mut metadata: Option<FileMetadata> = None;
        let mut temp_path: Option<PathBuf> = None;
        let mut current_id: Option<String> = None;
        let mut final_name: Option<String> = None;
        let mut hasher = Sha256::new();
        let mut received_size = 0u64;

        loop {
            let msg = match timeout(INACTIVITY_TIMEOUT, rx.recv()).await {
                Ok(Some(message)) => message,
                Ok(None) => break,
                Err(_) => anyhow::bail!("Transfer inactivity timeout"),
            };

            match msg {
                TransferMessage::Metadata { id, name, size, sha256, .. } => {
                    info!("Receiving file: {} ({} bytes)", name, size);
                    if size > MAX_FILE_SIZE {
                        let reject = TransferMessage::Reject {
                            id: id.clone(),
                            reason: Some("size_limit".to_string()),
                        };
                        let _ = data_channel.send_text(serde_json::to_string(&reject)?).await;
                        anyhow::bail!("File exceeds max size");
                    }
                    let sanitized_name = sanitize_file_name(&name);
                    let path = save_dir.join(format!("{}.{}.tmp", id, sanitized_name));
                    file = Some(File::create(&path).await?);
                    temp_path = Some(path);
                    current_id = Some(id.clone());
                    final_name = Some(sanitized_name);
                    metadata = Some(FileMetadata { name, size, sha256 });
                    let accept = TransferMessage::Accept { id };
                    data_channel.send_text(serde_json::to_string(&accept)?).await?;
                }
                TransferMessage::Chunk { data } => {
                    if let Some(ref mut f) = file {
                        f.write_all(&data).await?;
                        hasher.update(&data);
                        received_size += data.len() as u64;
                        debug!("Received chunk: {} bytes (total {}/{})", 
                            data.len(), 
                            received_size, 
                            metadata.as_ref().map(|m| m.size).unwrap_or(0)
                        );
                    }
                }
                TransferMessage::Eof { id } => {
                    if current_id.as_ref() == Some(&id) {
                        break;
                    }
                }
                TransferMessage::Reject { id, .. } | TransferMessage::Cancel { id, .. } => {
                    if current_id.as_ref() == Some(&id) {
                        anyhow::bail!("Transfer cancelled by peer");
                    }
                }
                TransferMessage::Accept { .. } => {}
            }

            if let Some(ref m) = metadata {
                if received_size >= m.size {
                    break;
                }
            }
        }

        if let (Some(m), Some(f)) = (metadata, file) {
            if received_size != m.size {
                anyhow::bail!("Size mismatch");
            }
            let final_hash = hex_encode(hasher.finalize());
            if final_hash == m.sha256 {
                info!("Integrity check passed for {}", m.name);
                let name_for_save = final_name.unwrap_or_else(|| sanitize_file_name(&m.name));
                let final_path = unique_file_path(&save_dir, &name_for_save).await?;
                drop(f);
                if let Some(path) = temp_path {
                    tokio::fs::rename(path, &final_path).await?;
                }
                info!("File saved to {:?}", final_path);
            } else {
                if let Some(path) = temp_path {
                    let _ = tokio::fs::remove_file(path).await;
                }
                error!("Integrity check failed! Expected {}, got {}", m.sha256, final_hash);
                anyhow::bail!("Integrity check failed");
            }
        }

        Ok(())
    }
}

fn sanitize_file_name(raw: &str) -> String {
    let base = Path::new(raw)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file");

    let sanitized: String = base
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | ' ') {
                c
            } else {
                '_'
            }
        })
        .collect();

    let trimmed = sanitized.trim();
    if trimmed.is_empty() {
        "file".to_string()
    } else {
        trimmed.to_string()
    }
}

async fn unique_file_path(dir: &Path, file_name: &str) -> anyhow::Result<PathBuf> {
    let separator_index = file_name.rfind('.');
    let (base, extension) = match separator_index {
        Some(idx) if idx > 0 => (&file_name[..idx], &file_name[idx..]),
        _ => (file_name, ""),
    };

    let mut candidate = dir.join(file_name);
    let mut counter = 1;
    while tokio::fs::metadata(&candidate).await.is_ok() {
        let next_name = format!("{} ({}){}", base, counter, extension);
        candidate = dir.join(next_name);
        counter += 1;
    }

    Ok(candidate)
}
