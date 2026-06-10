use crate::api::transfer::{remove_connection, set_data_channel, upsert_connection};
use crate::frb_generated::StreamSink;
use anyhow::Context;
use ice::network_type::NetworkType;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::Write as _;
use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;
use tokio::time::{sleep, Duration};
use webrtc::api::interceptor_registry::{configure_rtcp_reports, configure_twcc_receiver_only};
use webrtc::api::media_engine::{MediaEngine, MIME_TYPE_OPUS};
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
use webrtc::peer_connection::offer_answer_options::RTCOfferOptions;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::rtp::codecs::h264::H264Packet;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::rtp_transceiver::rtp_sender::RTCRtpSender;
use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
use webrtc::track::track_local::TrackLocal;
use webrtc::track::track_remote::TrackRemote;

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

/// Descriptor for one decoded video frame. The pixel bytes live in the
/// shared `VIDEO_RING`; this struct carries only a pointer + length + slot
/// id across the FRB boundary. Dart wraps the pointer as a zero-copy
/// `Uint8List` view and MUST call `releaseVideoFrame(slot)` when done, or
/// the slot leaks. After all 4 slots leak the decoder drops every frame.
#[derive(Debug, Clone)]
pub struct RawVideoFrame {
    /// Raw pointer to the slot's bytes. Cast to i64 because Dart's `int` is
    /// 64-bit signed; the round-trip preserves the bit pattern.
    pub addr: i64,
    /// Bytes of decoded RGBA data (width * height * 4).
    pub len: u32,
    pub width: u32,
    pub height: u32,
    /// Index into the ring buffer — pass back via `releaseVideoFrame`.
    pub slot: u32,
    /// Wall-clock ns at the moment the decoder published the frame.
    pub ts_ns: i64,
}

pub(crate) struct EventBus {
    buffer: Mutex<Vec<WebRtcEvent>>,
    event_sink: Mutex<Option<StreamSink<WebRtcEvent>>>,
    video_sink: Mutex<Option<StreamSink<RawVideoFrame>>>,
}

impl EventBus {
    fn new() -> Self {
        Self {
            buffer: Mutex::new(Vec::new()),
            event_sink: Mutex::new(None),
            video_sink: Mutex::new(None),
        }
    }

    pub async fn push_event(&self, event: WebRtcEvent) {
        if let Some(sink) = self.event_sink.lock().await.as_ref() {
            let _ = sink.add(event);
        } else {
            self.buffer.lock().await.push(event);
        }
    }

    pub async fn push_video_frame(
        &self,
        addr: i64,
        len: u32,
        width: u32,
        height: u32,
        slot: u32,
        ts_ns: i64,
    ) {
        let _ = self
            .push_video_frame_timed(addr, len, width, height, slot, ts_ns)
            .await;
    }

    /// Variant that reports per-stage timing for the FRB hop. Returns
    /// `(mutex_lock_us, sink_add_us)`. When no sink is attached we release
    /// the slot immediately (we no longer buffer pixel data — the ring's
    /// slot lifetimes make that unworkable).
    pub async fn push_video_frame_timed(
        &self,
        addr: i64,
        len: u32,
        width: u32,
        height: u32,
        slot: u32,
        ts_ns: i64,
    ) -> (u64, u64) {
        let lock_started = Instant::now();
        let guard = self.video_sink.lock().await;
        let lock_us = lock_started.elapsed().as_micros() as u64;

        if let Some(sink) = guard.as_ref() {
            let add_started = Instant::now();
            let _ = sink.add(RawVideoFrame {
                addr,
                len,
                width,
                height,
                slot,
                ts_ns,
            });
            let sink_add_us = add_started.elapsed().as_micros() as u64;
            (lock_us, sink_add_us)
        } else {
            drop(guard);
            super::video_ring::VIDEO_RING.release(slot);
            (lock_us, 0)
        }
    }
}

pub(crate) struct WebRtcSession {
    connection_id: String,
    pub(crate) pc: Arc<RTCPeerConnection>,
    control_channel: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
    file_channel: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
    pub(crate) event_bus: Arc<EventBus>,
    pub(crate) video_track: Arc<Mutex<Option<Arc<TrackLocalStaticSample>>>>,
    pub(crate) video_sender: Arc<Mutex<Option<Arc<RTCRtpSender>>>>,
    pub(crate) audio_track: Arc<Mutex<Option<Arc<TrackLocalStaticSample>>>>,
    /// Separate from `audio_track` (voice chat): carries system/desktop
    /// audio loopback alongside a shared screen. Pre-negotiated the same
    /// way on both sides so starting it later needs no renegotiation; the
    /// side that never calls `start_desktop_audio_capture` just never
    /// writes samples to it.
    pub(crate) system_audio_track: Arc<Mutex<Option<Arc<TrackLocalStaticSample>>>>,
}

static WEBRTC_API: Lazy<Result<Arc<API>, String>> = Lazy::new(|| {
    let mut media_engine = MediaEngine::default();
    media_engine
        .register_default_codecs()
        .map_err(|e| e.to_string())?;

    // Manual interceptor setup instead of register_default_interceptors: the
    // default NACK generator tracks an 8192-packet window, and under sustained
    // loss its missing-list can exceed TransportLayerNack's 253-pair marshal
    // limit — every NACK then fails with "Too many reports" and retransmission
    // goes completely dead. A 4096 window caps the worst case at
    // ceil(4096/17) = 241 pairs, so NACKs always go out.
    let mut registry = Registry::new();
    media_engine.register_feedback(
        webrtc::rtp_transceiver::RTCPFeedback {
            typ: "nack".to_owned(),
            parameter: "".to_owned(),
        },
        webrtc::rtp_transceiver::rtp_codec::RTPCodecType::Video,
    );
    media_engine.register_feedback(
        webrtc::rtp_transceiver::RTCPFeedback {
            typ: "nack".to_owned(),
            parameter: "pli".to_owned(),
        },
        webrtc::rtp_transceiver::rtp_codec::RTPCodecType::Video,
    );
    registry.add(Box::new(
        webrtc::interceptor::nack::responder::Responder::builder(),
    ));
    registry.add(Box::new(
        webrtc::interceptor::nack::generator::Generator::builder().with_log2_size_minus_6(6),
    ));
    registry = configure_rtcp_reports(registry);
    registry =
        configure_twcc_receiver_only(registry, &mut media_engine).map_err(|e| e.to_string())?;
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

async fn ensure_data_channel(session: &Arc<WebRtcSession>, label: &str) -> anyhow::Result<()> {
    let already_exists = match label {
        "control" => session.control_channel.lock().await.is_some(),
        "file_transfer" => {
            let mut guard = session.file_channel.lock().await;
            if let Some(ch) = guard.as_ref() {
                if ch.ready_state() == RTCDataChannelState::Closed {
                    *guard = None;
                    false
                } else {
                    true
                }
            } else {
                false
            }
        }
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
                ..Default::default()
            }),
        )
        .await
        .with_context(|| format!("failed to create {label} data channel"))?;
    attach_data_channel(session, channel).await;

    Ok(())
}

async fn ensure_default_data_channels(session: &Arc<WebRtcSession>) -> anyhow::Result<()> {
    ensure_data_channel(session, "control").await?;
    ensure_data_channel(session, "file_transfer").await?;
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

/// Convenience for paths that hold an owned RGBA `Vec<u8>` (the local-preview
/// branches of the capture pipelines). Claims a ring slot, copies the bytes,
/// publishes, and forwards a descriptor. Drops the frame if no slot is free
/// or the buffer is too large.
pub(crate) async fn push_preview_frame(
    bus: &Arc<EventBus>,
    rgba: Vec<u8>,
    width: u32,
    height: u32,
) {
    let Some((slot, slot_buf)) = crate::api::video_ring::VIDEO_RING.claim() else {
        return;
    };
    if rgba.len() > slot_buf.len() {
        tracing::warn!(
            "video ring slot too small for preview ({} > {}); dropping",
            rgba.len(),
            slot_buf.len()
        );
        crate::api::video_ring::VIDEO_RING.release(slot);
        return;
    }
    slot_buf[..rgba.len()].copy_from_slice(&rgba);
    let len = rgba.len() as u32;
    crate::api::video_ring::VIDEO_RING.publish(slot);

    let addr = crate::api::video_ring::VIDEO_RING.slot_addr(slot);
    let ts_ns = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as i64)
        .unwrap_or(0);
    bus.push_video_frame(addr, len, width, height, slot, ts_ns)
        .await;
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
    let already_open = dc.ready_state() == RTCDataChannelState::Open;

    let bus = Arc::clone(&session.event_bus);
    let open_label = label.clone();
    dc.on_open(Box::new(move || {
        let bus = Arc::clone(&bus);
        let open_label = open_label.clone();
        Box::pin(async move {
            bus.push_event(WebRtcEvent::DataChannelStateChanged {
                label: open_label,
                state: "open".to_string(),
            })
            .await;
        })
    }));

    let bus = Arc::clone(&session.event_bus);
    let close_label = label.clone();
    dc.on_close(Box::new(move || {
        let bus = Arc::clone(&bus);
        let close_label = close_label.clone();
        Box::pin(async move {
            bus.push_event(WebRtcEvent::DataChannelStateChanged {
                label: close_label,
                state: "closed".to_string(),
            })
            .await;
        })
    }));

    let bus = Arc::clone(&session.event_bus);
    let msg_label = label.clone();
    let msg_connection_id = session.connection_id.clone();
    dc.on_message(Box::new(move |msg| {
        let bus = Arc::clone(&bus);
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
                        } else if let Some(input_msg) =
                            crate::api::input_inject::parse_input_message(text)
                        {
                            crate::api::input_inject::handle_input_message(
                                &msg_connection_id,
                                input_msg,
                            )
                            .await;
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
                            bus.push_event(event).await;
                        } else {
                            bus.push_event(WebRtcEvent::ControlMessage {
                                message: text.to_string(),
                            })
                            .await;
                        }
                    } else if msg_label == "file_transfer"
                        && crate::api::file_transfer::handle_file_message(
                            msg_connection_id.clone(),
                            text.to_string(),
                        )
                        .await
                        .is_err()
                    {
                        tracing::warn!("file transfer control message handling failed");
                    }
                }
            } else if msg_label == "file_transfer"
                && crate::api::file_transfer::handle_file_chunk(
                    msg_connection_id.clone(),
                    msg.data.to_vec(),
                )
                .await
                .is_err()
            {
                tracing::warn!("file transfer chunk handling failed");
            }
        })
    }));

    if label == "file_transfer" {
        let bus = Arc::clone(&session.event_bus);
        dc.on_buffered_amount_low(Box::new(move || {
            let bus = Arc::clone(&bus);
            Box::pin(async move {
                bus.push_event(WebRtcEvent::FileBufferedAmountLow).await;
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

    if already_open {
        session
            .event_bus
            .push_event(WebRtcEvent::DataChannelStateChanged {
                label,
                state: "open".to_string(),
            })
            .await;
    }
}

pub(crate) async fn get_session(connection_id: &str) -> anyhow::Result<Arc<WebRtcSession>> {
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
        event_bus: Arc::new(EventBus::new()),
        video_track: Arc::new(Mutex::new(None)),
        video_sender: Arc::new(Mutex::new(None)),
        audio_track: Arc::new(Mutex::new(None)),
        system_audio_track: Arc::new(Mutex::new(None)),
    });

    let bus = Arc::clone(&session.event_bus);
    pc.on_ice_candidate(Box::new(move |candidate| {
        let bus = Arc::clone(&bus);
        Box::pin(async move {
            if let Some(candidate) = candidate {
                if let Ok(candidate_init) = candidate.to_json() {
                    bus.push_event(WebRtcEvent::LocalIceCandidate {
                        candidate: IceCandidateDto {
                            candidate: candidate_init.candidate,
                            sdp_mid: candidate_init.sdp_mid,
                            sdp_mline_index: candidate_init.sdp_mline_index,
                        },
                    })
                    .await;
                }
            }
        })
    }));

    let bus = Arc::clone(&session.event_bus);
    pc.on_peer_connection_state_change(Box::new(move |state| {
        let bus = Arc::clone(&bus);
        Box::pin(async move {
            bus.push_event(WebRtcEvent::ConnectionStateChanged {
                state: state_label(state),
            })
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

    let bus = Arc::clone(&session.event_bus);
    let pc_for_track = Arc::clone(&pc);
    pc.on_track(Box::new(move |track, _receiver, _transceiver| {
        let bus = Arc::clone(&bus);
        let pc = Arc::clone(&pc_for_track);
        Box::pin(async move {
            let codec = track.codec();
            let mime = codec.capability.mime_type.to_lowercase();
            if mime.contains("opus") || mime.starts_with("audio") {
                tracing::info!(
                    "received remote audio track: mime={}, ssrc={}",
                    mime,
                    track.ssrc()
                );
                crate::api::audio::spawn_remote_audio_playback(track);
                return;
            }
            if !mime.contains("h264") && !mime.contains("video") {
                return;
            }
            tracing::info!(
                "received remote video track: mime={}, ssrc={}",
                mime,
                track.ssrc()
            );
            tokio::spawn(decode_incoming_track(track, bus, pc));
        })
    }));

    upsert_connection(connection_id.clone(), Arc::clone(&pc)).await?;
    let mut sessions = SESSIONS.lock().await;
    sessions.insert(connection_id, session);

    Ok(())
}

/// Add the pre-negotiated outgoing audio track once. Idempotent so repeated
/// offers/answers (renegotiation, ICE restart) don't stack duplicate m-lines.
async fn ensure_local_audio_track(session: &Arc<WebRtcSession>) -> anyhow::Result<()> {
    let mut guard = session.audio_track.lock().await;
    if guard.is_some() {
        return Ok(());
    }
    let audio_track = Arc::new(TrackLocalStaticSample::new(
        RTCRtpCodecCapability {
            mime_type: MIME_TYPE_OPUS.to_owned(),
            clock_rate: 48000,
            channels: 2,
            sdp_fmtp_line: "minptime=10;useinbandfec=1".to_owned(),
            ..Default::default()
        },
        format!("voice-{}", session.connection_id),
        format!("voice-stream-{}", session.connection_id),
    ));
    session
        .pc
        .add_track(Arc::clone(&audio_track) as Arc<dyn TrackLocal + Send + Sync>)
        .await
        .context("failed to add pre-negotiated audio track")?;
    *guard = Some(audio_track);
    Ok(())
}

/// Second, independent audio m-line for system/desktop audio (see
/// `WebRtcSession::system_audio_track`). Pre-negotiated the same way and
/// for the same reason as the voice track above.
async fn ensure_local_system_audio_track(session: &Arc<WebRtcSession>) -> anyhow::Result<()> {
    let mut guard = session.system_audio_track.lock().await;
    if guard.is_some() {
        return Ok(());
    }
    let audio_track = Arc::new(TrackLocalStaticSample::new(
        RTCRtpCodecCapability {
            mime_type: MIME_TYPE_OPUS.to_owned(),
            clock_rate: 48000,
            channels: 2,
            sdp_fmtp_line: "minptime=10;useinbandfec=1".to_owned(),
            ..Default::default()
        },
        format!("system-audio-{}", session.connection_id),
        format!("system-audio-stream-{}", session.connection_id),
    ));
    session
        .pc
        .add_track(Arc::clone(&audio_track) as Arc<dyn TrackLocal + Send + Sync>)
        .await
        .context("failed to add pre-negotiated system audio track")?;
    *guard = Some(audio_track);
    Ok(())
}

pub async fn create_offer(connection_id: String) -> anyhow::Result<SessionDescriptionDto> {
    let session = get_session(&connection_id).await?;
    ensure_default_data_channels(&session).await?;

    {
        let mut video_guard = session.video_track.lock().await;
        if video_guard.is_none() {
            let video_track = Arc::new(TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: "video/H264".to_owned(),
                    clock_rate: 90000,
                    sdp_fmtp_line:
                        "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f"
                            .to_owned(),
                    ..Default::default()
                },
                format!("screen-{connection_id}"),
                format!("screen-stream-{connection_id}"),
            ));
            let sender = session
                .pc
                .add_track(video_track.clone() as Arc<dyn TrackLocal + Send + Sync>)
                .await
                .context("failed to add pre-negotiated video track")?;
            *video_guard = Some(video_track);
            *session.video_sender.lock().await = Some(sender);
        }
    }
    ensure_local_audio_track(&session).await?;
    ensure_local_system_audio_track(&session).await?;

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

pub async fn create_restart_offer(connection_id: String) -> anyhow::Result<SessionDescriptionDto> {
    let session = get_session(&connection_id).await?;

    let offer = session
        .pc
        .create_offer(Some(RTCOfferOptions {
            ice_restart: true,
            ..Default::default()
        }))
        .await
        .context("failed to create ICE restart offer")?;
    session
        .pc
        .set_local_description(offer)
        .await
        .context("failed to set local ICE restart offer description")?;

    let local = if let Some(local) = session.pc.pending_local_description().await {
        local
    } else {
        session
            .pc
            .current_local_description()
            .await
            .ok_or_else(|| anyhow::anyhow!("missing local ICE restart offer description"))?
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
    let audio_mline_count = remote_offer
        .sdp
        .lines()
        .filter(|line| line.starts_with("m=audio"))
        .count();
    session
        .pc
        .set_remote_description(RTCSessionDescription::offer(remote_offer.sdp)?)
        .await
        .context("failed to set remote offer description")?;

    // Voice is bidirectional: attach our own track to the offered audio
    // m-line so the answer comes back sendrecv. Skipped for peers that
    // don't offer audio (older clients). `add_track` fills transceivers in
    // the same order the offer declared them, so these two calls must stay
    // in the same order `create_offer` adds them (voice, then system audio).
    if audio_mline_count >= 1 {
        ensure_local_audio_track(&session).await?;
    }
    if audio_mline_count >= 2 {
        ensure_local_system_audio_track(&session).await?;
    }

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
    // Polled every 100ms by the Flutter event loop; must never block waiting
    // for the channel — before the connection is established that would stall
    // event draining (and with it trickle ICE) for the full wait window.
    let channel = session.file_channel.lock().await.clone();
    match channel {
        Some(channel) => Ok(channel.buffered_amount().await as u64),
        None => Ok(0),
    }
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

pub async fn create_file_channel(connection_id: String) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    ensure_data_channel(&session, "file_transfer").await?;
    Ok(())
}

pub async fn wait_for_file_channel_ready(connection_id: String) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let _ = wait_for_named_data_channel(&session, "file_transfer").await?;
    Ok(())
}

pub async fn drain_events(connection_id: String) -> anyhow::Result<Vec<WebRtcEvent>> {
    let session = get_session(&connection_id).await?;
    let mut events = session.event_bus.buffer.lock().await;
    Ok(std::mem::take(&mut *events))
}

#[flutter_rust_bridge::frb]
pub async fn subscribe_event_stream(
    connection_id: String,
    sink: StreamSink<WebRtcEvent>,
) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    let buffered = {
        let mut guard = session.event_bus.buffer.lock().await;
        std::mem::take(&mut *guard)
    };
    for event in buffered {
        let _ = sink.add(event);
    }
    *session.event_bus.event_sink.lock().await = Some(sink);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn subscribe_video_stream(
    connection_id: String,
    sink: StreamSink<RawVideoFrame>,
) -> anyhow::Result<()> {
    let session = get_session(&connection_id).await?;
    *session.event_bus.video_sink.lock().await = Some(sink);
    Ok(())
}

pub async fn close_session(connection_id: String) -> anyhow::Result<()> {
    crate::api::audio::stop_capture_for_connection(&connection_id);
    #[cfg(target_os = "linux")]
    crate::api::desktop_audio::stop_capture_for_connection(&connection_id);

    let session = {
        let mut sessions = SESSIONS.lock().await;
        sessions.remove(&connection_id)
    };

    if let Some(session) = session {
        *session.event_bus.event_sink.lock().await = None;
        *session.event_bus.video_sink.lock().await = None;
        let _ = session.pc.close().await;
    }

    remove_connection(&connection_id).await;

    Ok(())
}

async fn decode_incoming_track(
    track: Arc<TrackRemote>,
    bus: Arc<EventBus>,
    pc: Arc<RTCPeerConnection>,
) {
    // Prefer the GStreamer + NVDEC path when nvh264dec + cuda postproc are
    // available. Single-digit ms transit instead of openh264's ~300 ms.
    #[cfg(feature = "gstreamer")]
    {
        if super::screen_decode_gst::is_available() {
            match super::screen_decode_gst::run_decode_pipeline(
                track.clone(),
                bus.clone(),
                pc.clone(),
            )
            .await
            {
                Ok(()) => return,
                Err(e) => {
                    tracing::warn!(
                        "GStreamer NVDEC decode failed during setup, falling back to openh264: {e:#}"
                    );
                }
            }
        }
    }

    let mut decoder = match openh264::decoder::Decoder::new() {
        Ok(d) => d,
        Err(e) => {
            tracing::error!("failed to create H.264 decoder: {e}");
            return;
        }
    };

    // 128 packets ≈ 250 ms at 5 Mbps — bounds how long a loss gap can stall
    // frame delivery. 512 held frames back for over a second under loss.
    let mut sample_builder =
        media::io::sample_builder::SampleBuilder::new(128, H264Packet::default(), 90000);

    let media_ssrc = track.ssrc();

    // ─── Receiver-side stats (2 s window, mirrors the sender's reporter) ──
    let session_id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let mut jsonl = open_recv_stats_jsonl();
    let mut window_started = Instant::now();
    let mut rtp_packets = 0u64;
    let mut samples_total = 0u64;
    let mut samples_empty = 0u64;
    let mut decoded = 0u64;
    let mut decode_errors = 0u64;
    let mut decode_sum_us = 0u64;
    let mut decode_max_us = 0u64;
    let mut push_sum_us = 0u64;
    let mut push_max_us = 0u64;

    loop {
        let (rtp_packet, _attr) = match track.read_rtp().await {
            Ok(pair) => pair,
            Err(e) => {
                tracing::info!("remote video track read ended: {e}");
                break;
            }
        };
        rtp_packets += 1;

        sample_builder.push(rtp_packet);

        while let Some(sample) = sample_builder.pop() {
            samples_total += 1;
            if sample.data.is_empty() {
                samples_empty += 1;
                continue;
            }
            let dec_started = Instant::now();
            match decoder.decode(&sample.data) {
                Ok(Some(yuv_frame)) => {
                    let (uv_w, uv_h) = yuv_frame.dimensions_uv();
                    let width = uv_w * 2;
                    let height = uv_h * 2;
                    let needed = width * height * 4;

                    let mut rgba = vec![0u8; needed];
                    yuv_frame.write_rgba8(&mut rgba);

                    let dec_us = dec_started.elapsed().as_micros() as u64;
                    decode_sum_us += dec_us;
                    if dec_us > decode_max_us {
                        decode_max_us = dec_us;
                    }
                    decoded += 1;

                    // Render through VIDEO_TEXTURE, exactly like the GStreamer
                    // NVDEC path. The responder UI renders TextureVideoView
                    // (which reads VIDEO_TEXTURE) unconditionally, so software-
                    // decoded frames MUST land here — writing them to the video
                    // ring instead left the texture black on any non-NVIDIA peer.
                    // The len==0 sentinel through the bus flips the responder's
                    // "remote video present" gate and carries the source dims.
                    let push_started = Instant::now();
                    crate::api::video_texture::VIDEO_TEXTURE.publish_owned_rgba(
                        rgba,
                        width as u32,
                        height as u32,
                    );
                    bus.push_video_frame(0, 0, width as u32, height as u32, u32::MAX, 0)
                        .await;
                    let push_us = push_started.elapsed().as_micros() as u64;
                    push_sum_us += push_us;
                    if push_us > push_max_us {
                        push_max_us = push_us;
                    }
                }
                Ok(None) => {}
                Err(e) => {
                    decode_errors += 1;
                    tracing::warn!("H.264 decode error: {e}, requesting keyframe");
                    let pli =
                        rtcp::payload_feedbacks::picture_loss_indication::PictureLossIndication {
                            sender_ssrc: 0,
                            media_ssrc,
                        };
                    let _ = pc.write_rtcp(&[Box::new(pli)]).await;
                }
            }
        }

        // 2 s window flush. Sits inside the loop because the receiver path
        // has no separate reporter task — the decode loop is the natural
        // pacer, and at any non-pathological frame rate we tick through here
        // many times per second.
        let elapsed = window_started.elapsed();
        if elapsed >= Duration::from_secs(2) {
            let secs = elapsed.as_secs_f64();
            let dec_avg = if decoded > 0 { decode_sum_us / decoded } else { 0 };
            let push_avg = if decoded > 0 { push_sum_us / decoded } else { 0 };
            let fps = decoded as f64 / secs;
            tracing::info!(
                target: "relink::recv_stats",
                "2s recv: rtp={} samples={} (empty={}) decoded={} ({:.1} fps) decode {{avg={}µs max={}µs}} push {{avg={}µs max={}µs}} errs={}",
                rtp_packets,
                samples_total,
                samples_empty,
                decoded,
                fps,
                dec_avg,
                decode_max_us,
                push_avg,
                push_max_us,
                decode_errors,
            );
            if let Some(f) = jsonl.as_mut() {
                let ts_ms = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_millis() as u64)
                    .unwrap_or(0);
                let row = serde_json::json!({
                    "ts_ms": ts_ms,
                    "session_id": session_id,
                    "window_secs": 2,
                    "side": "recv",
                    "rtp_packets": rtp_packets,
                    "samples_total": samples_total,
                    "samples_empty": samples_empty,
                    "decoded": decoded,
                    "decode_errors": decode_errors,
                    "decoded_fps": fps,
                    "decode_us":  {"avg": dec_avg,  "max": decode_max_us},
                    "push_us":    {"avg": push_avg, "max": push_max_us},
                });
                if let Err(e) = writeln!(f, "{}", row).and_then(|()| f.flush()) {
                    tracing::warn!("recv_stats: JSONL write failed, disabling: {e}");
                    jsonl = None;
                }
            }
            window_started = Instant::now();
            rtp_packets = 0;
            samples_total = 0;
            samples_empty = 0;
            decoded = 0;
            decode_errors = 0;
            decode_sum_us = 0;
            decode_max_us = 0;
            push_sum_us = 0;
            push_max_us = 0;
        }
    }
}

fn recv_stats_jsonl_path() -> PathBuf {
    if let Ok(p) = std::env::var("RELINK_STATS_JSONL") {
        return PathBuf::from(p);
    }
    let base = std::env::var("XDG_CACHE_HOME")
        .ok()
        .map(PathBuf::from)
        .or_else(|| std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("relink").join("stage_stats.jsonl")
}

fn open_recv_stats_jsonl() -> Option<std::fs::File> {
    let path = recv_stats_jsonl_path();
    if let Some(parent) = path.parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            tracing::warn!("recv_stats: could not create {}: {e}", parent.display());
            return None;
        }
    }
    match OpenOptions::new().create(true).append(true).open(&path) {
        Ok(f) => {
            tracing::info!("recv_stats: appending JSONL to {}", path.display());
            Some(f)
        }
        Err(e) => {
            tracing::warn!("recv_stats: could not open {}: {e}", path.display());
            None
        }
    }
}
