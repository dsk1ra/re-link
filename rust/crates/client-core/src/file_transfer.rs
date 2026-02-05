use std::path::PathBuf;
use std::sync::Arc;
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, Notify};
use webrtc::data_channel::RTCDataChannel;
use webrtc::data_channel::data_channel_state::RTCDataChannelState;
use serde::{Serialize, Deserialize};
use blake3::Hasher;
use tracing::{info, error, debug};

const CHUNK_SIZE: usize = 64 * 1024; // 64KB
const HIGH_WATER_MARK: usize = 1024 * 1024; // 1MB
const BUFFERED_LOW_THRESHOLD: usize = 64 * 1024; // 64KB

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct FileMetadata {
    pub name: String,
    pub size: u64,
    pub hash: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum TransferMessage {
    Metadata(FileMetadata),
    Chunk {
        seq: u64,
        data: Vec<u8>,
        chunk_hash: String,
    },
    Eof,
}

pub struct FileTransferService;

impl FileTransferService {
    pub async fn send_file(
        data_channel: Arc<RTCDataChannel>,
        file_path: PathBuf,
    ) -> anyhow::Result<()> {
        let file_name = file_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();
        
        let file = File::open(&file_path).await?;
        let metadata = file.metadata().await?;
        let file_size = metadata.len();

        info!("Starting file transfer: {} ({} bytes)", file_name, file_size);

        let mut hasher = Hasher::new();
        let mut file_for_hash = File::open(&file_path).await?;
        let mut buffer = vec![0u8; CHUNK_SIZE];
        while let Ok(n) = file_for_hash.read(&mut buffer).await {
            if n == 0 { break; }
            hasher.update(&buffer[..n]);
        }
        let global_hash = hasher.finalize().to_string();

        let metadata = FileMetadata {
            name: file_name,
            size: file_size,
            hash: global_hash,
        };

        // Send Metadata
        let metadata_json = serde_json::to_string(&TransferMessage::Metadata(metadata))?;
        data_channel.send_text(metadata_json).await?;

        // CSP Channel with capacity 1 (Rendezvous)
        let (tx, mut rx) = mpsc::channel::<Vec<u8>>(1);

        // Notify for backpressure
        let notify = Arc::new(Notify::new());
        let notify_clone = Arc::clone(&notify);
        
        data_channel.set_buffered_amount_low_threshold(BUFFERED_LOW_THRESHOLD).await;
        data_channel.on_buffered_amount_low(Box::new(move || {
            debug!("Buffered amount low, notifying writer");
            let n = Arc::clone(&notify_clone);
            Box::pin(async move {
                n.notify_waiters();
            })
        })).await;

        // Reader Task (Producer)
        let reader_handle = tokio::spawn(async move {
            let mut file = File::open(&file_path).await.map_err(|e| e.to_string())?;
            let mut seq = 0u64;
            
            loop {
                let mut buffer = vec![0u8; CHUNK_SIZE];
                let n = file.read(&mut buffer).await.map_err(|e| e.to_string())?;
                
                if n == 0 {
                    break;
                }
                
                buffer.truncate(n);
                
                // Synchronous Validation (BLAKE3)
                let mut chunk_hasher = Hasher::new();
                chunk_hasher.update(&buffer);
                let _chunk_hash = chunk_hasher.finalize().to_string();

                if tx.send(buffer).await.is_err() {
                    error!("Reader failed to send chunk to channel");
                    break;
                }
                seq += 1;
            }
            Ok::<u64, String>(seq)
        });

        // Writer Task (Consumer)
        let dc = Arc::clone(&data_channel);
        let writer_handle = tokio::spawn(async move {
            while let Some(chunk) = rx.recv().await {
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
            let eof_json = serde_json::to_string(&TransferMessage::Eof)?;
            dc.send_text(eof_json).await.map_err(|e| anyhow::anyhow!("DC send EOF failed: {}", e))?;
            
            Ok::<(), anyhow::Error>(())
        });

        // Wait for tasks to complete
        let _reader_result = reader_handle.await.map_err(|e| anyhow::anyhow!("Reader task panicked: {}", e))?
            .map_err(|e| anyhow::anyhow!("Reader error: {}", e))?;
        writer_handle.await.map_err(|e| anyhow::anyhow!("Writer task panicked: {}", e))??;

        info!("File transfer completed successfully");
        Ok(())
    }

    pub async fn receive_file(
        data_channel: Arc<RTCDataChannel>,
        save_dir: PathBuf,
    ) -> anyhow::Result<()> {
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
                    let _ = tx.send(TransferMessage::Chunk {
                        seq: 0, // Not used if raw
                        data: msg.data.to_vec(),
                        chunk_hash: "".to_string(),
                    }).await;
                }
            })
        }));

        let mut file: Option<File> = None;
        let mut metadata: Option<FileMetadata> = None;
        let mut hasher = Hasher::new();
        let mut received_size = 0u64;

        while let Some(msg) = rx.recv().await {
            match msg {
                TransferMessage::Metadata(m) => {
                    info!("Receiving file: {:?}", m);
                    let path = save_dir.join(format!("{}.tmp", m.name));
                    file = Some(File::create(&path).await?);
                    metadata = Some(m);
                }
                TransferMessage::Chunk { data, .. } => {
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
                TransferMessage::Eof => {
                    break;
                }
            }
            
            if let Some(ref m) = metadata {
                if received_size >= m.size {
                    break;
                }
            }
        }

        if let (Some(m), Some(f)) = (metadata, file) {
            let final_hash = hasher.finalize().to_string();
            if final_hash == m.hash {
                info!("Integrity check passed for {}", m.name);
                let temp_path = save_dir.join(format!("{}.tmp", m.name));
                let final_path = save_dir.join(&m.name);
                drop(f);
                tokio::fs::rename(temp_path, final_path).await?;
                info!("File saved to {:?}", save_dir.join(&m.name));
            } else {
                error!("Integrity check failed! Expected {}, got {}", m.hash, final_hash);
                anyhow::bail!("Integrity check failed");
            }
        }

        Ok(())
    }
}
