use crate::api::webrtc;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, VecDeque};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::fs::{File, OpenOptions};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::time::{sleep, Duration, Instant};

const MSG_METADATA: &str = "metadata";
const MSG_ACCEPT: &str = "accept";
const MSG_REJECT: &str = "reject";
const MSG_CANCEL: &str = "cancel";
const MSG_EOF: &str = "eof";

const MAX_FILE_SIZE_BYTES: u64 = 512 * 1024 * 1024;
const ACCEPT_TIMEOUT: Duration = Duration::from_secs(30);
const INACTIVITY_TIMEOUT: Duration = Duration::from_secs(30);
const INTERNAL_TICK_INTERVAL: Duration = Duration::from_secs(1);
const COMMAND_CHANNEL_CAPACITY: usize = 32;
const STATE_HISTORY_CAPACITY: usize = 64;
const PROGRESS_UPDATE_BYTES: u64 = 64 * 1024;
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SessionRole {
    Sender,
    Receiver,
}

#[derive(Debug)]
struct FileTransferSession {
    id: String,
    file_name: String,
    file_size: u64,
    role: SessionRole,
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
    cancel_flag: Option<Arc<AtomicBool>>,
    worker_started: bool,
}

struct FileTransferActor {
    connection_id: String,
    instance_nonce: String,
    current_state: FileTransferStateDto,
    current_session: Option<FileTransferSession>,
    pending_states: VecDeque<FileTransferStateDto>,
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

#[derive(Serialize)]
struct OutMetadata<'a> {
    r#type: &'a str,
    id: &'a str,
    name: &'a str,
    size: u64,
    sha256: &'a str,
    sender_nonce: &'a str,
}

type ResponseSender<T> = oneshot::Sender<anyhow::Result<T>>;

enum ActorCommand {
    SendOffer {
        file_path: String,
        reply: ResponseSender<()>,
    },
    AcceptOffer {
        save_dir: String,
        reply: ResponseSender<()>,
    },
    RejectOffer {
        reason: Option<String>,
        reply: ResponseSender<()>,
    },
    CancelTransfer {
        reason: Option<String>,
        reply: ResponseSender<()>,
    },
    IncomingControl {
        text: String,
        reply: ResponseSender<()>,
    },
    IncomingChunk {
        bytes: Vec<u8>,
        reply: ResponseSender<()>,
    },
    Tick {
        reply: Option<ResponseSender<()>>,
    },
    DrainStates {
        reply: ResponseSender<Vec<FileTransferStateDto>>,
    },
    SenderProgress {
        id: String,
        bytes_transferred: u64,
    },
    SenderFinished {
        id: String,
        total_bytes: u64,
    },
    SenderFailed {
        id: String,
        error: String,
    },
    Shutdown {
        reply: oneshot::Sender<()>,
    },
}

#[derive(Clone)]
struct ActorHandle {
    id: String,
    tx: mpsc::Sender<ActorCommand>,
}

static ACTORS: Lazy<Mutex<HashMap<String, ActorHandle>>> = Lazy::new(|| Mutex::new(HashMap::new()));

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

impl FileTransferActor {
    fn new(connection_id: String) -> Self {
        Self {
            connection_id,
            instance_nonce: now_nonce(),
            current_state: FileTransferStateDto {
                status: TransferStatusDto::Idle,
                file_name: None,
                total_bytes: 0,
                bytes_transferred: 0,
                error: None,
            },
            current_session: None,
            pending_states: VecDeque::new(),
        }
    }

    fn push_state(&mut self, state: FileTransferStateDto) {
        self.current_state = state.clone();

        if let Some(last) = self.pending_states.back_mut() {
            if should_coalesce_progress_state(last, &state) {
                *last = state;
                return;
            }
        }

        if self.pending_states.len() >= STATE_HISTORY_CAPACITY {
            self.pending_states.pop_front();
        }
        self.pending_states.push_back(state);
    }

    fn drain_states(&mut self) -> Vec<FileTransferStateDto> {
        if self.pending_states.is_empty() {
            vec![self.current_state.clone()]
        } else {
            self.pending_states.drain(..).collect()
        }
    }

    async fn clear_current_session(&mut self) {
        if let Some(session) = self.current_session.take() {
            cleanup_session_resources(session).await;
        }
    }

    async fn fail_current_session(&mut self, message: impl Into<String>) {
        let (file_name, total_bytes, bytes_transferred) =
            state_snapshot_for_session(self.current_session.as_ref(), &self.current_state);
        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Error,
            file_name,
            total_bytes,
            bytes_transferred,
            error: Some(message.into()),
        });
        self.clear_current_session().await;
    }

    async fn handle_send_offer(&mut self, file_path: String) -> anyhow::Result<()> {
        if self.current_session.is_some() {
            anyhow::bail!("Transfer already in progress");
        }

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
        let id = now_nonce();
        let sender_nonce = self.instance_nonce.clone();

        self.current_session = Some(FileTransferSession {
            id: id.clone(),
            file_name: name.clone(),
            file_size: size,
            role: SessionRole::Sender,
            expected_sha256: Some(sha256.clone()),
            sender_nonce: Some(sender_nonce.clone()),
            source_file_path: Some(path.clone()),
            destination_dir: None,
            temp_path: None,
            writer: None,
            bytes_received: 0,
            hasher: None,
            accept_deadline: Some(Instant::now() + ACCEPT_TIMEOUT),
            inactivity_deadline: None,
            cancel_flag: Some(Arc::new(AtomicBool::new(false))),
            worker_started: false,
        });
        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Offering,
            file_name: Some(name.clone()),
            total_bytes: size,
            bytes_transferred: 0,
            error: None,
        });

        let metadata = serde_json::to_string(&OutMetadata {
            r#type: MSG_METADATA,
            id: &id,
            name: &name,
            size,
            sha256: &sha256,
            sender_nonce: &sender_nonce,
        })?;

        if let Err(error) = webrtc::send_control_message(self.connection_id.clone(), metadata).await
        {
            self.push_state(FileTransferStateDto {
                status: TransferStatusDto::Error,
                file_name: Some(name),
                total_bytes: size,
                bytes_transferred: 0,
                error: Some(format!("send offer failed: {error}")),
            });
            self.clear_current_session().await;
            return Err(error);
        }

        if webrtc::send_file_transfer_prompt(self.connection_id.clone())
            .await
            .is_err()
        {
            tracing::warn!("file transfer prompt failed");
        }

        Ok(())
    }

    async fn handle_accept_offer(&mut self, save_dir: String) -> anyhow::Result<()> {
        let dest_dir = PathBuf::from(&save_dir);
        tokio::fs::create_dir_all(&dest_dir).await?;
        webrtc::wait_for_file_channel_ready(self.connection_id.clone())
            .await
            .map_err(|e| anyhow::anyhow!("file transfer channel is not ready yet: {e}"))?;

        let (transfer_id, file_name) = {
            let session = self
                .current_session
                .as_mut()
                .ok_or_else(|| anyhow::anyhow!("no incoming offer"))?;
            if session.role != SessionRole::Receiver {
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

            self.push_state(FileTransferStateDto {
                status: TransferStatusDto::Receiving,
                file_name: Some(file_name.clone()),
                total_bytes: file_size,
                bytes_transferred: 0,
                error: None,
            });

            (transfer_id, file_name)
        };

        let msg = serde_json::json!({"type": MSG_ACCEPT, "id": transfer_id}).to_string();
        if let Err(error) = webrtc::send_control_message(self.connection_id.clone(), msg).await {
            self.push_state(FileTransferStateDto {
                status: TransferStatusDto::Error,
                file_name: Some(file_name),
                total_bytes: self.current_state.total_bytes,
                bytes_transferred: 0,
                error: Some(format!("accept failed: {error}")),
            });
            self.clear_current_session().await;
            return Err(error);
        }

        Ok(())
    }

    async fn handle_reject_offer(&mut self, reason: Option<String>) -> anyhow::Result<()> {
        let transfer_id = self
            .current_session
            .as_ref()
            .map(|session| session.id.clone());
        self.clear_current_session().await;
        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Idle,
            file_name: None,
            total_bytes: 0,
            bytes_transferred: 0,
            error: None,
        });

        if let Some(id) = transfer_id {
            let msg =
                serde_json::json!({"type": MSG_REJECT, "id": id, "reason": reason}).to_string();
            webrtc::send_control_message(self.connection_id.clone(), msg).await?;
        }

        Ok(())
    }

    async fn handle_cancel_transfer(&mut self, reason: Option<String>) -> anyhow::Result<()> {
        let transfer_id = self
            .current_session
            .as_ref()
            .map(|session| session.id.clone());
        let cancel_message = reason.clone().unwrap_or_else(|| "Cancelled".to_string());
        let (file_name, total_bytes, bytes_transferred) =
            state_snapshot_for_session(self.current_session.as_ref(), &self.current_state);

        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Error,
            file_name,
            total_bytes,
            bytes_transferred,
            error: Some(cancel_message),
        });
        self.clear_current_session().await;

        if let Some(id) = transfer_id {
            let msg =
                serde_json::json!({"type": MSG_CANCEL, "id": id, "reason": reason}).to_string();
            let _ = webrtc::send_control_message(self.connection_id.clone(), msg).await;
        }

        Ok(())
    }

    async fn handle_incoming_message(
        &mut self,
        tx: &mpsc::Sender<ActorCommand>,
        parsed: IncomingFileMessage,
    ) -> anyhow::Result<()> {
        match parsed {
            IncomingFileMessage::Metadata {
                id,
                name,
                size,
                sha256,
                sender_nonce,
            } => {
                let mut auto_reject: Option<String> = None;

                if let Some(existing) = self.current_session.as_ref() {
                    if existing.role == SessionRole::Sender
                        && matches!(self.current_state.status, TransferStatusDto::Offering)
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
                                self.clear_current_session().await;
                                let cancel = serde_json::json!({
                                    "type": MSG_CANCEL,
                                    "id": local_id,
                                    "reason": "collision_remote_offer_won",
                                })
                                .to_string();
                                let _ = webrtc::send_control_message(
                                    self.connection_id.clone(),
                                    cancel,
                                )
                                .await;
                            }
                        }
                    } else {
                        auto_reject = Some("busy".to_string());
                    }
                }

                if self.current_session.is_none() && auto_reject.is_none() {
                    if size > MAX_FILE_SIZE_BYTES {
                        auto_reject = Some("size_limit".to_string());
                    } else {
                        self.current_session = Some(FileTransferSession {
                            id: id.clone(),
                            file_name: name.clone(),
                            file_size: size,
                            role: SessionRole::Receiver,
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
                            cancel_flag: None,
                            worker_started: false,
                        });
                        self.push_state(FileTransferStateDto {
                            status: TransferStatusDto::Offered,
                            file_name: Some(name),
                            total_bytes: size,
                            bytes_transferred: 0,
                            error: None,
                        });
                    }
                }

                if let Some(reason) = auto_reject {
                    let reject =
                        serde_json::json!({"type": MSG_REJECT, "id": id, "reason": reason})
                            .to_string();
                    webrtc::send_control_message(self.connection_id.clone(), reject).await?;
                }
            }
            IncomingFileMessage::Accept { id } => {
                let (path, file_size, cancel_flag, should_start) = {
                    let session = match self.current_session.as_mut() {
                        Some(session)
                            if session.role == SessionRole::Sender
                                && session.id == id
                                && !session.worker_started =>
                        {
                            session
                        }
                        _ => return Ok(()),
                    };

                    session.accept_deadline = None;
                    session.inactivity_deadline = Some(Instant::now() + INACTIVITY_TIMEOUT);
                    session.worker_started = true;

                    (
                        session
                            .source_file_path
                            .clone()
                            .ok_or_else(|| anyhow::anyhow!("missing source file path"))?,
                        session.file_size,
                        session
                            .cancel_flag
                            .as_ref()
                            .cloned()
                            .ok_or_else(|| anyhow::anyhow!("missing sender cancel flag"))?,
                        true,
                    )
                };

                if should_start {
                    spawn_sender_pipeline(
                        self.connection_id.clone(),
                        id,
                        path,
                        file_size,
                        cancel_flag,
                        tx.clone(),
                    );
                }
            }
            IncomingFileMessage::Reject { id, .. } => {
                if self
                    .current_session
                    .as_ref()
                    .map(|session| session.id == id)
                    .unwrap_or(false)
                {
                    self.fail_current_session("Rejected by peer").await;
                }
            }
            IncomingFileMessage::Cancel { id, .. } => {
                if self
                    .current_session
                    .as_ref()
                    .map(|session| session.id == id)
                    .unwrap_or(false)
                {
                    self.fail_current_session("Cancelled by peer").await;
                }
            }
            IncomingFileMessage::Eof { id } => {
                self.handle_incoming_eof(id).await?;
            }
        }

        Ok(())
    }

    async fn handle_incoming_chunk(&mut self, bytes: Vec<u8>) -> anyhow::Result<()> {
        let mut should_error = false;
        let mut error_state: Option<FileTransferStateDto> = None;
        let mut should_emit_progress = None;

        if let Some(session) = self.current_session.as_mut() {
            if session.role == SessionRole::Receiver {
                if let Some(writer) = session.writer.as_mut() {
                    writer.write_all(&bytes).await?;
                }
                if let Some(hasher) = session.hasher.as_mut() {
                    hasher.update(&bytes);
                }
                session.bytes_received += bytes.len() as u64;
                session.inactivity_deadline = Some(Instant::now() + INACTIVITY_TIMEOUT);

                if session.bytes_received > session.file_size {
                    should_error = true;
                    error_state = Some(FileTransferStateDto {
                        status: TransferStatusDto::Error,
                        file_name: Some(session.file_name.clone()),
                        total_bytes: session.file_size,
                        bytes_transferred: session.bytes_received,
                        error: Some("Size mismatch".to_string()),
                    });
                } else {
                    let should_report = session.bytes_received == session.file_size
                        || session
                            .bytes_received
                            .saturating_sub(self.current_state.bytes_transferred)
                            >= PROGRESS_UPDATE_BYTES;
                    if should_report {
                        should_emit_progress = Some(FileTransferStateDto {
                            status: TransferStatusDto::Receiving,
                            file_name: Some(session.file_name.clone()),
                            total_bytes: session.file_size,
                            bytes_transferred: session.bytes_received,
                            error: None,
                        });
                    }
                }
            }
        }

        if let Some(progress) = should_emit_progress {
            self.push_state(progress);
        }

        if should_error {
            if let Some(state) = error_state {
                self.push_state(state);
            }
            self.clear_current_session().await;
        }

        Ok(())
    }

    async fn handle_incoming_eof(&mut self, id: String) -> anyhow::Result<()> {
        let Some(mut session) = self.current_session.take() else {
            return Ok(());
        };

        if session.role != SessionRole::Receiver || session.id != id {
            self.current_session = Some(session);
            return Ok(());
        }

        if let Some(mut writer) = session.writer.take() {
            writer.flush().await?;
        }

        let expected_size = session.file_size;
        let received = session.bytes_received;
        if expected_size != received {
            self.push_state(FileTransferStateDto {
                status: TransferStatusDto::Error,
                file_name: Some(session.file_name.clone()),
                total_bytes: expected_size,
                bytes_transferred: received,
                error: Some("Size mismatch".to_string()),
            });
            cleanup_session_resources(session).await;
            return Ok(());
        }

        let computed_sha = if let Some(hasher) = session.hasher.take() {
            hex::encode(hasher.finalize())
        } else {
            String::new()
        };
        if session
            .expected_sha256
            .as_ref()
            .map(|expected| expected != &computed_sha)
            .unwrap_or(false)
        {
            self.push_state(FileTransferStateDto {
                status: TransferStatusDto::Error,
                file_name: Some(session.file_name.clone()),
                total_bytes: expected_size,
                bytes_transferred: received,
                error: Some("SHA-256 mismatch".to_string()),
            });
            cleanup_session_resources(session).await;
            return Ok(());
        }

        let temp_path = session
            .temp_path
            .take()
            .ok_or_else(|| anyhow::anyhow!("Missing temporary file"))?;
        let target_dir = session
            .destination_dir
            .clone()
            .unwrap_or_else(|| PathBuf::from("."));
        let safe_name = sanitize_file_name(&session.file_name);
        let final_path = finalize_received_file(&temp_path, &target_dir, &safe_name).await?;
        let saved_name = final_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(&safe_name)
            .to_string();

        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Completed,
            file_name: Some(saved_name),
            total_bytes: expected_size,
            bytes_transferred: expected_size,
            error: None,
        });

        Ok(())
    }

    async fn handle_tick(&mut self) -> anyhow::Result<()> {
        let timeout = {
            let session = match self.current_session.as_ref() {
                Some(session) => session,
                None => return Ok(()),
            };

            let now = Instant::now();
            if session
                .accept_deadline
                .map(|deadline| now > deadline)
                .unwrap_or(false)
            {
                Some((session.id.clone(), "accept_timeout".to_string()))
            } else if session
                .inactivity_deadline
                .map(|deadline| now > deadline)
                .unwrap_or(false)
            {
                Some((session.id.clone(), "inactivity_timeout".to_string()))
            } else {
                None
            }
        };

        if let Some((id, reason)) = timeout {
            self.fail_current_session(reason.clone()).await;
            let cancel =
                serde_json::json!({"type": MSG_CANCEL, "id": id, "reason": reason}).to_string();
            let _ = webrtc::send_control_message(self.connection_id.clone(), cancel).await;
        }

        Ok(())
    }

    fn handle_sender_progress(&mut self, id: String, bytes_transferred: u64) {
        let Some(session) = self.current_session.as_mut() else {
            return;
        };
        if session.role != SessionRole::Sender || session.id != id {
            return;
        }

        session.inactivity_deadline = Some(Instant::now() + INACTIVITY_TIMEOUT);
        let file_name = session.file_name.clone();
        let file_size = session.file_size;
        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Transferring,
            file_name: Some(file_name),
            total_bytes: file_size,
            bytes_transferred: bytes_transferred.min(file_size),
            error: None,
        });
    }

    async fn handle_sender_finished(&mut self, id: String, total_bytes: u64) {
        let matches = self
            .current_session
            .as_ref()
            .map(|session| session.role == SessionRole::Sender && session.id == id)
            .unwrap_or(false);
        if !matches {
            return;
        }

        let (file_name, file_size) = {
            let session = self
                .current_session
                .as_ref()
                .expect("session checked above");
            (session.file_name.clone(), session.file_size)
        };
        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Completed,
            file_name: Some(file_name),
            total_bytes: file_size,
            bytes_transferred: total_bytes.min(file_size),
            error: None,
        });
        self.clear_current_session().await;
    }

    async fn handle_sender_failed(&mut self, id: String, error: String) {
        let matches = self
            .current_session
            .as_ref()
            .map(|session| session.role == SessionRole::Sender && session.id == id)
            .unwrap_or(false);
        if !matches {
            return;
        }

        let bytes_transferred = self.current_state.bytes_transferred;
        let (file_name, total_bytes, _) =
            state_snapshot_for_session(self.current_session.as_ref(), &self.current_state);
        self.push_state(FileTransferStateDto {
            status: TransferStatusDto::Error,
            file_name,
            total_bytes,
            bytes_transferred,
            error: Some(format!("send error: {error}")),
        });
        self.clear_current_session().await;
    }
}

fn should_coalesce_progress_state(
    current: &FileTransferStateDto,
    next: &FileTransferStateDto,
) -> bool {
    matches!(
        current.status,
        TransferStatusDto::Transferring | TransferStatusDto::Receiving
    ) && matches!(
        next.status,
        TransferStatusDto::Transferring | TransferStatusDto::Receiving
    ) && std::mem::discriminant(&current.status) == std::mem::discriminant(&next.status)
        && current.file_name == next.file_name
        && current.total_bytes == next.total_bytes
        && current.error == next.error
}

fn state_snapshot_for_session(
    session: Option<&FileTransferSession>,
    current_state: &FileTransferStateDto,
) -> (Option<String>, u64, u64) {
    if let Some(session) = session {
        (
            Some(session.file_name.clone()),
            session.file_size,
            current_state.bytes_transferred.min(session.file_size),
        )
    } else {
        (
            current_state.file_name.clone(),
            current_state.total_bytes,
            current_state.bytes_transferred,
        )
    }
}

async fn cleanup_session_resources(mut session: FileTransferSession) {
    if let Some(cancel_flag) = session.cancel_flag.take() {
        cancel_flag.store(true, Ordering::SeqCst);
    }

    if let Some(mut writer) = session.writer.take() {
        let _ = writer.flush().await;
    }

    if let Some(temp_path) = session.temp_path.take() {
        let _ = tokio::fs::remove_file(temp_path).await;
    }
}

async fn run_actor(
    connection_id: String,
    tx: mpsc::Sender<ActorCommand>,
    mut rx: mpsc::Receiver<ActorCommand>,
) {
    let mut actor = FileTransferActor::new(connection_id.clone());
    let tick_tx = tx.clone();
    tokio::spawn(async move {
        loop {
            sleep(INTERNAL_TICK_INTERVAL).await;
            if tick_tx
                .send(ActorCommand::Tick { reply: None })
                .await
                .is_err()
            {
                break;
            }
        }
    });

    while let Some(command) = rx.recv().await {
        match command {
            ActorCommand::SendOffer { file_path, reply } => {
                let _ = reply.send(actor.handle_send_offer(file_path).await);
            }
            ActorCommand::AcceptOffer { save_dir, reply } => {
                let _ = reply.send(actor.handle_accept_offer(save_dir).await);
            }
            ActorCommand::RejectOffer { reason, reply } => {
                let _ = reply.send(actor.handle_reject_offer(reason).await);
            }
            ActorCommand::CancelTransfer { reason, reply } => {
                let _ = reply.send(actor.handle_cancel_transfer(reason).await);
            }
            ActorCommand::IncomingControl { text, reply } => {
                let result = match parse_file_message(&text) {
                    Ok(parsed) => actor.handle_incoming_message(&tx, parsed).await,
                    Err(error) => Err(error),
                };
                let _ = reply.send(result);
            }
            ActorCommand::IncomingChunk { bytes, reply } => {
                let _ = reply.send(actor.handle_incoming_chunk(bytes).await);
            }
            ActorCommand::Tick { reply } => {
                let result = actor.handle_tick().await;
                if let Some(reply) = reply {
                    let _ = reply.send(result);
                }
            }
            ActorCommand::DrainStates { reply } => {
                let _ = reply.send(Ok(actor.drain_states()));
            }
            ActorCommand::SenderProgress {
                id,
                bytes_transferred,
            } => {
                actor.handle_sender_progress(id, bytes_transferred);
            }
            ActorCommand::SenderFinished { id, total_bytes } => {
                actor.handle_sender_finished(id, total_bytes).await;
            }
            ActorCommand::SenderFailed { id, error } => {
                actor.handle_sender_failed(id, error).await;
            }
            ActorCommand::Shutdown { reply } => {
                actor.clear_current_session().await;
                let _ = reply.send(());
                break;
            }
        }
    }

    actor.clear_current_session().await;
}

fn spawn_sender_pipeline(
    connection_id: String,
    transfer_id: String,
    file_path: PathBuf,
    file_size: u64,
    cancel_flag: Arc<AtomicBool>,
    actor_tx: mpsc::Sender<ActorCommand>,
) {
    tokio::spawn(async move {
        let result = async {
            webrtc::set_file_buffered_amount_low_threshold(connection_id.clone(), LOW_WATER_MARK)
                .await?;

            let (chunk_tx, mut chunk_rx) = mpsc::channel::<Vec<u8>>(1);
            let reader_cancel = cancel_flag.clone();
            let writer_cancel = cancel_flag.clone();
            let reader_path = file_path.clone();

            let reader = tokio::spawn(async move {
                let mut file = File::open(&reader_path).await?;
                loop {
                    if reader_cancel.load(Ordering::SeqCst) {
                        anyhow::bail!("transfer cancelled");
                    }

                    let mut buffer = vec![0u8; CHUNK_SIZE];
                    let n = file.read(&mut buffer).await?;
                    if n == 0 {
                        break;
                    }
                    buffer.truncate(n);

                    if chunk_tx.send(buffer).await.is_err() {
                        anyhow::bail!("writer channel closed");
                    }
                }

                Ok::<(), anyhow::Error>(())
            });

            let writer_connection_id = connection_id.clone();
            let writer_transfer_id = transfer_id.clone();
            let writer_actor_tx = actor_tx.clone();
            let writer = tokio::spawn(async move {
                let mut offset = 0u64;
                let mut last_reported = 0u64;

                while let Some(chunk) = chunk_rx.recv().await {
                    if writer_cancel.load(Ordering::SeqCst) {
                        anyhow::bail!("transfer cancelled");
                    }

                    loop {
                        let buffered =
                            webrtc::get_file_buffered_amount(writer_connection_id.clone()).await?;
                        if buffered <= HIGH_WATER_MARK {
                            break;
                        }
                        if writer_cancel.load(Ordering::SeqCst) {
                            anyhow::bail!("transfer cancelled");
                        }
                        sleep(Duration::from_millis(15)).await;
                    }

                    let chunk_len = chunk.len() as u64;
                    webrtc::send_file_chunk(writer_connection_id.clone(), chunk).await?;
                    offset += chunk_len;

                    if offset == file_size
                        || offset.saturating_sub(last_reported) >= PROGRESS_UPDATE_BYTES
                    {
                        last_reported = offset;
                        let _ = writer_actor_tx
                            .send(ActorCommand::SenderProgress {
                                id: writer_transfer_id.clone(),
                                bytes_transferred: offset,
                            })
                            .await;
                    }
                }

                let eof =
                    serde_json::json!({"type": MSG_EOF, "id": writer_transfer_id}).to_string();
                webrtc::send_file_message(writer_connection_id, eof).await?;
                Ok::<u64, anyhow::Error>(offset)
            });

            reader.await??;
            let total_bytes = writer.await??;
            Ok::<u64, anyhow::Error>(total_bytes)
        }
        .await;

        match result {
            Ok(total_bytes) => {
                let _ = actor_tx
                    .send(ActorCommand::SenderFinished {
                        id: transfer_id,
                        total_bytes,
                    })
                    .await;
            }
            Err(error) => {
                let _ = actor_tx
                    .send(ActorCommand::SenderFailed {
                        id: transfer_id,
                        error: error.to_string(),
                    })
                    .await;
            }
        }
    });
}

fn spawn_background_task<F>(task: F)
where
    F: std::future::Future<Output = ()> + Send + 'static,
{
    if let Ok(handle) = tokio::runtime::Handle::try_current() {
        handle.spawn(task);
    } else {
        FALLBACK_RUNTIME.spawn(task);
    }
}

async fn get_or_spawn_actor(connection_id: &str) -> ActorHandle {
    let mut actors = ACTORS.lock().await;
    if let Some(existing) = actors.get(connection_id) {
        if !existing.tx.is_closed() {
            return existing.clone();
        }
    }

    let actor_id = now_nonce();
    let (tx, rx) = mpsc::channel(COMMAND_CHANNEL_CAPACITY);
    let handle = ActorHandle {
        id: actor_id.clone(),
        tx: tx.clone(),
    };
    actors.insert(connection_id.to_string(), handle.clone());

    let cleanup_connection_id = connection_id.to_string();
    spawn_background_task(async move {
        run_actor(cleanup_connection_id.clone(), tx, rx).await;
        let mut actors = ACTORS.lock().await;
        if actors
            .get(&cleanup_connection_id)
            .map(|current| current.id.as_str())
            == Some(actor_id.as_str())
        {
            actors.remove(&cleanup_connection_id);
        }
    });

    handle
}

async fn request_actor<T, F>(connection_id: &str, build: F) -> anyhow::Result<T>
where
    T: Send + 'static,
    F: FnOnce(ResponseSender<T>) -> ActorCommand,
{
    let handle = get_or_spawn_actor(connection_id).await;
    let (reply_tx, reply_rx) = oneshot::channel();
    handle
        .tx
        .send(build(reply_tx))
        .await
        .map_err(|_| anyhow::anyhow!("file transfer actor command failed"))?;
    reply_rx
        .await
        .map_err(|_| anyhow::anyhow!("file transfer actor response dropped"))?
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_transfer(connection_id: String) {
    spawn_background_task(async move {
        let _ = get_or_spawn_actor(&connection_id).await;
    });
}

pub async fn send_offer(connection_id: String, file_path: String) -> anyhow::Result<()> {
    request_actor(&connection_id, move |reply| ActorCommand::SendOffer {
        file_path,
        reply,
    })
    .await
}

pub async fn accept_offer(connection_id: String, save_dir: String) -> anyhow::Result<()> {
    request_actor(&connection_id, move |reply| ActorCommand::AcceptOffer {
        save_dir,
        reply,
    })
    .await
}

pub async fn reject_offer(connection_id: String, reason: Option<String>) -> anyhow::Result<()> {
    request_actor(&connection_id, move |reply| ActorCommand::RejectOffer {
        reason,
        reply,
    })
    .await
}

pub async fn cancel_transfer(connection_id: String, reason: Option<String>) -> anyhow::Result<()> {
    request_actor(&connection_id, move |reply| ActorCommand::CancelTransfer {
        reason,
        reply,
    })
    .await
}

pub async fn handle_file_message(connection_id: String, text: String) -> anyhow::Result<()> {
    request_actor(&connection_id, move |reply| ActorCommand::IncomingControl {
        text,
        reply,
    })
    .await
}

pub async fn handle_file_chunk(connection_id: String, bytes: Vec<u8>) -> anyhow::Result<()> {
    request_actor(&connection_id, move |reply| ActorCommand::IncomingChunk {
        bytes,
        reply,
    })
    .await
}

pub async fn tick(connection_id: String) -> anyhow::Result<()> {
    request_actor(&connection_id, move |reply| ActorCommand::Tick {
        reply: Some(reply),
    })
    .await
}

pub async fn drain_states(connection_id: String) -> anyhow::Result<Vec<FileTransferStateDto>> {
    request_actor(&connection_id, move |reply| ActorCommand::DrainStates {
        reply,
    })
    .await
}

pub async fn dispose_transfer(connection_id: String) {
    let handle = {
        let mut actors = ACTORS.lock().await;
        actors.remove(&connection_id)
    };

    let Some(handle) = handle else {
        return;
    };

    let (reply_tx, reply_rx) = oneshot::channel();
    if handle
        .tx
        .send(ActorCommand::Shutdown { reply: reply_tx })
        .await
        .is_ok()
    {
        let _ = reply_rx.await;
    }
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

    #[test]
    fn progress_states_are_coalesced() {
        let mut actor = FileTransferActor::new("conn".to_string());
        actor.push_state(FileTransferStateDto {
            status: TransferStatusDto::Transferring,
            file_name: Some("demo.bin".to_string()),
            total_bytes: 100,
            bytes_transferred: 10,
            error: None,
        });
        actor.push_state(FileTransferStateDto {
            status: TransferStatusDto::Transferring,
            file_name: Some("demo.bin".to_string()),
            total_bytes: 100,
            bytes_transferred: 20,
            error: None,
        });

        let drained = actor.drain_states();
        assert_eq!(drained.len(), 1);
        assert_eq!(drained[0].bytes_transferred, 20);
    }
}
