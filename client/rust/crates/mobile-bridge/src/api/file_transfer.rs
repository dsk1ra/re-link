use crate::api::webrtc;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::fs::{File, OpenOptions};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;
use tokio::time::{sleep, Duration, Instant};

const MSG_METADATA: &str = "metadata";
const MSG_ACCEPT: &str = "accept";
const MSG_REJECT: &str = "reject";
const MSG_CANCEL: &str = "cancel";
const MSG_EOF: &str = "eof";

const MAX_FILE_SIZE_BYTES: u64 = 512 * 1024 * 1024;
const ACCEPT_TIMEOUT: Duration = Duration::from_secs(30);
const INACTIVITY_TIMEOUT: Duration = Duration::from_secs(30);
// Attached RTCDataChannel reads are not robust for large binary messages in this stack.
// Keep chunks comfortably below the observed read-loop ceiling to avoid stream resets.
const CHUNK_SIZE: usize = 16 * 1024;
const HIGH_WATER_MARK: u64 = 1024 * 1024;
const LOW_WATER_MARK: u64 = 64 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TransferStatusDto {
    Idle,
    Offering,
    Offered,
    Transferring,
    Receiving,
    Completed,
    Error,
}

#[derive(Debug, Clone)]
pub struct FileTransferStateDto {
    pub status: TransferStatusDto,
    pub file_name: Option<String>,
    pub total_bytes: u64,
    pub bytes_transferred: u64,
    pub error: Option<String>,
}

#[derive(Debug)]
struct FileTransferSession {
    id: String,
    file_name: String,
    file_size: u64,
    is_sender: bool,
    expected_sha256: Option<String>,
    sender_nonce: Option<String>,
    source_file_path: Option<PathBuf>,
    destination_dir: Option<PathBuf>,
    temp_path: Option<PathBuf>,
    writer: Option<File>,
    bytes_received: u64,
    hasher: Option<Sha256>,
    accept_deadline: Option<Instant>,
    inactivity_deadline: Option<Instant>,
}

#[derive(Debug)]
struct FileTransferManager {
    connection_id: String,
    instance_nonce: String,
    current_state: FileTransferStateDto,
    current_session: Option<FileTransferSession>,
    pending_states: Vec<FileTransferStateDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
enum IncomingFileMessage {
    #[serde(rename = "metadata")]
    Metadata {
        id: String,
        name: String,
        size: u64,
        sha256: String,
        sender_nonce: Option<String>,
    },
    #[serde(rename = "accept")]
    Accept { id: String },
    #[serde(rename = "reject")]
    Reject { id: String, reason: Option<String> },
    #[serde(rename = "cancel")]
    Cancel { id: String, reason: Option<String> },
    #[serde(rename = "eof")]
    Eof { id: String },
}

static MANAGERS: Lazy<Mutex<HashMap<String, Arc<Mutex<FileTransferManager>>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

// FRB sync entrypoints may run on threads without an active Tokio reactor.
// Keep a fallback runtime for lightweight background initialization tasks.
static FALLBACK_RUNTIME: Lazy<tokio::runtime::Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(1)
        .thread_name("mobile-bridge-bg")
        .build()
        .expect("failed to create fallback tokio runtime")
});

fn now_nonce() -> String {
    let micros = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros())
        .unwrap_or(0);
    format!("{}-{}", micros, rand::random::<u32>())
}

async fn get_manager(connection_id: &str) -> Arc<Mutex<FileTransferManager>> {
    let mut guard = MANAGERS.lock().await;
    guard
        .entry(connection_id.to_string())
        .or_insert_with(|| {
            Arc::new(Mutex::new(FileTransferManager {
                connection_id: connection_id.to_string(),
                instance_nonce: now_nonce(),
                current_state: FileTransferStateDto {
                    status: TransferStatusDto::Idle,
                    file_name: None,
                    total_bytes: 0,
                    bytes_transferred: 0,
                    error: None,
                },
                current_session: None,
                pending_states: Vec::new(),
            }))
        })
        .clone()
}

fn push_state(manager: &mut FileTransferManager, state: FileTransferStateDto) {
    manager.current_state = state.clone();
    manager.pending_states.push(state);
}

fn parse_file_message(text: &str) -> anyhow::Result<IncomingFileMessage> {
    let value: serde_json::Value = serde_json::from_str(text)?;
    let parsed = serde_json::from_value::<IncomingFileMessage>(value)?;
    Ok(parsed)
}

pub fn is_file_transfer_control_message(text: &str) -> bool {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(text) else {
        return false;
    };

    matches!(
        value.get("type").and_then(|value| value.as_str()),
        Some(MSG_METADATA | MSG_ACCEPT | MSG_REJECT | MSG_CANCEL | MSG_EOF)
    )
}

async fn compute_sha256(path: &Path) -> anyhow::Result<String> {
    let mut file = File::open(path).await?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; CHUNK_SIZE];
    loop {
        let n = file.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

fn split_file_name(file_name: &str) -> (&str, &str) {
    let separator_index = file_name.rfind('.');
    match separator_index {
        Some(idx) if idx > 0 => (&file_name[..idx], &file_name[idx..]),
        _ => (file_name, ""),
    }
}

async fn create_unique_destination_file(
    dir: &Path,
    file_name: &str,
) -> anyhow::Result<(PathBuf, File)> {
    let (base, extension) = split_file_name(file_name);
    let mut counter = 0;

    loop {
        let candidate_name = if counter == 0 {
            file_name.to_string()
        } else {
            format!("{} ({}){}", base, counter, extension)
        };
        let candidate = dir.join(&candidate_name);

        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
            .await
        {
            Ok(file) => return Ok((candidate, file)),
            Err(err) if err.kind() == ErrorKind::AlreadyExists => {
                counter += 1;
            }
            Err(err) => return Err(err.into()),
        }
    }
}

async fn finalize_received_file(
    temp_path: &Path,
    target_dir: &Path,
    file_name: &str,
) -> anyhow::Result<PathBuf> {
    let (final_path, mut destination) =
        create_unique_destination_file(target_dir, file_name).await?;
    let mut source = File::open(temp_path).await?;
    tokio::io::copy(&mut source, &mut destination).await?;
    destination.flush().await?;
    drop(destination);
    tokio::fs::remove_file(temp_path).await?;
    Ok(final_path)
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

fn compare_offer_priority(
    local_id: &str,
    local_nonce: &str,
    remote_id: &str,
    remote_nonce: &str,
) -> i32 {
    let local_key = format!("{}|{}", local_id, local_nonce);
    let remote_key = format!("{}|{}", remote_id, remote_nonce);
    if local_key < remote_key {
        -1
    } else if local_key > remote_key {
        1
    } else {
        0
    }
}

#[derive(Serialize)]
struct OutMetadata<'a> {
    r#type: &'a str,
    id: &'a str,
    name: &'a str,
    size: u64,
    sha256: &'a str,
    sender_nonce: &'a str,
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_transfer(connection_id: String) {
    let task = async move {
        let _ = get_manager(&connection_id).await;
    };

    if let Ok(handle) = tokio::runtime::Handle::try_current() {
        handle.spawn(task);
    } else {
        FALLBACK_RUNTIME.spawn(task);
    }
}

pub async fn send_offer(connection_id: String, file_path: String) -> anyhow::Result<()> {
    let manager_arc = get_manager(&connection_id).await;

    let path = PathBuf::from(file_path);
    let meta = tokio::fs::metadata(&path).await?;
    let size = meta.len();
    if size > MAX_FILE_SIZE_BYTES {
        anyhow::bail!("File exceeds max size");
    }

    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string();
    let sha256 = compute_sha256(&path).await?;
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let id = millis.to_string();

    {
        let mut manager = manager_arc.lock().await;
        if manager.current_session.is_some() {
            anyhow::bail!("Transfer already in progress");
        }

        manager.current_session = Some(FileTransferSession {
            id: id.clone(),
            file_name: name.clone(),
            file_size: size,
            is_sender: true,
            expected_sha256: Some(sha256.clone()),
            sender_nonce: Some(manager.instance_nonce.clone()),
            source_file_path: Some(path.clone()),
            destination_dir: None,
            temp_path: None,
            writer: None,
            bytes_received: 0,
            hasher: None,
            accept_deadline: Some(Instant::now() + ACCEPT_TIMEOUT),
            inactivity_deadline: None,
        });

        push_state(
            &mut manager,
            FileTransferStateDto {
                status: TransferStatusDto::Offering,
                file_name: Some(name.clone()),
                total_bytes: size,
                bytes_transferred: 0,
                error: None,
            },
        );
    }

    let sender_nonce = {
        let manager = manager_arc.lock().await;
        manager.instance_nonce.clone()
    };

    let msg = serde_json::to_string(&OutMetadata {
        r#type: MSG_METADATA,
        id: &id,
        name: &name,
        size,
        sha256: &sha256,
        sender_nonce: &sender_nonce,
    })?;

    if let Err(e) = webrtc::send_control_message(connection_id.clone(), msg).await {
        let mut manager = manager_arc.lock().await;
        push_state(
            &mut manager,
            FileTransferStateDto {
                status: TransferStatusDto::Error,
                file_name: Some(name),
                total_bytes: size,
                bytes_transferred: 0,
                error: Some(format!("send offer failed: {e}")),
            },
        );
        manager.current_session = None;
    } else if webrtc::send_file_transfer_prompt(connection_id)
        .await
        .is_err()
    {
        tracing::warn!("file transfer prompt failed");
    }

    Ok(())
}

async fn start_transfer_robust(
    connection_id: String,
    manager_arc: Arc<Mutex<FileTransferManager>>,
) -> anyhow::Result<()> {
    let (transfer_id, path, file_size) = {
        let mut manager = manager_arc.lock().await;
        let (id, path, size, file_name) = {
            let session = manager
                .current_session
                .as_mut()
                .ok_or_else(|| anyhow::anyhow!("no active transfer session"))?;

            session.inactivity_deadline = Some(Instant::now() + INACTIVITY_TIMEOUT);

            (
                session.id.clone(),
                session
                    .source_file_path
                    .clone()
                    .ok_or_else(|| anyhow::anyhow!("missing source file path"))?,
                session.file_size,
                session.file_name.clone(),
            )
        };

        push_state(
            &mut manager,
            FileTransferStateDto {
                status: TransferStatusDto::Transferring,
                file_name: Some(file_name.clone()),
                total_bytes: size,
                bytes_transferred: 0,
                error: None,
            },
        );

        (id, path, size)
    };

    webrtc::set_file_buffered_amount_low_threshold(connection_id.clone(), LOW_WATER_MARK).await?;

    let mut raf = File::open(&path).await?;
    let mut offset = 0u64;

    while offset < file_size {
        {
            let manager = manager_arc.lock().await;
            if let Some(session) = manager.current_session.as_ref() {
                if !session.is_sender || session.id != transfer_id {
                    anyhow::bail!("transfer no longer active");
                }
            } else {
                anyhow::bail!("transfer ended");
            }
        }

        loop {
            let buffered = webrtc::get_file_buffered_amount(connection_id.clone()).await?;
            if buffered <= HIGH_WATER_MARK {
                break;
            }
            sleep(Duration::from_millis(15)).await;
        }

        let to_read = std::cmp::min(CHUNK_SIZE as u64, file_size - offset) as usize;
        let mut chunk = vec![0u8; to_read];
        let n = raf.read(&mut chunk).await?;
        if n == 0 {
            break;
        }
        chunk.truncate(n);

        webrtc::send_file_chunk(connection_id.clone(), chunk).await?;
        offset += n as u64;

        let mut manager = manager_arc.lock().await;
        if let Some(session) = manager.current_session.as_mut() {
            session.inactivity_deadline = Some(Instant::now() + INACTIVITY_TIMEOUT);
            let session_file_name = session.file_name.clone();
            push_state(
                &mut manager,
                FileTransferStateDto {
                    status: TransferStatusDto::Transferring,
                    file_name: Some(session_file_name),
                    total_bytes: file_size,
                    bytes_transferred: offset,
                    error: None,
                },
            );
        }
    }

    let eof = serde_json::json!({"type": MSG_EOF, "id": transfer_id}).to_string();
    webrtc::send_file_message(connection_id.clone(), eof).await?;

    let mut manager = manager_arc.lock().await;
    let completed_file_name = manager
        .current_session
        .as_ref()
        .map(|s| s.file_name.clone());
    push_state(
        &mut manager,
        FileTransferStateDto {
            status: TransferStatusDto::Completed,
            file_name: completed_file_name,
            total_bytes: file_size,
            bytes_transferred: file_size,
            error: None,
        },
    );
    manager.current_session = None;

    Ok(())
}

pub async fn accept_offer(connection_id: String, save_dir: String) -> anyhow::Result<()> {
    let manager_arc = get_manager(&connection_id).await;
    let dest_dir = PathBuf::from(&save_dir);
    tokio::fs::create_dir_all(&dest_dir).await?;

    let (transfer_id, file_name) = {
        let mut manager = manager_arc.lock().await;
        let session = manager
            .current_session
            .as_mut()
            .ok_or_else(|| anyhow::anyhow!("no incoming offer"))?;
        if session.is_sender {
            anyhow::bail!("active session is sender side");
        }

        let temp_path = std::env::temp_dir().join(format!("relink-recv-{}.tmp", session.id));
        session.destination_dir = Some(dest_dir.clone());
        session.temp_path = Some(temp_path.clone());
        session.writer = Some(File::create(&temp_path).await?);
        session.hasher = Some(Sha256::new());
        session.inactivity_deadline = Some(Instant::now() + INACTIVITY_TIMEOUT);

        let transfer_id = session.id.clone();
        let file_name = session.file_name.clone();
        let file_size = session.file_size;

        push_state(
            &mut manager,
            FileTransferStateDto {
                status: TransferStatusDto::Receiving,
                file_name: Some(file_name.clone()),
                total_bytes: file_size,
                bytes_transferred: 0,
                error: None,
            },
        );

        (transfer_id, file_name)
    };

    webrtc::wait_for_file_channel_ready(connection_id.clone())
        .await
        .map_err(|e| anyhow::anyhow!("file transfer channel is not ready yet: {e}"))?;

    let msg = serde_json::json!({"type": MSG_ACCEPT, "id": transfer_id}).to_string();
    let _ = file_name;
    webrtc::send_control_message(connection_id, msg).await
}

pub async fn reject_offer(connection_id: String, reason: Option<String>) -> anyhow::Result<()> {
    let manager_arc = get_manager(&connection_id).await;

    let transfer_id = {
        let mut manager = manager_arc.lock().await;
        let id = manager.current_session.as_ref().map(|s| s.id.clone());
        manager.current_session = None;
        push_state(
            &mut manager,
            FileTransferStateDto {
                status: TransferStatusDto::Idle,
                file_name: None,
                total_bytes: 0,
                bytes_transferred: 0,
                error: None,
            },
        );
        id
    };

    if let Some(id) = transfer_id {
        let msg = serde_json::json!({"type": MSG_REJECT, "id": id, "reason": reason}).to_string();
        webrtc::send_control_message(connection_id, msg).await?;
    }

    Ok(())
}

pub async fn cancel_transfer(connection_id: String, reason: Option<String>) -> anyhow::Result<()> {
    let manager_arc = get_manager(&connection_id).await;

    let transfer_id = {
        let mut manager = manager_arc.lock().await;
        let id = manager.current_session.as_ref().map(|s| s.id.clone());
        manager.current_session = None;
        push_state(
            &mut manager,
            FileTransferStateDto {
                status: TransferStatusDto::Error,
                file_name: None,
                total_bytes: 0,
                bytes_transferred: 0,
                error: Some("Cancelled".to_string()),
            },
        );
        id
    };

    if let Some(id) = transfer_id {
        let msg = serde_json::json!({"type": MSG_CANCEL, "id": id, "reason": reason}).to_string();
        let _ = webrtc::send_control_message(connection_id, msg).await;
    }

    Ok(())
}

pub async fn handle_file_message(connection_id: String, text: String) -> anyhow::Result<()> {
    let manager_arc = get_manager(&connection_id).await;
    let parsed = parse_file_message(&text)?;

    match parsed {
        IncomingFileMessage::Metadata {
            id,
            name,
            size,
            sha256,
            sender_nonce,
        } => {
            let mut auto_reject: Option<String> = None;
            {
                let mut manager = manager_arc.lock().await;

                if let Some(existing) = manager.current_session.as_ref() {
                    if existing.is_sender
                        && matches!(manager.current_state.status, TransferStatusDto::Offering)
                    {
                        if let (Some(local_nonce), Some(remote_nonce)) =
                            (existing.sender_nonce.as_ref(), sender_nonce.as_ref())
                        {
                            if compare_offer_priority(&existing.id, local_nonce, &id, remote_nonce)
                                < 0
                            {
                                auto_reject = Some("collision_local_offer_won".to_string());
                            } else {
                                let local_id = existing.id.clone();
                                manager.current_session = None;
                                let cancel =
                                    serde_json::json!({"type": MSG_CANCEL, "id": local_id, "reason": "collision_remote_offer_won"}).to_string();
                                let conn = manager.connection_id.clone();
                                tokio::spawn(async move {
                                    let _ = webrtc::send_control_message(conn, cancel).await;
                                });
                            }
                        }
                    } else {
                        auto_reject = Some("busy".to_string());
                    }
                }

                if manager.current_session.is_none() && auto_reject.is_none() {
                    if size > MAX_FILE_SIZE_BYTES {
                        auto_reject = Some("size_limit".to_string());
                    } else {
                        manager.current_session = Some(FileTransferSession {
                            id: id.clone(),
                            file_name: name.clone(),
                            file_size: size,
                            is_sender: false,
                            expected_sha256: Some(sha256),
                            sender_nonce,
                            source_file_path: None,
                            destination_dir: None,
                            temp_path: None,
                            writer: None,
                            bytes_received: 0,
                            hasher: None,
                            accept_deadline: None,
                            inactivity_deadline: None,
                        });

                        push_state(
                            &mut manager,
                            FileTransferStateDto {
                                status: TransferStatusDto::Offered,
                                file_name: Some(name),
                                total_bytes: size,
                                bytes_transferred: 0,
                                error: None,
                            },
                        );
                    }
                }
            }

            if let Some(reason) = auto_reject {
                let msg =
                    serde_json::json!({"type": MSG_REJECT, "id": id, "reason": reason}).to_string();
                webrtc::send_control_message(connection_id, msg).await?;
            }
        }
        IncomingFileMessage::Accept { id } => {
            let can_start = {
                let mut manager = manager_arc.lock().await;
                if let Some(session) = manager.current_session.as_mut() {
                    if session.is_sender && session.id == id {
                        session.accept_deadline = None;
                        true
                    } else {
                        false
                    }
                } else {
                    false
                }
            };

            if can_start {
                let conn = connection_id.clone();
                let manager_for_task = Arc::clone(&manager_arc);
                tokio::spawn(async move {
                    if let Err(e) =
                        start_transfer_robust(conn.clone(), manager_for_task.clone()).await
                    {
                        let mut manager = manager_for_task.lock().await;
                        let error_file_name = manager
                            .current_session
                            .as_ref()
                            .map(|s| s.file_name.clone());
                        let error_total_bytes = manager
                            .current_session
                            .as_ref()
                            .map(|s| s.file_size)
                            .unwrap_or(0);
                        push_state(
                            &mut manager,
                            FileTransferStateDto {
                                status: TransferStatusDto::Error,
                                file_name: error_file_name,
                                total_bytes: error_total_bytes,
                                bytes_transferred: 0,
                                error: Some(format!("send error: {e}")),
                            },
                        );
                        manager.current_session = None;
                    }
                });
            }
        }
        IncomingFileMessage::Reject { id, .. } => {
            let mut manager = manager_arc.lock().await;
            if manager
                .current_session
                .as_ref()
                .map(|s| s.id == id)
                .unwrap_or(false)
            {
                let error_file_name = manager
                    .current_session
                    .as_ref()
                    .map(|s| s.file_name.clone());
                let error_total_bytes = manager
                    .current_session
                    .as_ref()
                    .map(|s| s.file_size)
                    .unwrap_or(0);
                push_state(
                    &mut manager,
                    FileTransferStateDto {
                        status: TransferStatusDto::Error,
                        file_name: error_file_name,
                        total_bytes: error_total_bytes,
                        bytes_transferred: 0,
                        error: Some("Rejected by peer".to_string()),
                    },
                );
                manager.current_session = None;
            }
        }
        IncomingFileMessage::Cancel { id, .. } => {
            let mut manager = manager_arc.lock().await;
            if manager
                .current_session
                .as_ref()
                .map(|s| s.id == id)
                .unwrap_or(false)
            {
                let error_file_name = manager
                    .current_session
                    .as_ref()
                    .map(|s| s.file_name.clone());
                let error_total_bytes = manager
                    .current_session
                    .as_ref()
                    .map(|s| s.file_size)
                    .unwrap_or(0);
                push_state(
                    &mut manager,
                    FileTransferStateDto {
                        status: TransferStatusDto::Error,
                        file_name: error_file_name,
                        total_bytes: error_total_bytes,
                        bytes_transferred: 0,
                        error: Some("Cancelled by peer".to_string()),
                    },
                );
                manager.current_session = None;
            }
        }
        IncomingFileMessage::Eof { id } => {
            let mut manager = manager_arc.lock().await;
            let mut finalization: Option<(PathBuf, PathBuf, String, u64)> = None;
            let mut terminal_state: Option<FileTransferStateDto> = None;
            if let Some(session) = manager.current_session.as_mut() {
                if !session.is_sender && session.id == id {
                    if let Some(mut writer) = session.writer.take() {
                        writer.flush().await?;
                    }

                    let expected_size = session.file_size;
                    let received = session.bytes_received;
                    if expected_size != received {
                        terminal_state = Some(FileTransferStateDto {
                            status: TransferStatusDto::Error,
                            file_name: Some(session.file_name.clone()),
                            total_bytes: expected_size,
                            bytes_transferred: received,
                            error: Some("Size mismatch".to_string()),
                        });
                    }

                    if terminal_state.is_none() {
                        let computed_sha = if let Some(hasher) = session.hasher.take() {
                            hex::encode(hasher.finalize())
                        } else {
                            String::new()
                        };

                        if session
                            .expected_sha256
                            .as_ref()
                            .map(|s| s != &computed_sha)
                            .unwrap_or(false)
                        {
                            terminal_state = Some(FileTransferStateDto {
                                status: TransferStatusDto::Error,
                                file_name: Some(session.file_name.clone()),
                                total_bytes: expected_size,
                                bytes_transferred: received,
                                error: Some("SHA-256 mismatch".to_string()),
                            });
                        }
                    }

                    if terminal_state.is_none() {
                        if let Some(temp_path) = session.temp_path.clone() {
                            let target_dir = session
                                .destination_dir
                                .clone()
                                .unwrap_or_else(|| PathBuf::from("."));
                            let safe_name = sanitize_file_name(&session.file_name);
                            finalization = Some((temp_path, target_dir, safe_name, expected_size));
                        } else {
                            terminal_state = Some(FileTransferStateDto {
                                status: TransferStatusDto::Error,
                                file_name: Some(session.file_name.clone()),
                                total_bytes: expected_size,
                                bytes_transferred: received,
                                error: Some("Missing temporary file".to_string()),
                            });
                        }
                    }
                }
            }

            if let Some(state) = terminal_state {
                push_state(&mut manager, state);
                manager.current_session = None;
                return Ok(());
            }

            if let Some((temp, target_dir, safe_name, total)) = finalization {
                let final_path = finalize_received_file(&temp, &target_dir, &safe_name).await?;
                let saved_name = final_path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or(&safe_name)
                    .to_string();
                push_state(
                    &mut manager,
                    FileTransferStateDto {
                        status: TransferStatusDto::Completed,
                        file_name: Some(saved_name),
                        total_bytes: total,
                        bytes_transferred: total,
                        error: None,
                    },
                );
                manager.current_session = None;
            }
        }
    }

    Ok(())
}

pub async fn handle_file_chunk(connection_id: String, bytes: Vec<u8>) -> anyhow::Result<()> {
    let manager_arc = get_manager(&connection_id).await;
    let mut manager = manager_arc.lock().await;

    if let Some(session) = manager.current_session.as_mut() {
        if !session.is_sender {
            if let Some(writer) = session.writer.as_mut() {
                writer.write_all(&bytes).await?;
            }
            if let Some(hasher) = session.hasher.as_mut() {
                hasher.update(&bytes);
            }
            session.bytes_received += bytes.len() as u64;
            session.inactivity_deadline = Some(Instant::now() + INACTIVITY_TIMEOUT);
            let session_file_name = session.file_name.clone();
            let session_file_size = session.file_size;
            let session_bytes_received = session.bytes_received;

            if session_bytes_received > session_file_size {
                push_state(
                    &mut manager,
                    FileTransferStateDto {
                        status: TransferStatusDto::Error,
                        file_name: Some(session_file_name),
                        total_bytes: session_file_size,
                        bytes_transferred: session_bytes_received,
                        error: Some("Size mismatch".to_string()),
                    },
                );
                manager.current_session = None;
            } else {
                push_state(
                    &mut manager,
                    FileTransferStateDto {
                        status: TransferStatusDto::Receiving,
                        file_name: Some(session_file_name),
                        total_bytes: session_file_size,
                        bytes_transferred: session_bytes_received,
                        error: None,
                    },
                );
            }
        }
    }

    Ok(())
}

pub async fn tick(connection_id: String) -> anyhow::Result<()> {
    let manager_arc = get_manager(&connection_id).await;
    let mut timed_out = None;

    {
        let mut manager = manager_arc.lock().await;
        if let Some(session) = manager.current_session.as_ref() {
            let now = Instant::now();
            if session
                .accept_deadline
                .map(|deadline| now > deadline)
                .unwrap_or(false)
            {
                timed_out = Some((session.id.clone(), "accept_timeout".to_string()));
            } else if session
                .inactivity_deadline
                .map(|deadline| now > deadline)
                .unwrap_or(false)
            {
                timed_out = Some((session.id.clone(), "inactivity_timeout".to_string()));
            }
        }

        if let Some((_, ref reason)) = timed_out {
            let error_file_name = manager
                .current_session
                .as_ref()
                .map(|s| s.file_name.clone());
            let error_total_bytes = manager
                .current_session
                .as_ref()
                .map(|s| s.file_size)
                .unwrap_or(0);
            push_state(
                &mut manager,
                FileTransferStateDto {
                    status: TransferStatusDto::Error,
                    file_name: error_file_name,
                    total_bytes: error_total_bytes,
                    bytes_transferred: 0,
                    error: Some(reason.clone()),
                },
            );
            manager.current_session = None;
        }
    }

    if let Some((id, reason)) = timed_out {
        let msg = serde_json::json!({"type": MSG_CANCEL, "id": id, "reason": reason}).to_string();
        let _ = webrtc::send_control_message(connection_id, msg).await;
    }

    Ok(())
}

pub async fn drain_states(connection_id: String) -> anyhow::Result<Vec<FileTransferStateDto>> {
    let manager_arc = get_manager(&connection_id).await;
    let mut manager = manager_arc.lock().await;
    if manager.pending_states.is_empty() {
        Ok(vec![manager.current_state.clone()])
    } else {
        Ok(std::mem::take(&mut manager.pending_states))
    }
}

pub async fn dispose_transfer(connection_id: String) {
    let mut guard = MANAGERS.lock().await;
    guard.remove(&connection_id);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_dir(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "relink-file-transfer-{}-{}-{}",
            name,
            std::process::id(),
            rand::random::<u64>()
        ))
    }

    #[tokio::test]
    async fn finalize_received_file_creates_numbered_copy_without_overwriting() -> anyhow::Result<()>
    {
        let dir = test_dir("numbered");
        tokio::fs::create_dir_all(&dir).await?;

        let existing = dir.join("interim-report.pdf");
        tokio::fs::write(&existing, b"existing").await?;

        let temp = dir.join("incoming.tmp");
        tokio::fs::write(&temp, b"new").await?;

        let saved = finalize_received_file(&temp, &dir, "interim-report.pdf").await?;

        assert_eq!(
            saved.file_name().and_then(|name| name.to_str()),
            Some("interim-report (1).pdf")
        );
        assert_eq!(tokio::fs::read(&existing).await?, b"existing");
        assert_eq!(tokio::fs::read(&saved).await?, b"new");

        tokio::fs::remove_dir_all(&dir).await?;
        Ok(())
    }

    #[tokio::test]
    async fn finalize_received_file_keeps_incrementing_suffixes() -> anyhow::Result<()> {
        let dir = test_dir("incrementing");
        tokio::fs::create_dir_all(&dir).await?;

        tokio::fs::write(dir.join("interim-report.pdf"), b"existing").await?;
        tokio::fs::write(dir.join("interim-report (1).pdf"), b"existing").await?;

        let temp = dir.join("incoming.tmp");
        tokio::fs::write(&temp, b"new").await?;

        let saved = finalize_received_file(&temp, &dir, "interim-report.pdf").await?;

        assert_eq!(
            saved.file_name().and_then(|name| name.to_str()),
            Some("interim-report (2).pdf")
        );
        assert_eq!(tokio::fs::read(&saved).await?, b"new");

        tokio::fs::remove_dir_all(&dir).await?;
        Ok(())
    }
}
