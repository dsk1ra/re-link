use crate::api::transfer::{remove_connection, set_data_channel, upsert_connection};
use anyhow::Context;
use ice::network_type::NetworkType;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::time::{sleep, Duration};
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::setting_engine::SettingEngine;
use webrtc::api::APIBuilder;
use webrtc::api::API;
use webrtc::data_channel::data_channel_init::RTCDataChannelInit;
use webrtc::data_channel::data_channel_state::RTCDataChannelState;
use webrtc::data_channel::RTCDataChannel;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
use webrtc::ice_transport::ice_server::RTCIceServer;
use webrtc::interceptor::registry::Registry;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;

#[derive(Debug, Clone)]
pub struct IceServerConfig {
    pub urls: Vec<String>,
    pub username: Option<String>,
    pub credential: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SessionDescriptionDto {
    pub kind: String,
    pub sdp: String,
}

#[derive(Debug, Clone)]
pub struct IceCandidateDto {
    pub candidate: String,
    pub sdp_mid: Option<String>,
    pub sdp_mline_index: Option<u16>,
}

#[derive(Debug, Clone)]
pub enum WebRtcEvent {
    ConnectionStateChanged {
        state: String,
    },
    DataChannelStateChanged {
        label: String,
        state: String,
    },
    LocalIceCandidate {
        candidate: IceCandidateDto,
    },
    RenegotiationOffer {
        description: SessionDescriptionDto,
    },
    RenegotiationAnswer {
        description: SessionDescriptionDto,
    },
    RenegotiationIce {
        candidate: IceCandidateDto,
    },
    FileTransferRequested,
    SessionClosed {
        id: Option<String>,
        reason: Option<String>,
    },
    VideoFrame {
        data: Vec<u8>,
        width: u32,
        height: u32,
    },
    SessionClosedAck {
        id: Option<String>,
    },
    Ping {
        ts: Option<String>,
    },
    Pong {
        ts: Option<String>,
    },
    ControlMessage {
        message: String,
    },
    FileMessage {
        message: String,
    },
    FileChunk {
        bytes: Vec<u8>,
    },
    FileBufferedAmountLow,
}

struct WebRtcSession {
    connection_id: String,
    pc: Arc<RTCPeerConnection>,
    control_channel: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
    file_channel: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
    events: Arc<Mutex<Vec<WebRtcEvent>>>,
}

static WEBRTC_API: Lazy<Result<Arc<API>, String>> = Lazy::new(|| {
    let mut media_engine = MediaEngine::default();
    media_engine
        .register_default_codecs()
        .map_err(|e| e.to_string())?;

    let mut registry = Registry::new();
    registry =
        register_default_interceptors(registry, &mut media_engine).map_err(|e| e.to_string())?;
    let mut setting_engine = SettingEngine::default();
    configure_ice_setting_engine(&mut setting_engine);

    Ok(Arc::new(
        APIBuilder::new()
            .with_setting_engine(setting_engine)
            .with_media_engine(media_engine)
            .with_interceptor_registry(registry)
            .build(),
    ))
});

static SESSIONS: Lazy<Mutex<HashMap<String, Arc<WebRtcSession>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

const FILE_SEND_RETRY_ATTEMPTS: usize = 500;
const FILE_SEND_RETRY_DELAY: Duration = Duration::from_millis(20);
const CONTROL_CHANNEL_ID: u16 = 0;
const FILE_TRANSFER_CHANNEL_ID: u16 = 1;

async fn wait_for_data_channel_open(
    channel: &Arc<RTCDataChannel>,
    channel_label: &str,
) -> anyhow::Result<()> {
    for _ in 0..FILE_SEND_RETRY_ATTEMPTS {
        let state: RTCDataChannelState = channel.ready_state();
        match state {
            RTCDataChannelState::Open => return Ok(()),
            RTCDataChannelState::Closing | RTCDataChannelState::Closed => {
                anyhow::bail!("{channel_label} data channel is {state}");
            }
            RTCDataChannelState::Connecting => {
                sleep(FILE_SEND_RETRY_DELAY).await;
            }
            _ => {
                sleep(FILE_SEND_RETRY_DELAY).await;
            }
        }
    }

    anyhow::bail!(
        "{channel_label} data channel did not open within {}ms",
        FILE_SEND_RETRY_ATTEMPTS as u64 * FILE_SEND_RETRY_DELAY.as_millis() as u64
    )
}

async fn wait_for_named_data_channel(
    session: &Arc<WebRtcSession>,
    channel_label: &str,
) -> anyhow::Result<Arc<RTCDataChannel>> {
    for _ in 0..FILE_SEND_RETRY_ATTEMPTS {
        let channel = match channel_label {
            "control" => session.control_channel.lock().await.clone(),
            "file_transfer" => session.file_channel.lock().await.clone(),
            _ => anyhow::bail!("unknown data channel label: {channel_label}"),
        };

        if let Some(channel) = channel {
            wait_for_data_channel_open(&channel, channel_label).await?;
            return Ok(channel);
        }

        sleep(FILE_SEND_RETRY_DELAY).await;
    }

    anyhow::bail!(
        "{channel_label} data channel did not become available within {}ms",
        FILE_SEND_RETRY_ATTEMPTS as u64 * FILE_SEND_RETRY_DELAY.as_millis() as u64
    )
}

async fn ensure_data_channel(
    session: &Arc<WebRtcSession>,
    label: &str,
    negotiated_id: u16,
) -> anyhow::Result<()> {
    let already_exists = match label {
        "control" => session.control_channel.lock().await.is_some(),
        "file_transfer" => session.file_channel.lock().await.is_some(),
        _ => anyhow::bail!("unknown data channel label: {label}"),
    };

    if already_exists {
        return Ok(());
    }

    let channel = session
        .pc
        .create_data_channel(
            label,
            Some(RTCDataChannelInit {
                ordered: Some(true),
                negotiated: Some(negotiated_id),
                ..Default::default()
            }),
        )
        .await
        .with_context(|| format!("failed to create {label} data channel"))?;
    attach_data_channel(session, channel).await;

    Ok(())
}

async fn ensure_default_data_channels(session: &Arc<WebRtcSession>) -> anyhow::Result<()> {
    ensure_data_channel(session, "control", CONTROL_CHANNEL_ID).await?;
    ensure_data_channel(session, "file_transfer", FILE_TRANSFER_CHANNEL_ID).await?;
    Ok(())
}

fn get_api() -> anyhow::Result<Arc<API>> {
    WEBRTC_API
        .as_ref()
        .map(Arc::clone)
        .map_err(|e| anyhow::anyhow!(e.clone()))
}

fn normalize_sdp_kind(kind: &str) -> String {
    kind.trim().to_ascii_lowercase()
}

fn to_sdp_dto(desc: RTCSessionDescription) -> SessionDescriptionDto {
    SessionDescriptionDto {
        kind: desc.sdp_type.to_string(),
        sdp: desc.sdp,
    }
}

fn to_webrtc_ice_server(server: IceServerConfig) -> RTCIceServer {
    RTCIceServer {
        urls: server.urls,
        username: server.username.unwrap_or_default(),
        credential: server.credential.unwrap_or_default(),
        ..Default::default()
    }
}

fn state_label(state: RTCPeerConnectionState) -> String {
    state.to_string()
}

fn configure_ice_setting_engine(setting_engine: &mut SettingEngine) {
    if cfg!(windows) {
        // Keep UDP enabled for both IPv4 and IPv6 on Windows.
        // The IP filter below already strips loopback/link-local candidates,
        // so disabling IPv6 here unnecessarily breaks some mobile networks.
        setting_engine.set_network_types(vec![NetworkType::Udp4, NetworkType::Udp6]);
    }

    setting_engine.set_ip_filter(Box::new(should_gather_ice_ip));
}

fn should_gather_ice_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ipv4) => {
            !ipv4.is_loopback()
                && !ipv4.is_link_local()
                && !ipv4.is_multicast()
                && !ipv4.is_unspecified()
        }
        IpAddr::V6(ipv6) => {
            !ipv6.is_loopback()
                && !ipv6.is_multicast()
                && !ipv6.is_unspecified()
                && !ipv6.is_unicast_link_local()
        }
    }
}

async fn push_event(events: &Arc<Mutex<Vec<WebRtcEvent>>>, event: WebRtcEvent) {
    let mut guard = events.lock().await;
    guard.push(event);
}

enum ParsedControlMessage {
    RenegotiationOffer(SessionDescriptionDto),
    RenegotiationAnswer(SessionDescriptionDto),
    RenegotiationIce(IceCandidateDto),
    FileTransferRequested,
    SessionClosed {
        id: Option<String>,
        reason: Option<String>,
    },
    SessionClosedAck {
        id: Option<String>,
    },
    Ping {
        ts: Option<String>,
    },
    Pong {
        ts: Option<String>,
    },
}

fn parse_control_message(text: &str) -> Option<ParsedControlMessage> {
    let value = serde_json::from_str::<serde_json::Value>(text).ok()?;
    let message_type = value.get("type")?.as_str()?;

    match message_type {
        "webrtc_offer" => {
            let data = value.get("data")?;
            Some(ParsedControlMessage::RenegotiationOffer(
                SessionDescriptionDto {
                    kind: data.get("type")?.as_str()?.to_string(),
                    sdp: data.get("sdp")?.as_str()?.to_string(),
                },
            ))
        }
        "webrtc_answer" => {
            let data = value.get("data")?;
            Some(ParsedControlMessage::RenegotiationAnswer(
                SessionDescriptionDto {
                    kind: data.get("type")?.as_str()?.to_string(),
                    sdp: data.get("sdp")?.as_str()?.to_string(),
                },
            ))
        }
        "webrtc_ice" => {
            let data = value.get("data")?;
            Some(ParsedControlMessage::RenegotiationIce(IceCandidateDto {
                candidate: data.get("candidate")?.as_str()?.to_string(),
                sdp_mid: data
                    .get("sdpMid")
                    .and_then(|value| value.as_str())
                    .map(ToOwned::to_owned),
                sdp_mline_index: data
                    .get("sdpMLineIndex")
                    .and_then(|value| value.as_u64())
                    .map(|value| value as u16),
            }))
        }
        "file_transfer_offer" => Some(ParsedControlMessage::FileTransferRequested),
        "session_closed" => Some(ParsedControlMessage::SessionClosed {
            id: value
                .get("id")
                .and_then(|value| value.as_str())
                .map(ToOwned::to_owned),
            reason: value
                .get("reason")
                .and_then(|value| value.as_str())
                .map(ToOwned::to_owned),
        }),
        "session_closed_ack" => Some(ParsedControlMessage::SessionClosedAck {
            id: value
                .get("id")
                .and_then(|value| value.as_str())
                .map(ToOwned::to_owned),
        }),
        "ping" => Some(ParsedControlMessage::Ping {
            ts: value
                .get("ts")
                .and_then(|value| value.as_str())
                .map(ToOwned::to_owned),
        }),
        "pong" => Some(ParsedControlMessage::Pong {
            ts: value
                .get("ts")
                .and_then(|value| value.as_str())
                .map(ToOwned::to_owned),
        }),
        _ => None,
    }
}

async fn attach_data_channel(session: &Arc<WebRtcSession>, dc: Arc<RTCDataChannel>) {
    let label = dc.label().to_string();

    let open_events = Arc::clone(&session.events);
    let open_label = label.clone();
    dc.on_open(Box::new(move || {
        let open_events = Arc::clone(&open_events);
        let open_label = open_label.clone();
        Box::pin(async move {
            push_event(
                &open_events,
                WebRtcEvent::DataChannelStateChanged {
                    label: open_label,
                    state: "open".to_string(),
                },
            )
            .await;
        })
    }));

    let close_events = Arc::clone(&session.events);
    let close_label = label.clone();
    dc.on_close(Box::new(move || {
        let close_events = Arc::clone(&close_events);
        let close_label = close_label.clone();
        Box::pin(async move {
            push_event(
                &close_events,
                WebRtcEvent::DataChannelStateChanged {
                    label: close_label,
                    state: "closed".to_string(),
                },
            )
            .await;
        })
    }));

    let msg_events = Arc::clone(&session.events);
    let msg_label = label.clone();
    let msg_connection_id = session.connection_id.clone();
    dc.on_message(Box::new(move |msg| {
        let msg_events = Arc::clone(&msg_events);
        let msg_label = msg_label.clone();
        let msg_connection_id = msg_connection_id.clone();
        Box::pin(async move {
            if msg.is_string {
                if let Ok(text) = std::str::from_utf8(&msg.data) {
                    if msg_label == "control" {
                        if crate::api::file_transfer::is_file_transfer_control_message(text) {
                            if crate::api::file_transfer::handle_file_message(
                                msg_connection_id.clone(),
                                text.to_string(),
                            )
                            .await
                            .is_err()
                            {
                                tracing::warn!("control file transfer message handling failed");
                            }
                        } else if let Some(parsed) = parse_control_message(text) {
                            let event = match parsed {
                                ParsedControlMessage::RenegotiationOffer(description) => {
                                    WebRtcEvent::RenegotiationOffer { description }
                                }
                                ParsedControlMessage::RenegotiationAnswer(description) => {
                                    WebRtcEvent::RenegotiationAnswer { description }
                                }
                                ParsedControlMessage::RenegotiationIce(candidate) => {
                                    WebRtcEvent::RenegotiationIce { candidate }
                                }
                                ParsedControlMessage::FileTransferRequested => {
                                    WebRtcEvent::FileTransferRequested
                                }
                                ParsedControlMessage::SessionClosed { id, reason } => {
                                    WebRtcEvent::SessionClosed { id, reason }
                                }
                                ParsedControlMessage::SessionClosedAck { id } => {
                                    WebRtcEvent::SessionClosedAck { id }
                                }
                                ParsedControlMessage::Ping { ts } => WebRtcEvent::Ping { ts },
                                ParsedControlMessage::Pong { ts } => WebRtcEvent::Pong { ts },
                            };
                            push_event(&msg_events, event).await;
                        } else {
                            push_event(
                                &msg_events,
                                WebRtcEvent::ControlMessage {
                                    message: text.to_string(),
                                },
                            )
                            .await;
                        }
                    } else if msg_label == "file_transfer" {
                        if crate::api::file_transfer::handle_file_message(
                            msg_connection_id.clone(),
                            text.to_string(),
                        )
                        .await
                        .is_err()
                        {
                            tracing::warn!("file transfer control message handling failed");
                        }
                    }
                }
            } else if msg_label == "file_transfer" {
                if crate::api::file_transfer::handle_file_chunk(
                    msg_connection_id.clone(),
                    msg.data.to_vec(),
                )
                .await
                .is_err()
                {
                    tracing::warn!("file transfer chunk handling failed");
                }
            }
        })
    }));

    if label == "file_transfer" {
        let low_events = Arc::clone(&session.events);
        dc.on_buffered_amount_low(Box::new(move || {
            let low_events = Arc::clone(&low_events);
            Box::pin(async move {
                push_event(&low_events, WebRtcEvent::FileBufferedAmountLow).await;
            })
        }))
        .await;
    }

    if label == "control" {
        let mut guard = session.control_channel.lock().await;
        *guard = Some(Arc::clone(&dc));
    } else if label == "file_transfer" {
        let mut guard = session.file_channel.lock().await;
        *guard = Some(Arc::clone(&dc));
    }

    let _ = set_data_channel(
        session.connection_id.clone(),
        label.clone(),
        Arc::clone(&dc),
    )
    .await;
}

async fn get_session(connection_id: &str) -> anyhow::Result<Arc<WebRtcSession>> {
    let sessions = SESSIONS.lock().await;
    sessions.get(connection_id).cloned().ok_or_else(|| {
        anyhow::anyhow!("webrtc session not found for connection_id={connection_id}")
    })
}

pub async fn create_session(
    connection_id: String,
    ice_servers: Vec<IceServerConfig>,
) -> anyhow::Result<()> {
    let api = get_api()?;
    let config = RTCConfiguration {
        ice_servers: if ice_servers.is_empty() {
            vec![RTCIceServer {
                urls: vec!["stun:localhost:3478".to_string()],
                ..Default::default()
            }]
        } else {
            ice_servers
                .into_iter()
                .map(to_webrtc_ice_server)
                .collect::<Vec<_>>()
        },
        ..Default::default()
    };

    let pc = Arc::new(api.new_peer_connection(config).await?);

    let session = Arc::new(WebRtcSession {
        connection_id: connection_id.clone(),
        pc: Arc::clone(&pc),
        control_channel: Arc::new(Mutex::new(None)),
        file_channel: Arc::new(Mutex::new(None)),
        events: Arc::new(Mutex::new(Vec::new())),
    });

    let candidate_events = Arc::clone(&session.events);
    pc.on_ice_candidate(Box::new(move |candidate| {
        let candidate_events = Arc::clone(&candidate_events);
        Box::pin(async move {
            if let Some(candidate) = candidate {
                if let Ok(candidate_init) = candidate.to_json() {
                    push_event(
                        &candidate_events,
                        WebRtcEvent::LocalIceCandidate {
                            candidate: IceCandidateDto {
                                candidate: candidate_init.candidate,
                                sdp_mid: candidate_init.sdp_mid,
                                sdp_mline_index: candidate_init.sdp_mline_index,
                            },
                        },
                    )
                    .await;
                }
            }
        })
    }));

    let state_events = Arc::clone(&session.events);
    pc.on_peer_connection_state_change(Box::new(move |state| {
        let state_events = Arc::clone(&state_events);
        Box::pin(async move {
            push_event(
                &state_events,
                WebRtcEvent::ConnectionStateChanged {
                    state: state_label(state),
                },
            )
            .await;
        })
    }));

    let session_for_dc = Arc::clone(&session);
    pc.on_data_channel(Box::new(move |dc| {
        let session_for_dc = Arc::clone(&session_for_dc);
        Box::pin(async move {
            attach_data_channel(&session_for_dc, dc).await;
        })
    }));

    upsert_connection(connection_id.clone(), Arc::clone(&pc)).await?;
    let mut sessions = SESSIONS.lock().await;
    sessions.insert(connection_id, session);

    Ok(())
}

pub async fn create_offer(connection_id: String) -> anyhow::Result<SessionDescriptionDto> {
    let session = get_session(&connection_id).await?;
    ensure_default_data_channels(&session).await?;

    let offer = session
        .pc
        .create_offer(None)
        .await
        .context("failed to create offer")?;
    session
        .pc
        .set_local_description(offer)
        .await
        .context("failed to set local offer description")?;

    let local = if let Some(local) = session.pc.pending_local_description().await {
        local
    } else {
        session
            .pc
            .current_local_description()
            .await
            .ok_or_else(|| anyhow::anyhow!("missing local offer description"))?
    };

    Ok(to_sdp_dto(local))
}

pub async fn create_answer(
    connection_id: String,
    remote_offer: SessionDescriptionDto,
) -> anyhow::Result<SessionDescriptionDto> {
    if normalize_sdp_kind(&remote_offer.kind) != "offer" {
        anyhow::bail!("remote_offer.kind must be 'offer'");
    }

    let session = get_session(&connection_id).await?;
    ensure_default_data_channels(&session).await?;
    session
        .pc
        .set_remote_description(RTCSessionDescription::offer(remote_offer.sdp)?)
        .await
        .context("failed to set remote offer description")?;

    let answer = session
        .pc
        .create_answer(None)
        .await
        .context("failed to create answer")?;
    session
        .pc
        .set_local_description(answer)
        .await
        .context("failed to set local answer description")?;

    let local = if let Some(local) = session.pc.pending_local_description().await {
        local
    } else {
        session
            .pc
            .current_local_description()
            .await
            .ok_or_else(|| anyhow::anyhow!("missing local answer description"))?
    };

    Ok(to_sdp_dto(local))
}

pub async fn set_remote_answer(
    connection_id: String,
    remote_answer: SessionDescriptionDto,
) -> anyhow::Result<()> {
    if normalize_sdp_kind(&remote_answer.kind) != "answer" {
        anyhow::bail!("remote_answer.kind must be 'answer'");
    }

    let session = get_session(&connection_id).await?;
    session
        .pc
        .set_remote_description(RTCSessionDescription::answer(remote_answer.sdp)?)
        .await
        .context("failed to set remote answer description")?;

    Ok(())
}

pub async fn add_ice_candidate(
    connection_id: String,
    candidate: IceCandidateDto,
) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let init = RTCIceCandidateInit {
        candidate: candidate.candidate,
        sdp_mid: candidate.sdp_mid,
        sdp_mline_index: candidate.sdp_mline_index,
        username_fragment: None,
    };

    session
        .pc
        .add_ice_candidate(init)
        .await
        .context("failed to add remote ice candidate")?;

    Ok(())
}

pub async fn send_control_message(connection_id: String, message: String) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let channel = wait_for_named_data_channel(&session, "control")
        .await
        .context("failed to send control message")?;

    channel
        .send_text(message)
        .await
        .context("failed to send control message")?;

    Ok(())
}

pub async fn send_renegotiation_offer(
    connection_id: String,
    description: SessionDescriptionDto,
) -> anyhow::Result<()> {
    let message = serde_json::json!({
        "type": "webrtc_offer",
        "data": {
            "sdp": description.sdp,
            "type": description.kind,
        }
    })
    .to_string();
    send_control_message(connection_id, message).await
}

pub async fn send_renegotiation_answer(
    connection_id: String,
    description: SessionDescriptionDto,
) -> anyhow::Result<()> {
    let message = serde_json::json!({
        "type": "webrtc_answer",
        "data": {
            "sdp": description.sdp,
            "type": description.kind,
        }
    })
    .to_string();
    send_control_message(connection_id, message).await
}

pub async fn send_renegotiation_ice(
    connection_id: String,
    candidate: IceCandidateDto,
) -> anyhow::Result<()> {
    let message = serde_json::json!({
        "type": "webrtc_ice",
        "data": {
            "candidate": candidate.candidate,
            "sdpMid": candidate.sdp_mid,
            "sdpMLineIndex": candidate.sdp_mline_index,
        }
    })
    .to_string();
    send_control_message(connection_id, message).await
}

pub async fn send_file_transfer_prompt(connection_id: String) -> anyhow::Result<()> {
    send_control_message(
        connection_id,
        serde_json::json!({"type": "file_transfer_offer"}).to_string(),
    )
    .await
}

pub async fn send_session_closed(
    connection_id: String,
    id: String,
    reason: Option<String>,
) -> anyhow::Result<()> {
    send_control_message(
        connection_id,
        serde_json::json!({
            "type": "session_closed",
            "id": id,
            "reason": reason,
        })
        .to_string(),
    )
    .await
}

pub async fn send_session_closed_ack(connection_id: String, id: String) -> anyhow::Result<()> {
    send_control_message(
        connection_id,
        serde_json::json!({
            "type": "session_closed_ack",
            "id": id,
        })
        .to_string(),
    )
    .await
}

pub async fn send_ping(connection_id: String, ts: String) -> anyhow::Result<()> {
    send_control_message(
        connection_id,
        serde_json::json!({
            "type": "ping",
            "ts": ts,
        })
        .to_string(),
    )
    .await
}

pub async fn send_pong(connection_id: String, ts: Option<String>) -> anyhow::Result<()> {
    send_control_message(
        connection_id,
        serde_json::json!({
            "type": "pong",
            "ts": ts,
        })
        .to_string(),
    )
    .await
}

pub async fn send_file_message(connection_id: String, message: String) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let channel = wait_for_named_data_channel(&session, "file_transfer")
        .await
        .context("failed to send file channel message")?;

    let mut last_err: Option<webrtc::error::Error> = None;
    for _ in 0..FILE_SEND_RETRY_ATTEMPTS {
        match channel.send_text(message.clone()).await {
            Ok(_) => return Ok(()),
            Err(err) => {
                let err_text = err.to_string();
                if err_text.contains("DataChannel is not opened") {
                    last_err = Some(err);
                    sleep(FILE_SEND_RETRY_DELAY).await;
                    continue;
                }
                return Err(err).context("failed to send file channel message");
            }
        }
    }

    if let Some(err) = last_err {
        return Err(err).context("failed to send file channel message");
    }

    Ok(())
}

pub async fn send_file_chunk(connection_id: String, bytes: Vec<u8>) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let channel = wait_for_named_data_channel(&session, "file_transfer")
        .await
        .context("failed to send file chunk")?;

    let mut last_err: Option<webrtc::error::Error> = None;
    for _ in 0..FILE_SEND_RETRY_ATTEMPTS {
        match channel.send(&bytes.clone().into()).await {
            Ok(_) => return Ok(()),
            Err(err) => {
                let err_text = err.to_string();
                if err_text.contains("DataChannel is not opened") {
                    last_err = Some(err);
                    sleep(FILE_SEND_RETRY_DELAY).await;
                    continue;
                }
                return Err(err).context("failed to send file chunk");
            }
        }
    }

    if let Some(err) = last_err {
        return Err(err).context("failed to send file chunk");
    }

    Ok(())
}

pub async fn get_file_buffered_amount(connection_id: String) -> anyhow::Result<u64> {
    let session = get_session(&connection_id).await?;
    let channel = wait_for_named_data_channel(&session, "file_transfer").await?;

    Ok(channel.buffered_amount().await as u64)
}

pub async fn set_file_buffered_amount_low_threshold(
    connection_id: String,
    threshold: u64,
) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let channel = wait_for_named_data_channel(&session, "file_transfer").await?;

    channel
        .set_buffered_amount_low_threshold(threshold as usize)
        .await;

    Ok(())
}

pub async fn wait_for_file_channel_ready(connection_id: String) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let _ = wait_for_named_data_channel(&session, "file_transfer").await?;
    Ok(())
}

pub async fn drain_events(connection_id: String) -> anyhow::Result<Vec<WebRtcEvent>> {
    let session = get_session(&connection_id).await?;
    let mut events = session.events.lock().await;
    Ok(std::mem::take(&mut *events))
}

pub async fn close_session(connection_id: String) -> anyhow::Result<()> {
    let session = {
        let mut sessions = SESSIONS.lock().await;
        sessions.remove(&connection_id)
    };

    if let Some(session) = session {
        let _ = session.pc.close().await;
    }

    remove_connection(&connection_id).await;

    Ok(())
}
