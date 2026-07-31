use std::fs::OpenOptions;
use std::io::{Cursor, Write};
use std::os::fd::AsRawFd;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context as _};
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_app as gst_app;
use gstreamer_video as gst_video;
use once_cell::sync::Lazy;
use webrtc::rtp_transceiver::rtp_sender::RTCRtpSender;
use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;

use super::screen_capture::{
    CaptureConfigDto, CaptureHandle, CaptureSourceDto, EncodeOutput, QualityTier, CAPTURE_SESSIONS,
    TIERS,
};
use super::webrtc::{push_preview_frame, EventBus};

// ─── Per-stage instrumentation ──────────────────────────────────────────────
// All four timing points feed a single global stats struct of lock-free atomic
// counters. A tokio task drains and logs every 2 s so we can see which stage
// owns the latency without paying any Mutex cost on the hot paths.

#[derive(Default)]
struct StageStats {
    count: AtomicU64,
    sum_us: AtomicU64,
    max_us: AtomicU64,
}

impl StageStats {
    fn record(&self, dur_us: u64) {
        self.count.fetch_add(1, Ordering::Relaxed);
        self.sum_us.fetch_add(dur_us, Ordering::Relaxed);
        self.max_us.fetch_max(dur_us, Ordering::Relaxed);
    }

    /// Atomically swap-out the window and return (count, avg_us, max_us).
    fn take(&self) -> (u64, u64, u64) {
        let count = self.count.swap(0, Ordering::Relaxed);
        let sum = self.sum_us.swap(0, Ordering::Relaxed);
        let max = self.max_us.swap(0, Ordering::Relaxed);
        let avg = if count == 0 { 0 } else { sum / count };
        (count, avg, max)
    }
}

#[derive(Default)]
struct PipelineStats {
    /// PipeWire `process` callback: dequeue + slice copy + try_send.
    pw_capture_us: StageStats,
    /// Frames dropped because the bridge channel was full when try_send fired.
    pw_dropped: AtomicU64,
    /// Time spent inside `appsrc.push_buffer()` (called from the PipeWire
    /// process callback). With a leaky appsrc queue this should stay in the
    /// tens of µs; higher means appsrc-side lock contention.
    bridge_push_us: StageStats,
    /// End-to-end pipeline transit, measured as
    /// `appsink.current_running_time - buffer.pts` for each NAL out. Covers
    /// queue + conversion + encoder.
    gst_pipeline_us: StageStats,
    /// `track.write_sample` duration. High values point at the WebRTC writer
    /// or the SCTP/DTLS transport, not the encode path.
    write_sample_us: StageStats,
    /// Encoded bytes in the current window — converts to outbound bitrate.
    nal_bytes: AtomicU64,
}

static PIPELINE_STATS: Lazy<PipelineStats> = Lazy::new(PipelineStats::default);

/// Path the reporter appends one JSON row per window to. Override with
/// `RELINK_STATS_JSONL=<path>`. Defaults to
/// `$XDG_CACHE_HOME/relink/stage_stats.jsonl` (or `$HOME/.cache/...`).
fn stats_jsonl_path() -> PathBuf {
    if let Ok(p) = std::env::var("RELINK_STATS_JSONL") {
        return PathBuf::from(p);
    }
    let base = std::env::var("XDG_CACHE_HOME")
        .ok()
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var("HOME")
                .ok()
                .map(|h| PathBuf::from(h).join(".cache"))
        })
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("relink").join("stage_stats.jsonl")
}

fn open_stats_jsonl() -> Option<std::fs::File> {
    let path = stats_jsonl_path();
    if let Some(parent) = path.parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            tracing::warn!("stage_stats: could not create {}: {e}", parent.display());
            return None;
        }
    }
    match OpenOptions::new().create(true).append(true).open(&path) {
        Ok(f) => {
            tracing::info!("stage_stats: appending JSONL to {}", path.display());
            Some(f)
        }
        Err(e) => {
            tracing::warn!("stage_stats: could not open {}: {e}", path.display());
            None
        }
    }
}

async fn run_stats_reporter(mut cancel_rx: tokio::sync::watch::Receiver<bool>) {
    let mut ticker = tokio::time::interval(Duration::from_secs(2));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    ticker.tick().await; // burn the immediate first tick
    let mut jsonl = open_stats_jsonl();
    // Per-process session id so multiple runs sharing the same JSONL file
    // can still be told apart. Just the millisecond timestamp at startup.
    let session_id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    loop {
        tokio::select! {
            _ = cancel_rx.changed() => break,
            _ = ticker.tick() => {
                let pw = PIPELINE_STATS.pw_capture_us.take();
                let drops = PIPELINE_STATS.pw_dropped.swap(0, Ordering::Relaxed);
                let br = PIPELINE_STATS.bridge_push_us.take();
                let gst = PIPELINE_STATS.gst_pipeline_us.take();
                let ws = PIPELINE_STATS.write_sample_us.take();
                let bytes = PIPELINE_STATS.nal_bytes.swap(0, Ordering::Relaxed);
                let mbps = (bytes as f64) * 8.0 / 1_000_000.0 / 2.0;
                tracing::info!(
                    target: "relink::stage_stats",
                    "2s: pw_capture {{n={} avg={}µs max={}µs drops={}}} | bridge_push {{n={} avg={}µs max={}µs}} | gst_pipeline {{n={} avg={}µs max={}µs}} | write_sample {{n={} avg={}µs max={}µs}} | out={:.2} Mbps",
                    pw.0, pw.1, pw.2, drops,
                    br.0, br.1, br.2,
                    gst.0, gst.1, gst.2,
                    ws.0, ws.1, ws.2,
                    mbps,
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
                        "pw_capture":   { "n": pw.0,  "avg_us": pw.1,  "max_us": pw.2, "drops": drops },
                        "bridge_push":  { "n": br.0,  "avg_us": br.1,  "max_us": br.2 },
                        "gst_pipeline": { "n": gst.0, "avg_us": gst.1, "max_us": gst.2 },
                        "write_sample": { "n": ws.0,  "avg_us": ws.1,  "max_us": ws.2 },
                        "out_mbps": mbps,
                    });
                    if let Err(e) = writeln!(f, "{}", row).and_then(|()| f.flush()) {
                        tracing::warn!("stage_stats: JSONL write failed, disabling: {e}");
                        jsonl = None;
                    }
                }
            }
        }
    }
}

// ─── Runtime detection ──────────────────────────────────────────────────────

static GST_INIT: std::sync::Once = std::sync::Once::new();
static GST_INIT_OK: AtomicBool = AtomicBool::new(false);

fn ensure_gst_init() -> bool {
    GST_INIT.call_once(|| {
        if gst::init().is_ok() {
            GST_INIT_OK.store(true, Ordering::SeqCst);
        }
    });
    GST_INIT_OK.load(Ordering::SeqCst)
}

pub(crate) fn is_available() -> bool {
    let gst_ok = ensure_gst_init();
    if !gst_ok {
        tracing::info!("GStreamer: init failed");
        return false;
    }
    let has_encoder = gst::ElementFactory::make("vah264enc").build().is_ok()
        || gst::ElementFactory::make("nvh264enc").build().is_ok()
        || gst::ElementFactory::make("x264enc").build().is_ok();
    let is_wayland = std::env::var("WAYLAND_DISPLAY").is_ok()
        || std::env::var("XDG_SESSION_TYPE").ok().as_deref() == Some("wayland");
    let available = has_encoder && is_wayland;
    tracing::info!(
        "GStreamer+PipeWire: encoder={has_encoder}, wayland={is_wayland}, available={available}"
    );
    available
}

pub(crate) fn list_sources() -> Vec<CaptureSourceDto> {
    vec![CaptureSourceDto {
        id: "portal:default".into(),
        name: "Screen (system picker)".into(),
        kind: "portal".into(),
        width: 0,
        height: 0,
    }]
}

// ─── Portal session ─────────────────────────────────────────────────────────

struct PortalSession {
    node_id: u32,
    fd: std::os::fd::OwnedFd,
    _session: ashpd::desktop::Session<ashpd::desktop::screencast::Screencast>,
}

async fn acquire_portal() -> anyhow::Result<PortalSession> {
    use ashpd::desktop::screencast::{CursorMode, Screencast, SelectSourcesOptions, SourceType};

    let proxy = Screencast::new().await.context("ScreenCast proxy")?;

    let session = proxy
        .create_session(Default::default())
        .await
        .context("create session")?;

    proxy
        .select_sources(
            &session,
            SelectSourcesOptions::default()
                .set_cursor_mode(CursorMode::Embedded)
                .set_sources(SourceType::Monitor | SourceType::Window)
                .set_multiple(false),
        )
        .await
        .context("select sources")?;

    let response = proxy
        .start(&session, None, Default::default())
        .await
        .context("portal start")?
        .response()
        .context("portal response")?;

    let streams = response.streams();
    let stream = streams
        .first()
        .ok_or_else(|| anyhow::anyhow!("no streams returned from portal"))?;

    let node_id = stream.pipe_wire_node_id();

    let fd = proxy
        .open_pipe_wire_remote(
            &session,
            ashpd::desktop::screencast::OpenPipeWireRemoteOptions::default(),
        )
        .await
        .context("open PipeWire remote")?;

    Ok(PortalSession {
        node_id,
        fd,
        _session: session,
    })
}

// ─── Encoder selection ──────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy)]
enum EncoderKind {
    VaH264,
    NvH264,
    X264,
}

fn select_encoder() -> anyhow::Result<EncoderKind> {
    if gst::ElementFactory::make("vah264enc").build().is_ok() {
        return Ok(EncoderKind::VaH264);
    }
    if gst::ElementFactory::make("nvh264enc").build().is_ok() {
        return Ok(EncoderKind::NvH264);
    }
    if gst::ElementFactory::make("x264enc").build().is_ok() {
        return Ok(EncoderKind::X264);
    }
    bail!("no H.264 encoder available (tried vah264enc, nvh264enc, x264enc)")
}

// ─── PipeWire direct capture ────────────────────────────────────────────────
// Bypasses GStreamer's pipewiresrc which can't handle compositor DMA-BUF
// renegotiation on PipeWire 1.x. We connect directly via pipewire-rs with
// SHM-only format params. The `process` callback pushes frames straight into
// the pipeline's appsrc (published via an `OnceLock` once the pipeline is
// Playing); appsrc's own leaky queue replaces the old bridge thread + channel.

#[derive(Debug, Clone)]
struct PwNegotiatedFormat {
    gst_format: String,
    width: u32,
    height: u32,
}

struct PwCapture {
    quit_tx: pipewire::channel::Sender<()>,
    _thread: std::thread::JoinHandle<()>,
}

impl PwCapture {
    fn start(
        node_id: u32,
        target_w: u32,
        target_h: u32,
        target_fps: u32,
        appsrc_slot: Arc<std::sync::OnceLock<gst_app::AppSrc>>,
    ) -> anyhow::Result<(Self, PwNegotiatedFormat)> {
        let (format_tx, format_rx) =
            std::sync::mpsc::sync_channel::<anyhow::Result<PwNegotiatedFormat>>(1);
        let (quit_tx, quit_rx) = pipewire::channel::channel::<()>();

        let thread = std::thread::Builder::new()
            .name("relink-pw-capture".into())
            .spawn(move || {
                if let Err(e) = pw_capture_thread(
                    node_id,
                    target_w,
                    target_h,
                    target_fps,
                    format_tx,
                    appsrc_slot,
                    quit_rx,
                ) {
                    tracing::error!("PipeWire capture thread failed: {e:#}");
                }
            })
            .context("spawn PipeWire capture thread")?;

        let format = format_rx
            .recv_timeout(Duration::from_secs(10))
            .map_err(|_| anyhow::anyhow!("PipeWire format negotiation timed out"))??;

        Ok((
            Self {
                quit_tx,
                _thread: thread,
            },
            format,
        ))
    }
}

impl Drop for PwCapture {
    fn drop(&mut self) {
        let _ = self.quit_tx.send(());
    }
}

fn spa_video_format_to_gst(
    format: pipewire::spa::param::video::VideoFormat,
) -> Option<&'static str> {
    use pipewire::spa::param::video::VideoFormat;
    match format {
        VideoFormat::BGRx => Some("BGRx"),
        VideoFormat::BGRA => Some("BGRA"),
        VideoFormat::RGBx => Some("RGBx"),
        VideoFormat::RGBA => Some("RGBA"),
        VideoFormat::NV12 => Some("NV12"),
        VideoFormat::I420 => Some("I420"),
        VideoFormat::YUY2 => Some("YUY2"),
        VideoFormat::RGB => Some("RGB"),
        VideoFormat::BGR => Some("BGR"),
        _ => None,
    }
}

#[allow(clippy::too_many_arguments)]
fn pw_capture_thread(
    node_id: u32,
    target_w: u32,
    target_h: u32,
    target_fps: u32,
    format_tx: std::sync::mpsc::SyncSender<anyhow::Result<PwNegotiatedFormat>>,
    appsrc_slot: Arc<std::sync::OnceLock<gst_app::AppSrc>>,
    quit_rx: pipewire::channel::Receiver<()>,
) -> anyhow::Result<()> {
    use pipewire::{
        context::ContextRc,
        keys::{MEDIA_CATEGORY, MEDIA_TYPE},
        main_loop::MainLoopRc,
        spa::{
            param::{
                format::{FormatProperties, MediaSubtype, MediaType},
                format_utils,
                video::VideoFormat,
                ParamType,
            },
            pod::{self, serialize::PodSerializer, Pod, Value},
            utils::{Direction, Fraction, Rectangle, SpaTypes},
        },
        stream::{StreamFlags, StreamRc},
    };

    pipewire::init();

    let main_loop = MainLoopRc::new(None).map_err(|e| anyhow::anyhow!("MainLoop::new: {e}"))?;
    let context =
        ContextRc::new(&main_loop, None).map_err(|e| anyhow::anyhow!("Context::new: {e}"))?;
    let core = context
        .connect_rc(None)
        .map_err(|e| anyhow::anyhow!("connect: {e}"))?;

    let _quit_source = quit_rx.attach(main_loop.loop_(), {
        let main_loop = main_loop.clone();
        move |_| {
            main_loop.quit();
        }
    });

    let stream = StreamRc::new(
        core,
        "relink-capture",
        pipewire::properties::properties! {
            *MEDIA_TYPE => "Video",
            *MEDIA_CATEGORY => "Capture",
        },
    )
    .map_err(|e| anyhow::anyhow!("Stream::new: {e}"))?;

    struct UserData {
        format_tx: Option<std::sync::mpsc::SyncSender<anyhow::Result<PwNegotiatedFormat>>>,
        /// Filled by `start_capture_gst` once the encode pipeline is Playing.
        /// Frames arriving before that are shed here.
        appsrc_slot: Arc<std::sync::OnceLock<gst_app::AppSrc>>,
        format: Option<PwNegotiatedFormat>,
        /// Drift-free throttle: accept a frame once `now >= next_frame_due`,
        /// then advance the deadline on the ideal grid. Comparing against a
        /// fixed grid (rather than `last_frame_at + interval`) avoids the
        /// beat-frequency effect where a 60 Hz compositor stream gated by an
        /// elapsed-time check lands at ~24 fps instead of the target rate.
        next_frame_due: std::time::Instant,
        frame_interval: Duration,
        // Drop instrumentation: rolling 1s window.
        window_started_at: std::time::Instant,
        frames_sent: u64,
        frames_dropped: u64,
    }

    let now0 = std::time::Instant::now();
    let user_data = UserData {
        format_tx: Some(format_tx),
        appsrc_slot,
        format: None,
        next_frame_due: now0,
        frame_interval: Duration::from_nanos(1_000_000_000 / target_fps.clamp(1, 120) as u64),
        window_started_at: now0,
        frames_sent: 0,
        frames_dropped: 0,
    };

    let _listener = stream
        .add_local_listener_with_user_data(user_data)
        .param_changed(|_stream, user_data, id, param| {
            let Some(param) = param else { return };
            if id != ParamType::Format.as_raw() {
                return;
            }

            let (media_type, media_subtype) = match format_utils::parse_format(param) {
                Ok(v) => v,
                Err(_) => return,
            };
            if media_type != MediaType::Video || media_subtype != MediaSubtype::Raw {
                return;
            }

            let mut info = pipewire::spa::param::video::VideoInfoRaw::new();
            if info.parse(param).is_err() {
                tracing::warn!("PipeWire: failed to parse video format pod");
                return;
            }

            let gst_fmt = match spa_video_format_to_gst(info.format()) {
                Some(f) => f,
                None => {
                    tracing::warn!("PipeWire: unsupported video format {:?}", info.format());
                    return;
                }
            };

            let negotiated = PwNegotiatedFormat {
                gst_format: gst_fmt.to_string(),
                width: info.size().width,
                height: info.size().height,
            };

            tracing::info!(
                "PipeWire format: {} {}x{}",
                negotiated.gst_format,
                negotiated.width,
                negotiated.height
            );

            user_data.format = Some(negotiated.clone());

            if let Some(tx) = user_data.format_tx.take() {
                let _ = tx.send(Ok(negotiated));
            }
        })
        .process(|stream, user_data| {
            let cb_started_at = Instant::now();

            if user_data.format.is_none() {
                return;
            }

            let Some(mut buffer) = stream.dequeue_buffer() else {
                return;
            };

            let now = cb_started_at;
            if now < user_data.next_frame_due {
                return;
            }

            let datas = buffer.datas_mut();
            if datas.is_empty() {
                return;
            }

            let data = &mut datas[0];
            let chunk = data.chunk();
            let size = chunk.size() as usize;

            if let Some(slice) = data.data() {
                if slice.len() >= size && size > 0 {
                    match user_data.appsrc_slot.get() {
                        Some(appsrc) => {
                            let mut gst_buf = gst::Buffer::from_slice(slice[..size].to_vec());
                            // PTS = wall-clock ns since UNIX_EPOCH (appsrc has
                            // do_timestamp off); the appsink diffs against now
                            // for real pipeline transit latency.
                            let now_ns = SystemTime::now()
                                .duration_since(UNIX_EPOCH)
                                .map(|d| d.as_nanos() as u64)
                                .unwrap_or(0);
                            gst_buf
                                .make_mut()
                                .set_pts(gst::ClockTime::from_nseconds(now_ns));
                            let push_started = Instant::now();
                            if appsrc.push_buffer(gst_buf).is_ok() {
                                // Stay on the grid unless we've fallen more
                                // than one interval behind (compositor stall),
                                // then re-anchor to now instead of bursting.
                                let next =
                                    user_data.next_frame_due + user_data.frame_interval;
                                user_data.next_frame_due =
                                    if next < now { now } else { next };
                                user_data.frames_sent += 1;
                            } else {
                                user_data.frames_dropped += 1;
                                PIPELINE_STATS.pw_dropped.fetch_add(1, Ordering::Relaxed);
                            }
                            PIPELINE_STATS
                                .bridge_push_us
                                .record(push_started.elapsed().as_micros() as u64);
                        }
                        None => {
                            // Pipeline not up yet; shed the frame.
                            user_data.frames_dropped += 1;
                            PIPELINE_STATS.pw_dropped.fetch_add(1, Ordering::Relaxed);
                        }
                    }
                }
            }

            PIPELINE_STATS
                .pw_capture_us
                .record(cb_started_at.elapsed().as_micros() as u64);

            let window = now.duration_since(user_data.window_started_at);
            if window >= Duration::from_secs(1) {
                let sent = user_data.frames_sent;
                let dropped = user_data.frames_dropped;
                let total = sent + dropped;
                if total > 0 {
                    let secs = window.as_secs_f64();
                    let drop_pct = (dropped as f64 / total as f64) * 100.0;
                    if dropped > 0 {
                        tracing::warn!(
                            "PipeWire→appsrc: {:.1} fps in, {} sent, {} dropped ({:.1}%) — pipeline not ready or flushing",
                            total as f64 / secs,
                            sent,
                            dropped,
                            drop_pct
                        );
                    } else {
                        tracing::debug!(
                            "PipeWire→appsrc: {:.1} fps in, 0 drops",
                            total as f64 / secs
                        );
                    }
                }
                user_data.window_started_at = now;
                user_data.frames_sent = 0;
                user_data.frames_dropped = 0;
            }
        })
        .register()
        .map_err(|e| anyhow::anyhow!("listener register: {e}"))?;

    let obj = pod::object!(
        SpaTypes::ObjectParamFormat,
        ParamType::EnumFormat,
        pod::property!(FormatProperties::MediaType, Id, MediaType::Video),
        pod::property!(FormatProperties::MediaSubtype, Id, MediaSubtype::Raw),
        pod::property!(
            FormatProperties::VideoFormat,
            Choice,
            Enum,
            Id,
            VideoFormat::NV12,
            VideoFormat::I420,
            VideoFormat::BGRx,
            VideoFormat::BGRA,
            VideoFormat::RGBx,
            VideoFormat::RGBA,
        ),
        // Default to the tier's target dims (compositors that can downscale
        // honour it), but leave the max wide so portals that don't support
        // downscaling still negotiate at native res. Downscaling at native
        // res then happens in our pipeline's videoconvert/postproc stage.
        pod::property!(
            FormatProperties::VideoSize,
            Choice,
            Range,
            Rectangle,
            Rectangle {
                width: target_w,
                height: target_h
            },
            Rectangle {
                width: 1,
                height: 1
            },
            Rectangle {
                width: 7680,
                height: 4320
            }
        ),
        pod::property!(
            FormatProperties::VideoFramerate,
            Choice,
            Range,
            Fraction,
            Fraction {
                num: target_fps.clamp(1, 120),
                denom: 1
            },
            Fraction { num: 0, denom: 1 },
            Fraction { num: 120, denom: 1 }
        ),
    );

    let pod_bytes = PodSerializer::serialize(Cursor::new(Vec::new()), &Value::Object(obj))
        .map_err(|e| anyhow::anyhow!("SPA pod serialize: {e}"))?
        .0
        .into_inner();

    let mut params =
        [Pod::from_bytes(&pod_bytes).ok_or_else(|| anyhow::anyhow!("invalid SPA pod"))?];

    stream
        .connect(
            Direction::Input,
            Some(node_id),
            StreamFlags::AUTOCONNECT | StreamFlags::MAP_BUFFERS,
            &mut params,
        )
        .map_err(|e| anyhow::anyhow!("stream connect: {e}"))?;

    tracing::info!("PipeWire stream connected, entering mainloop");
    main_loop.run();
    tracing::info!("PipeWire capture thread ended");
    Ok(())
}

// ─── GStreamer encode pipeline ──────────────────────────────────────────────

pub(crate) struct GstPipeline {
    pipeline: gst::Pipeline,
    appsrc: gst_app::AppSrc,
    encoder: gst::Element,
    /// Caps shape the pre-encoder capsfilter was built with. Must match what
    /// the chosen conversion chain can actually produce, or update_caps() will
    /// break negotiation the moment a tier change demands GPU memory the
    /// chain can't supply.
    pre_enc_caps_kind: PreEncCaps,
    pre_enc_capsfilter: gst::Element,
    _bus_watch: Option<gst::bus::BusWatchGuard>,
}

#[derive(Debug, Clone, Copy)]
enum PreEncCaps {
    /// `video/x-raw` (system memory, format unconstrained, width/height range).
    /// Also used by the GL fallback chain, which ends in `gldownload` so the
    /// encoder sees the frame in system memory.
    Cpu,
    /// `video/x-raw(memory:VAMemory), format=NV12, …` — `vapostproc` output.
    VaMemory,
    /// `video/x-raw(memory:CUDAMemory), format=NV12, …` — CUDA postproc output.
    CudaMemory,
}

fn build_pre_enc_caps(kind: PreEncCaps, max_w: u32, max_h: u32) -> gst::Caps {
    let w = gst::IntRange::new(2, max_w as i32);
    let h = gst::IntRange::new(2, max_h as i32);
    match kind {
        PreEncCaps::VaMemory => gst::Caps::builder("video/x-raw")
            .features(["memory:VAMemory"])
            .field("format", "NV12")
            .field("width", w)
            .field("height", h)
            .build(),
        PreEncCaps::CudaMemory => gst::Caps::builder("video/x-raw")
            .features(["memory:CUDAMemory"])
            .field("format", "NV12")
            .field("width", w)
            .field("height", h)
            .build(),
        PreEncCaps::Cpu => gst::Caps::builder("video/x-raw")
            .field("width", w)
            .field("height", h)
            .build(),
    }
}

impl GstPipeline {
    fn set_bitrate(&self, kbps: u32) {
        self.encoder.set_property("bitrate", kbps);
    }

    fn force_keyframe(&self) {
        let event = gst_video::UpstreamForceKeyUnitEvent::builder()
            .all_headers(true)
            .build();
        self.encoder.send_event(event);
    }

    fn update_caps(&self, tier: &QualityTier) {
        let caps = build_pre_enc_caps(self.pre_enc_caps_kind, tier.max_w, tier.max_h);
        self.pre_enc_capsfilter.set_property("caps", &caps);
    }

    pub(crate) fn stop(&self) {
        let _ = self.appsrc.end_of_stream();
        let _ = self.pipeline.set_state(gst::State::Null);
    }
}

impl Drop for GstPipeline {
    fn drop(&mut self) {
        let _ = self.pipeline.set_state(gst::State::Null);
    }
}

fn build_encode_pipeline(
    pw_format: &PwNegotiatedFormat,
    tier: &QualityTier,
    encoder_kind: EncoderKind,
    want_preview: bool,
    nal_tx: tokio::sync::mpsc::Sender<EncodeOutput>,
    cancel_flag: Arc<AtomicBool>,
) -> anyhow::Result<GstPipeline> {
    let pipeline = gst::Pipeline::new();

    let src_caps = gst::Caps::builder("video/x-raw")
        .field("format", &pw_format.gst_format)
        .field("width", pw_format.width as i32)
        .field("height", pw_format.height as i32)
        .build();

    let appsrc = gst_app::AppSrc::builder()
        .caps(&src_caps)
        .format(gst::Format::Time)
        .is_live(true)
        // The PipeWire process callback stamps PTS with wall-clock ns so the
        // appsink can measure real transit latency. With do_timestamp=true the
        // running-time stamp ends up identical to whatever the sink reports.
        .do_timestamp(false)
        .build();
    // The PipeWire callback pushes directly into this appsrc; a small leaky
    // queue here sheds frames if downstream ever stalls (e.g. renegotiation)
    // so the realtime capture thread never blocks and memory stays bounded.
    appsrc.set_property("max-buffers", 4u64);
    appsrc.set_property_from_str("leaky-type", "downstream");

    let tee = gst::ElementFactory::make("tee").build().context("tee")?;

    pipeline
        .add_many([appsrc.upcast_ref::<gst::Element>(), &tee])
        .context("add appsrc+tee")?;
    appsrc.link(&tee).context("link appsrc→tee")?;

    // ─── Encode branch ───
    let enc_queue = gst::ElementFactory::make("queue")
        .property_from_str("leaky", "downstream")
        .property("max-size-buffers", 2u32)
        .property("max-size-bytes", 0u32)
        .property("max-size-time", 0u64)
        .build()
        .context("encode queue")?;

    // Pick the most efficient conversion chain the host can support:
    //   VA-API: vapostproc → CPU fallback
    //   NVENC:  cudaupload+cudaconvertscale  →  cudaupload+cudaconvert+cudascale
    //           →  glupload+glcolorscale (GL↔CUDA interop into nvh264enc)
    //           →  CPU videoconvert+videoscale
    //   x264:   CPU videoconvert+videoscale
    let try_cuda = || -> Option<Vec<gst::Element>> {
        let up = gst::ElementFactory::make("cudaupload").build().ok()?;
        if let Ok(cs) = gst::ElementFactory::make("cudaconvertscale").build() {
            return Some(vec![up, cs]);
        }
        let cc = gst::ElementFactory::make("cudaconvert").build().ok()?;
        let cs = gst::ElementFactory::make("cudascale").build().ok()?;
        Some(vec![up, cc, cs])
    };
    // GL fallback: opt-in via env var. On NVIDIA + Wayland the EGL context
    // negotiation is fragile (runtime not-negotiated errors after the
    // pipeline links cleanly) so we don't try it on every run by default.
    let try_gl = || -> Option<Vec<gst::Element>> {
        if std::env::var("RELINK_TRY_GL_POSTPROC").ok().as_deref() != Some("1") {
            return None;
        }
        let up = gst::ElementFactory::make("glupload").build().ok()?;
        let cs = gst::ElementFactory::make("glcolorscale").build().ok()?;
        let dl = gst::ElementFactory::make("gldownload").build().ok()?;
        let vc = gst::ElementFactory::make("videoconvert").build().ok()?;
        Some(vec![up, cs, dl, vc])
    };
    let cpu_chain = || -> anyhow::Result<Vec<gst::Element>> {
        let n_threads = std::thread::available_parallelism()
            .map(|n| n.get() as u32)
            .unwrap_or(4)
            .min(8);
        // Prefer the fused videoconvertscale (GStreamer 1.20+): one pass
        // through the pixels for both CSC and resize, with better cache use
        // than the split chain.
        if let Ok(fused) = gst::ElementFactory::make("videoconvertscale")
            .property("n-threads", n_threads)
            .build()
        {
            return Ok(vec![fused]);
        }
        // Split chain. SCALE FIRST so the expensive colorspace conversion
        // runs at the (smaller) target resolution rather than the source's.
        // Reversing this order avoids a 4× CPU cost when downscaling 4K
        // sources to 1080p.
        let vs = gst::ElementFactory::make("videoscale")
            .build()
            .context("videoscale")?;
        let vc = gst::ElementFactory::make("videoconvert")
            .property("n-threads", n_threads)
            .build()
            .context("videoconvert")?;
        Ok(vec![vs, vc])
    };

    let (conv_chain, pre_enc_caps_kind): (Vec<gst::Element>, PreEncCaps) = match encoder_kind {
        EncoderKind::VaH264 => match gst::ElementFactory::make("vapostproc").build() {
            Ok(vapp) => (vec![vapp], PreEncCaps::VaMemory),
            Err(e) => {
                tracing::warn!("vapostproc unavailable ({e}); falling back to CPU");
                (cpu_chain()?, PreEncCaps::Cpu)
            }
        },
        EncoderKind::NvH264 => {
            if let Some(chain) = try_cuda() {
                (chain, PreEncCaps::CudaMemory)
            } else if let Some(chain) = try_gl() {
                tracing::info!(
                    "CUDA postproc unavailable; using GL postproc (glupload+glcolorscale+gldownload, scale on GPU then CPU NV12 convert at target res)"
                );
                (chain, PreEncCaps::Cpu)
            } else {
                tracing::warn!(
                    "CUDA and GL postproc unavailable; falling back to CPU conversion (see `encode conversion:` line for the exact chain)"
                );
                (cpu_chain()?, PreEncCaps::Cpu)
            }
        }
        EncoderKind::X264 => (cpu_chain()?, PreEncCaps::Cpu),
    };

    let pre_enc_capsfilter = gst::ElementFactory::make("capsfilter")
        .property(
            "caps",
            build_pre_enc_caps(pre_enc_caps_kind, tier.max_w, tier.max_h),
        )
        .build()
        .context("pre-encoder capsfilter")?;
    tracing::info!(
        "encode conversion: {:?} via {}",
        pre_enc_caps_kind,
        conv_chain
            .iter()
            .map(|e| e
                .factory()
                .map(|f| f.name().to_string())
                .unwrap_or_default())
            .collect::<Vec<_>>()
            .join(" ! ")
    );

    let h264parse = gst::ElementFactory::make("h264parse")
        .property("config-interval", -1i32)
        .build()
        .context("h264parse")?;

    let post_enc_caps = gst::Caps::builder("video/x-h264")
        .field("stream-format", "byte-stream")
        .field("alignment", "au")
        .build();
    let post_enc_capsfilter = gst::ElementFactory::make("capsfilter")
        .property("caps", &post_enc_caps)
        .build()
        .context("post-encoder capsfilter")?;

    let nal_sink = gst_app::AppSink::builder()
        .sync(false)
        .drop(true)
        .max_buffers(2)
        .build();

    let (hw_chain, encoder_el) = match encoder_kind {
        EncoderKind::VaH264 => {
            let enc = gst::ElementFactory::make("vah264enc")
                .property_from_str("rate-control", "cbr")
                .property("bitrate", tier.bitrate_kbps)
                .property("key-int-max", tier.fps)
                .property("ref-frames", 1u32)
                .build()
                .context("vah264enc")?;
            (vec![enc.clone()], enc)
        }
        EncoderKind::NvH264 => {
            let enc = gst::ElementFactory::make("nvh264enc")
                .property("bitrate", tier.bitrate_kbps)
                .property("gop-size", tier.fps as i32)
                .property_from_str("preset", "p1")
                .property_from_str("tune", "ultra-low-latency")
                .property_from_str("rc-mode", "cbr")
                .property("zerolatency", true)
                .build()
                .context("nvh264enc")?;
            (vec![enc.clone()], enc)
        }
        EncoderKind::X264 => {
            let enc = gst::ElementFactory::make("x264enc")
                .property("bitrate", tier.bitrate_kbps)
                .property_from_str("speed-preset", "ultrafast")
                .property_from_str("tune", "zerolatency")
                .property("key-int-max", tier.fps)
                .property("bframes", 0u32)
                .property("byte-stream", true)
                .build()
                .context("x264enc")?;
            (vec![enc.clone()], enc)
        }
    };

    // Thread boundary between conversion and encoding: without it both run
    // serially on one streaming thread and their per-frame costs add up,
    // capping throughput on the CPU-conversion fallback path. Leaky so a slow
    // encoder sheds frames instead of adding latency.
    let enc_stage_queue = gst::ElementFactory::make("queue")
        .property_from_str("leaky", "downstream")
        .property("max-size-buffers", 1u32)
        .property("max-size-bytes", 0u32)
        .property("max-size-time", 0u64)
        .build()
        .context("encoder stage queue")?;

    let mut all_enc: Vec<gst::Element> = vec![enc_queue.clone()];
    all_enc.extend(conv_chain);
    all_enc.push(pre_enc_capsfilter.clone());
    all_enc.push(enc_stage_queue);
    all_enc.extend(hw_chain);
    all_enc.push(h264parse);
    all_enc.push(post_enc_capsfilter);
    all_enc.push(nal_sink.clone().upcast());

    for el in &all_enc {
        pipeline.add(el).context("add encode element")?;
    }
    tee.link(&enc_queue).context("link tee→enc_queue")?;
    for window in all_enc.windows(2) {
        window[0]
            .link(&window[1])
            .with_context(|| format!("link {}→{}", window[0].name(), window[1].name()))?;
    }

    let nal_tx_enc = nal_tx.clone();
    nal_sink.set_callbacks(
        gst_app::AppSinkCallbacks::builder()
            .new_sample(move |sink| {
                let sample = sink.pull_sample().map_err(|_| gst::FlowError::Eos)?;
                let buffer = sample.buffer().ok_or(gst::FlowError::Error)?;

                // End-to-end GStreamer transit. push_frame stamps PTS with
                // wall-clock ns since UNIX_EPOCH; we read it back here and
                // diff against current wall-clock to get true transit time.
                if let Some(pts) = buffer.pts() {
                    let now_ns = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .map(|d| d.as_nanos() as u64)
                        .unwrap_or(0);
                    let dur_us = now_ns.saturating_sub(pts.nseconds()) / 1000;
                    PIPELINE_STATS.gst_pipeline_us.record(dur_us);
                }

                let map = buffer.map_readable().map_err(|_| gst::FlowError::Error)?;
                let data = map.as_slice().to_vec();
                PIPELINE_STATS
                    .nal_bytes
                    .fetch_add(data.len() as u64, Ordering::Relaxed);

                let duration = buffer
                    .duration()
                    .map(|d| Duration::from_nanos(d.nseconds()))
                    .unwrap_or(Duration::from_millis(33));

                nal_tx_enc
                    .blocking_send(EncodeOutput::Nal { data, duration })
                    .map_err(|_| gst::FlowError::Eos)?;

                Ok(gst::FlowSuccess::Ok)
            })
            .build(),
    );

    // ─── Preview branch (optional) ───
    if want_preview {
        let preview_queue = gst::ElementFactory::make("queue")
            .property_from_str("leaky", "downstream")
            .property("max-size-buffers", 1u32)
            .property("max-size-bytes", 0u32)
            .property("max-size-time", 0u64)
            .build()
            .context("preview queue")?;

        let preview_w = ((tier.max_w / 2) & !1).max(2) as i32;
        let preview_h = ((tier.max_h / 2) & !1).max(2) as i32;
        let preview_caps = gst::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .field("width", preview_w)
            .field("height", preview_h)
            .build();

        let preview_chain: Vec<gst::Element> = {
            // A thumbnail doesn't need 60 fps; dropping to ≤10 fps BEFORE the
            // convert/scale keeps the preview branch off the CPU budget.
            let vr = gst::ElementFactory::make("videorate")
                .property("drop-only", true)
                .property("max-rate", 10i32)
                .build()
                .context("preview videorate")?;
            let vc = gst::ElementFactory::make("videoconvert")
                .build()
                .context("preview videoconvert")?;
            let vs = gst::ElementFactory::make("videoscale")
                .build()
                .context("preview videoscale")?;
            let cf = gst::ElementFactory::make("capsfilter")
                .property("caps", &preview_caps)
                .build()
                .context("preview capsfilter")?;
            vec![vr, vs, vc, cf]
        };

        let preview_sink = gst_app::AppSink::builder()
            .sync(false)
            .drop(true)
            .max_buffers(1)
            .build();

        let mut all_preview: Vec<gst::Element> = vec![preview_queue.clone()];
        all_preview.extend(preview_chain);
        all_preview.push(preview_sink.clone().upcast());

        for el in &all_preview {
            pipeline.add(el).context("add preview element")?;
        }
        tee.link(&preview_queue).context("link tee→preview_queue")?;
        for window in all_preview.windows(2) {
            window[0].link(&window[1]).with_context(|| {
                format!("link preview {}→{}", window[0].name(), window[1].name())
            })?;
        }

        let nal_tx_preview = nal_tx;
        preview_sink.set_callbacks(
            gst_app::AppSinkCallbacks::builder()
                .new_sample(move |sink| {
                    let sample = sink.pull_sample().map_err(|_| gst::FlowError::Eos)?;
                    let buffer = sample.buffer().ok_or(gst::FlowError::Error)?;
                    let map = buffer.map_readable().map_err(|_| gst::FlowError::Error)?;

                    let caps = sample.caps().ok_or(gst::FlowError::Error)?;
                    let structure = caps.structure(0).ok_or(gst::FlowError::Error)?;
                    let width = structure.get::<i32>("width").unwrap_or(0) as u32;
                    let height = structure.get::<i32>("height").unwrap_or(0) as u32;

                    if width > 0 && height > 0 {
                        let rgba = map.as_slice().to_vec();
                        let _ = nal_tx_preview.blocking_send(EncodeOutput::Preview {
                            rgba,
                            width,
                            height,
                        });
                    }

                    Ok(gst::FlowSuccess::Ok)
                })
                .build(),
        );
    }

    let bus_watch = pipeline.bus().and_then(|bus| {
        bus.add_watch(move |_, msg| {
            use gst::glib;
            match msg.view() {
                gst::MessageView::Error(err) => {
                    tracing::error!(
                        "GStreamer encode error: {} (debug: {:?})",
                        err.error(),
                        err.debug()
                    );
                    cancel_flag.store(true, Ordering::Relaxed);
                    glib::ControlFlow::Break
                }
                gst::MessageView::Eos(_) => {
                    tracing::info!("GStreamer encode pipeline EOS");
                    cancel_flag.store(true, Ordering::Relaxed);
                    glib::ControlFlow::Break
                }
                _ => glib::ControlFlow::Continue,
            }
        })
        .ok()
    });

    Ok(GstPipeline {
        pipeline,
        appsrc,
        encoder: encoder_el,
        pre_enc_caps_kind,
        pre_enc_capsfilter,
        _bus_watch: bus_watch,
    })
}

// ─── Pipeline entry point ───────────────────────────────────────────────────

pub(crate) async fn start_capture_gst(
    connection_id: String,
    config: CaptureConfigDto,
    local_preview: bool,
    video_track: Arc<TrackLocalStaticSample>,
    video_sender: Option<Arc<RTCRtpSender>>,
    preview_bus: Option<Arc<EventBus>>,
) -> anyhow::Result<()> {
    ensure_gst_init();

    let encoder_kind = select_encoder()?;
    tracing::info!("GStreamer encoder: {encoder_kind:?}");

    let portal = acquire_portal().await.context("portal acquisition")?;
    tracing::info!(
        "portal session acquired: node_id={}, fd={}",
        portal.node_id,
        portal.fd.as_raw_fd()
    );

    let tier = TIERS[0].clamped(&config);

    let appsrc_slot: Arc<std::sync::OnceLock<gst_app::AppSrc>> =
        Arc::new(std::sync::OnceLock::new());
    let (pw_capture, pw_format) = PwCapture::start(
        portal.node_id,
        tier.max_w,
        tier.max_h,
        tier.fps,
        Arc::clone(&appsrc_slot),
    )
    .context("PipeWire capture")?;

    tracing::info!(
        "PipeWire capture active: {} {}x{}",
        pw_format.gst_format,
        pw_format.width,
        pw_format.height
    );

    let cancel_flag = Arc::new(AtomicBool::new(false));
    let (cancel_tx, cancel_rx) = tokio::sync::watch::channel(false);
    let tier_idx = Arc::new(AtomicUsize::new(0));

    let (output_tx, output_rx) = tokio::sync::mpsc::channel::<EncodeOutput>(8);

    let gst_pipeline = build_encode_pipeline(
        &pw_format,
        &tier,
        encoder_kind,
        local_preview,
        output_tx,
        Arc::clone(&cancel_flag),
    )
    .context("build GStreamer encode pipeline")?;

    gst_pipeline
        .pipeline
        .set_state(gst::State::Playing)
        .map_err(|_| anyhow::anyhow!("encode pipeline failed to reach Playing state"))?;

    // Open the gate: from here the PipeWire process callback pushes frames
    // straight into the appsrc.
    let _ = appsrc_slot.set(gst_pipeline.appsrc.clone());

    tracing::info!(connection_id = %connection_id, "GStreamer encode pipeline started");

    let gst_pipeline = Arc::new(gst_pipeline);

    {
        let mut sessions = CAPTURE_SESSIONS.lock().await;
        sessions.insert(
            connection_id.clone(),
            CaptureHandle::new_gst(
                Arc::clone(&cancel_flag),
                cancel_tx,
                Arc::clone(&gst_pipeline),
            ),
        );
    }

    if let Some(sender) = video_sender {
        let gst_ref = Arc::clone(&gst_pipeline);
        tokio::spawn(adapt_quality_gst(
            sender,
            gst_ref,
            Arc::clone(&tier_idx),
            config,
            cancel_rx.clone(),
        ));
    }

    // Teardown watcher: owns the PipeWire capture and stops the pipeline when
    // the session is cancelled (stop_capture) or the bus watch flags a fatal
    // error. Frames flow PipeWire→appsrc directly; no bridge thread needed.
    let gst_ref = Arc::clone(&gst_pipeline);
    let cancel = Arc::clone(&cancel_flag);
    let mut cancel_watch = cancel_rx.clone();
    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = cancel_watch.changed() => break,
                _ = tokio::time::sleep(Duration::from_millis(500)) => {
                    if cancel.load(Ordering::Relaxed) {
                        break;
                    }
                }
            }
        }
        gst_ref.stop();
        drop(pw_capture);
        tracing::info!("PipeWire capture ended, encode pipeline stopped");
    });

    // Periodic stage-stats reporter (2 s window)
    tokio::spawn(run_stats_reporter(cancel_rx.clone()));

    // Output writer (instrumented inline so we can time track.write_sample)
    let cid = connection_id.clone();
    let _portal = portal;
    tokio::spawn(async move {
        write_outputs_instrumented(output_rx, video_track, preview_bus).await;
        let mut sessions = CAPTURE_SESSIONS.lock().await;
        sessions.remove(&cid);
        tracing::info!(connection_id = %cid, "GStreamer capture pipeline ended");
        drop(_portal);
    });

    Ok(())
}

async fn write_outputs_instrumented(
    mut output_rx: tokio::sync::mpsc::Receiver<EncodeOutput>,
    track: Arc<TrackLocalStaticSample>,
    preview_bus: Option<Arc<EventBus>>,
) {
    while let Some(output) = output_rx.recv().await {
        match output {
            EncodeOutput::Nal { data, duration } => {
                let sample = media::Sample {
                    data: data.into(),
                    duration,
                    ..Default::default()
                };
                let started_at = Instant::now();
                if let Err(e) = track.write_sample(&sample).await {
                    tracing::warn!("failed to write video sample: {e}");
                }
                PIPELINE_STATS
                    .write_sample_us
                    .record(started_at.elapsed().as_micros() as u64);
            }
            EncodeOutput::Preview {
                rgba,
                width,
                height,
            } => {
                if let Some(bus) = &preview_bus {
                    push_preview_frame(bus, rgba, width, height).await;
                }
            }
        }
    }
}

// ─── Quality adaptation with PLI forwarding ─────────────────────────────────

async fn adapt_quality_gst(
    sender: Arc<RTCRtpSender>,
    pipeline: Arc<GstPipeline>,
    tier_idx: Arc<AtomicUsize>,
    config: CaptureConfigDto,
    mut cancel_rx: tokio::sync::watch::Receiver<bool>,
) {
    let mut consecutive_bad = 0u32;
    let mut consecutive_good = 0u32;

    loop {
        let packets = tokio::select! {
            _ = cancel_rx.changed() => break,
            result = sender.read_rtcp() => match result {
                Ok((packets, _)) => packets,
                Err(e) => {
                    tracing::info!("GStreamer rtcp reader ended: {e}");
                    break;
                }
            },
        };

        let mut worst_loss: f64 = -1.0;
        let mut got_pli = false;

        for packet in &packets {
            if let Some(rr) = packet
                .as_any()
                .downcast_ref::<webrtc::rtcp::receiver_report::ReceiverReport>()
            {
                for report in &rr.reports {
                    worst_loss = worst_loss.max(report.fraction_lost as f64 / 256.0);
                }
            }
            if packet
                .as_any()
                .downcast_ref::<rtcp::payload_feedbacks::picture_loss_indication::PictureLossIndication>()
                .is_some()
            {
                got_pli = true;
            }
        }

        if got_pli {
            tracing::debug!("PLI received, forcing keyframe");
            pipeline.force_keyframe();
        }

        if worst_loss < 0.0 {
            continue;
        }

        let current = tier_idx.load(Ordering::Relaxed);
        let (next, bad, good) = super::screen_capture::step_tier(
            current,
            worst_loss,
            consecutive_bad,
            consecutive_good,
            TIERS.len(),
        );
        consecutive_bad = bad;
        consecutive_good = good;

        if next != current {
            tier_idx.store(next, Ordering::Relaxed);
            let t = TIERS[next].clamped(&config);
            pipeline.set_bitrate(t.bitrate_kbps);
            pipeline.update_caps(&t);
            if next > current {
                tracing::info!(
                    "quality down (loss {:.1}%): {}x{} @ {}fps {}kbps",
                    worst_loss * 100.0,
                    t.max_w,
                    t.max_h,
                    t.fps,
                    t.bitrate_kbps
                );
            } else {
                tracing::info!(
                    "quality up: {}x{} @ {}fps {}kbps",
                    t.max_w,
                    t.max_h,
                    t.fps,
                    t.bitrate_kbps
                );
            }
        }
    }
}
