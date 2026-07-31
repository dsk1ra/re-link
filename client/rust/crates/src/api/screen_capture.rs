use anyhow::Context;
use fast_image_resize::images::{Image, ImageRef};
use fast_image_resize::{FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};
use media::Sample;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use webrtc::rtp_transceiver::rtp_sender::RTCRtpSender;
use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
use xxhash_rust::xxh3::xxh3_64;
use yuv::{
    YuvChromaSubsampling, YuvConversionMode, YuvPlanarImageMut, YuvRange, YuvStandardMatrix,
};

use super::webrtc::{get_session, push_preview_frame, EventBus};

pub(crate) static CAPTURE_SESSIONS: Lazy<Mutex<HashMap<String, CaptureHandle>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub(crate) struct CaptureHandle {
    cancel_flag: Arc<AtomicBool>,
    cancel_tx: tokio::sync::watch::Sender<bool>,
    #[cfg(all(target_os = "linux", feature = "gstreamer"))]
    gst_pipeline: Option<Arc<super::screen_capture_gst::GstPipeline>>,
}

impl CaptureHandle {
    fn new(cancel_flag: Arc<AtomicBool>, cancel_tx: tokio::sync::watch::Sender<bool>) -> Self {
        Self {
            cancel_flag,
            cancel_tx,
            #[cfg(all(target_os = "linux", feature = "gstreamer"))]
            gst_pipeline: None,
        }
    }

    #[cfg(all(target_os = "linux", feature = "gstreamer"))]
    pub(crate) fn new_gst(
        cancel_flag: Arc<AtomicBool>,
        cancel_tx: tokio::sync::watch::Sender<bool>,
        pipeline: Arc<super::screen_capture_gst::GstPipeline>,
    ) -> Self {
        Self {
            cancel_flag,
            cancel_tx,
            gst_pipeline: Some(pipeline),
        }
    }
}

#[derive(Debug, Clone)]
pub struct CaptureSourceDto {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone)]
pub struct CaptureConfigDto {
    pub fps: u32,
    pub target_bitrate_kbps: u32,
}

// ─── Quality tier ladder ─────────────────────────────────────────────────────
// Network-adaptive: starts at tier 0 (capped by user config) and steps
// down/up based on RTCP receiver-report packet loss. 1080p/8000kbps is the
// absolute ceiling.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct QualityTier {
    pub(crate) max_w: u32,
    pub(crate) max_h: u32,
    pub(crate) fps: u32,
    pub(crate) bitrate_kbps: u32,
}

// Framerate-first ladder: fluid motion beats pixels for remote control, so
// congestion sheds resolution before it ever touches fps.
pub(crate) const TIERS: [QualityTier; 4] = [
    QualityTier {
        max_w: 1920,
        max_h: 1080,
        fps: 60,
        bitrate_kbps: 5000,
    },
    QualityTier {
        max_w: 1280,
        max_h: 720,
        fps: 60,
        bitrate_kbps: 3000,
    },
    QualityTier {
        max_w: 960,
        max_h: 540,
        fps: 60,
        bitrate_kbps: 1500,
    },
    QualityTier {
        max_w: 960,
        max_h: 540,
        fps: 30,
        bitrate_kbps: 800,
    },
];

impl QualityTier {
    /// Apply user-configured caps (fps and max bitrate) on top of the tier.
    pub(crate) fn clamped(mut self, config: &CaptureConfigDto) -> Self {
        self.fps = self.fps.min(config.fps.clamp(1, 60));
        self.bitrate_kbps = self.bitrate_kbps.min(config.target_bitrate_kbps.max(100));
        self
    }
}

const DEGRADE_LOSS: f64 = 0.05;
const UPGRADE_LOSS: f64 = 0.01;
const DEGRADE_AFTER: u32 = 2;
const UPGRADE_AFTER: u32 = 10;

/// Pure hysteresis step shared by both encoder backends (openh264 and
/// GStreamer): given the tier currently in use and one RTCP report's worst
/// loss fraction, decides whether to step the tier index down/up. Sustained
/// loss above 5% degrades after 2 bad reports; ~10 clean reports upgrade.
/// Kept free of I/O/logging so it's cheap to unit test.
pub(crate) fn step_tier(
    current: usize,
    worst_loss: f64,
    mut consecutive_bad: u32,
    mut consecutive_good: u32,
    tier_count: usize,
) -> (usize, u32, u32) {
    if worst_loss > DEGRADE_LOSS {
        consecutive_bad += 1;
        consecutive_good = 0;
    } else if worst_loss < UPGRADE_LOSS {
        consecutive_good += 1;
        consecutive_bad = 0;
    } else {
        consecutive_bad = 0;
        consecutive_good = 0;
    }

    if consecutive_bad >= DEGRADE_AFTER && current + 1 < tier_count {
        return (current + 1, 0, consecutive_good);
    }
    if consecutive_good >= UPGRADE_AFTER && current > 0 {
        return (current - 1, consecutive_bad, 0);
    }
    (current, consecutive_bad, consecutive_good)
}

#[cfg(test)]
mod quality_tier_tests {
    use super::step_tier;

    #[test]
    fn degrades_after_two_consecutive_bad_reports() {
        let (idx, bad, good) = step_tier(0, 0.10, 0, 0, 5);
        assert_eq!((idx, bad, good), (0, 1, 0));
        let (idx, bad, good) = step_tier(idx, 0.10, bad, good, 5);
        assert_eq!((idx, bad, good), (1, 0, 0));
    }

    #[test]
    fn upgrades_after_ten_consecutive_good_reports() {
        let mut idx = 1;
        let mut bad = 0;
        let mut good = 0;
        for _ in 0..9 {
            (idx, bad, good) = step_tier(idx, 0.0, bad, good, 5);
            assert_eq!(idx, 1, "should not upgrade before 10 clean reports");
        }
        (idx, bad, good) = step_tier(idx, 0.0, bad, good, 5);
        assert_eq!((idx, bad, good), (0, 0, 0));
    }

    #[test]
    fn does_not_degrade_past_the_last_tier() {
        let (idx, bad, _good) = step_tier(4, 0.5, 1, 0, 5);
        let (idx, _bad, _good) = step_tier(idx, 0.5, bad, 0, 5);
        assert_eq!(
            idx, 4,
            "already at the worst tier, nothing lower to step to"
        );
    }

    #[test]
    fn does_not_upgrade_past_the_best_tier() {
        let mut idx = 0;
        let mut bad = 0;
        let mut good = 0;
        for _ in 0..20 {
            (idx, bad, good) = step_tier(idx, 0.0, bad, good, 5);
        }
        assert_eq!(
            idx, 0,
            "already at the best tier, nothing higher to step to"
        );
    }

    #[test]
    fn middling_loss_resets_both_counters_without_stepping() {
        let (idx, bad, good) = step_tier(2, 0.10, 0, 0, 5);
        assert_eq!((idx, bad), (2, 1));
        // A report in the dead zone (between UPGRADE_LOSS and DEGRADE_LOSS)
        // resets the bad streak instead of carrying it forward.
        let (idx, bad, good) = step_tier(idx, 0.03, bad, good, 5);
        assert_eq!((idx, bad, good), (2, 0, 0));
    }
}

/// Raw captured frame (always RGBA).
struct RawFrame {
    rgba: Vec<u8>,
    width: u32,
    height: u32,
}

type FrameSlot = Arc<std::sync::Mutex<Option<RawFrame>>>;

pub(crate) enum EncodeOutput {
    Nal {
        data: Vec<u8>,
        duration: Duration,
    },
    Preview {
        rgba: Vec<u8>,
        width: u32,
        height: u32,
    },
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_capture_sources() -> anyhow::Result<Vec<CaptureSourceDto>> {
    #[cfg(all(target_os = "linux", feature = "gstreamer"))]
    if super::screen_capture_gst::is_available() {
        return Ok(super::screen_capture_gst::list_sources());
    }

    let mut sources = Vec::new();

    if let Ok(monitors) = xcap::Monitor::all() {
        for m in monitors {
            let id = match m.id() {
                Ok(v) => v,
                Err(_) => continue,
            };
            let name = m.name().unwrap_or_else(|_| format!("Monitor {id}"));
            let width = m.width().unwrap_or(0);
            let height = m.height().unwrap_or(0);

            sources.push(CaptureSourceDto {
                id: format!("monitor:{id}"),
                name,
                kind: "display".into(),
                width,
                height,
            });
        }
    }

    if let Ok(windows) = xcap::Window::all() {
        for w in windows {
            let minimized = w.is_minimized().unwrap_or(true);
            let width = w.width().unwrap_or(0);
            let height = w.height().unwrap_or(0);
            if minimized || width == 0 || height == 0 {
                continue;
            }

            let id = match w.id() {
                Ok(v) => v,
                Err(_) => continue,
            };
            let title = w.title().unwrap_or_else(|_| format!("Window {id}"));

            sources.push(CaptureSourceDto {
                id: format!("window:{id}"),
                name: title,
                kind: "window".into(),
                width,
                height,
            });
        }
    }

    Ok(sources)
}

#[flutter_rust_bridge::frb]
pub async fn start_capture(
    connection_id: String,
    source_id: String,
    config: CaptureConfigDto,
    local_preview: bool,
) -> anyhow::Result<()> {
    {
        let sessions = CAPTURE_SESSIONS.lock().await;
        if sessions.contains_key(&connection_id) {
            anyhow::bail!("capture already active for connection {connection_id}");
        }
    }

    let session = get_session(&connection_id).await?;

    let video_track = session.video_track.lock().await.clone().ok_or_else(|| {
        anyhow::anyhow!("no pre-negotiated video track for connection {connection_id}")
    })?;
    let video_sender = session.video_sender.lock().await.clone();

    let preview_bus = if local_preview {
        Some(Arc::clone(&session.event_bus))
    } else {
        None
    };

    #[cfg(all(target_os = "linux", feature = "gstreamer"))]
    let source_id = if super::screen_capture_gst::is_available() {
        match super::screen_capture_gst::start_capture_gst(
            connection_id.clone(),
            config.clone(),
            local_preview,
            Arc::clone(&video_track),
            video_sender.clone(),
            preview_bus.clone(),
        )
        .await
        {
            Ok(()) => return Ok(()),
            Err(e) => {
                tracing::warn!("GStreamer capture failed, falling back to legacy path: {e:#}");
                if source_id.starts_with("portal:") {
                    let fallback = xcap::Monitor::all()
                        .ok()
                        .and_then(|m| m.first().and_then(|m| m.id().ok()))
                        .map(|id| format!("monitor:{id}"))
                        .unwrap_or(source_id);
                    fallback
                } else {
                    source_id
                }
            }
        }
    } else {
        source_id
    };

    // Input injection (X11 only - see input_inject.rs) needs to know what's
    // being shared so it can scope/activate the right window. The portal/
    // GStreamer path above returns early and has no X11 window to scope to,
    // so this only ever registers a real "window:"/"monitor:" source.
    super::input_inject::register_target(&connection_id, &source_id).await;

    let cancel_flag = Arc::new(AtomicBool::new(false));
    let (cancel_tx, cancel_rx) = tokio::sync::watch::channel(false);
    let tier_idx = Arc::new(AtomicUsize::new(0));
    let frame_slot: FrameSlot = Arc::new(std::sync::Mutex::new(None));

    // Capture-source setup happens inside the capture thread (the ScreenCast
    // portal call can block on a user consent dialog); the result is reported
    // back so start_capture can fail fast on a bad source id.
    let (setup_tx, setup_rx) = tokio::sync::oneshot::channel::<anyhow::Result<()>>();
    spawn_capture_thread(
        source_id,
        Arc::clone(&frame_slot),
        Arc::clone(&cancel_flag),
        Arc::clone(&tier_idx),
        config.clone(),
        setup_tx,
    );
    // Generous ceiling: setup legitimately waits on the ScreenCast consent
    // dialog, but a misbehaving portal must not hang the caller forever.
    match tokio::time::timeout(Duration::from_secs(120), setup_rx).await {
        Ok(result) => {
            result.map_err(|_| anyhow::anyhow!("capture thread terminated during setup"))??
        }
        Err(_) => {
            // Unblocks the capture thread's loops if setup completes later.
            cancel_flag.store(true, Ordering::Relaxed);
            anyhow::bail!("screen capture setup timed out waiting for the desktop portal");
        }
    }

    {
        let mut sessions = CAPTURE_SESSIONS.lock().await;
        sessions.insert(
            connection_id.clone(),
            CaptureHandle::new(Arc::clone(&cancel_flag), cancel_tx),
        );
    }

    let (output_tx, output_rx) = tokio::sync::mpsc::channel::<EncodeOutput>(8);

    spawn_encode_thread(
        Arc::clone(&frame_slot),
        Arc::clone(&cancel_flag),
        Arc::clone(&tier_idx),
        config.clone(),
        preview_bus.is_some(),
        output_tx,
    );

    if let Some(sender) = video_sender {
        tokio::spawn(adapt_quality(
            sender,
            Arc::clone(&tier_idx),
            config.clone(),
            cancel_rx.clone(),
        ));
    }

    let cid = connection_id.clone();
    tokio::spawn(async move {
        write_outputs(output_rx, video_track, preview_bus).await;
        let mut sessions = CAPTURE_SESSIONS.lock().await;
        sessions.remove(&cid);
        tracing::info!(connection_id = %cid, "screen capture pipeline ended");
    });

    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn stop_capture(connection_id: String) -> anyhow::Result<()> {
    let mut sessions = CAPTURE_SESSIONS.lock().await;
    // Remove the entry here rather than waiting for the writer task: the
    // handle holds the pipeline Arc, and with it the appsink callbacks that
    // keep the output channel open — leaving it in place kept the writer
    // alive forever and made a re-share fail with "capture already active".
    if let Some(handle) = sessions.remove(&connection_id) {
        handle.cancel_flag.store(true, Ordering::Relaxed);
        let _ = handle.cancel_tx.send(true);
        #[cfg(all(target_os = "linux", feature = "gstreamer"))]
        if let Some(pipeline) = &handle.gst_pipeline {
            pipeline.stop();
        }
    }
    super::input_inject::clear_target(&connection_id).await;
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_capture_active(connection_id: String) -> bool {
    CAPTURE_SESSIONS
        .blocking_lock()
        .contains_key(&connection_id)
}

// ─── Capture stage ───────────────────────────────────────────────────────────

fn spawn_capture_thread(
    source_id: String,
    slot: FrameSlot,
    cancel: Arc<AtomicBool>,
    tier_idx: Arc<AtomicUsize>,
    config: CaptureConfigDto,
    setup_tx: tokio::sync::oneshot::Sender<anyhow::Result<()>>,
) {
    std::thread::Builder::new()
        .name("relink-capture".into())
        .spawn(move || {
            let (kind, id_str) = match source_id.split_once(':') {
                Some(pair) => pair,
                None => {
                    let _ = setup_tx.send(Err(anyhow::anyhow!(
                        "invalid source_id format: {source_id}"
                    )));
                    return;
                }
            };

            match kind {
                "monitor" => {
                    let monitor = match find_monitor(id_str) {
                        Ok(m) => m,
                        Err(e) => {
                            let _ = setup_tx.send(Err(e));
                            return;
                        }
                    };

                    // Preferred path: continuous frames from the compositor
                    // (ScreenCast portal + PipeWire on Wayland, XSHM on X11).
                    // Falls back to per-frame screenshots if unavailable.
                    match start_video_recorder(&monitor) {
                        Ok((recorder, frame_rx)) => {
                            let _ = setup_tx.send(Ok(()));
                            run_recorder_loop(frame_rx, &slot, &cancel);
                            let _ = recorder.stop();
                        }
                        Err(e) => {
                            tracing::warn!(
                                "video recorder unavailable, falling back to screenshot capture: {e}"
                            );
                            let _ = setup_tx.send(Ok(()));
                            run_poll_loop(
                                || monitor.capture_image().context("monitor capture failed"),
                                &slot,
                                &cancel,
                                &tier_idx,
                                &config,
                            );
                        }
                    }
                }
                "window" => {
                    let window = match find_window(id_str) {
                        Ok(w) => w,
                        Err(e) => {
                            let _ = setup_tx.send(Err(e));
                            return;
                        }
                    };
                    let _ = setup_tx.send(Ok(()));
                    run_poll_loop(
                        || window.capture_image().context("window capture failed"),
                        &slot,
                        &cancel,
                        &tier_idx,
                        &config,
                    );
                }
                other => {
                    let _ = setup_tx.send(Err(anyhow::anyhow!("unknown source kind: {other}")));
                }
            }

            tracing::info!("capture thread ended");
        })
        .expect("failed to spawn capture thread");
}

pub(crate) fn find_monitor(id_str: &str) -> anyhow::Result<xcap::Monitor> {
    let id: u32 = id_str.parse().context("invalid monitor id")?;
    let monitors = xcap::Monitor::all().context("failed to list monitors")?;
    monitors
        .into_iter()
        .find(|m| m.id().ok() == Some(id))
        .ok_or_else(|| anyhow::anyhow!("monitor {id} not found"))
}

pub(crate) fn find_window(id_str: &str) -> anyhow::Result<xcap::Window> {
    let id: u32 = id_str.parse().context("invalid window id")?;
    let windows = xcap::Window::all().context("failed to list windows")?;
    windows
        .into_iter()
        .find(|w| w.id().ok() == Some(id))
        .ok_or_else(|| anyhow::anyhow!("window {id} not found"))
}

#[allow(clippy::type_complexity)]
fn start_video_recorder(
    monitor: &xcap::Monitor,
) -> anyhow::Result<(xcap::VideoRecorder, std::sync::mpsc::Receiver<xcap::Frame>)> {
    let (recorder, frame_rx) = monitor
        .video_recorder()
        .context("failed to create video recorder")?;
    recorder.start().context("failed to start video recorder")?;
    Ok((recorder, frame_rx))
}

fn run_recorder_loop(
    frame_rx: std::sync::mpsc::Receiver<xcap::Frame>,
    slot: &FrameSlot,
    cancel: &AtomicBool,
) {
    while !cancel.load(Ordering::Relaxed) {
        match frame_rx.recv_timeout(Duration::from_millis(200)) {
            Ok(frame) => {
                if frame.raw.len() < (frame.width * frame.height * 4) as usize {
                    continue;
                }
                *slot.lock().unwrap() = Some(RawFrame {
                    rgba: frame.raw,
                    width: frame.width,
                    height: frame.height,
                });
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                tracing::warn!("video recorder stream disconnected");
                break;
            }
        }
    }
}

fn run_poll_loop<F>(
    capture: F,
    slot: &FrameSlot,
    cancel: &AtomicBool,
    tier_idx: &AtomicUsize,
    config: &CaptureConfigDto,
) where
    F: Fn() -> anyhow::Result<xcap::image::RgbaImage>,
{
    while !cancel.load(Ordering::Relaxed) {
        let tier = TIERS[tier_idx.load(Ordering::Relaxed)].clamped(config);
        let interval = Duration::from_micros(1_000_000 / tier.fps as u64);
        let started = Instant::now();

        match capture() {
            Ok(image) => {
                let width = image.width();
                let height = image.height();
                *slot.lock().unwrap() = Some(RawFrame {
                    rgba: image.into_raw(),
                    width,
                    height,
                });
            }
            Err(e) => {
                tracing::warn!("screenshot capture failed: {e}");
                std::thread::sleep(Duration::from_millis(250));
                continue;
            }
        }

        let elapsed = started.elapsed();
        if elapsed < interval {
            std::thread::sleep(interval - elapsed);
        }
    }
}

// ─── Encode stage ────────────────────────────────────────────────────────────

struct EncodePipeline {
    resizer: Resizer,
    resized: Option<Image<'static>>,
    planar: Option<YuvPlanarImageMut<'static, u8>>,
    encoder: Option<openh264::encoder::Encoder>,
    encoder_dims: (u32, u32),
    encoder_tier: Option<QualityTier>,
    last_hash: u64,
    last_encoded_at: Instant,
    frame_counter: u64,
}

fn spawn_encode_thread(
    slot: FrameSlot,
    cancel: Arc<AtomicBool>,
    tier_idx: Arc<AtomicUsize>,
    config: CaptureConfigDto,
    want_preview: bool,
    output_tx: tokio::sync::mpsc::Sender<EncodeOutput>,
) {
    std::thread::Builder::new()
        .name("relink-encode".into())
        .spawn(move || {
            let mut pipeline = EncodePipeline {
                resizer: Resizer::new(),
                resized: None,
                planar: None,
                encoder: None,
                encoder_dims: (0, 0),
                encoder_tier: None,
                last_hash: 0,
                last_encoded_at: Instant::now(),
                frame_counter: 0,
            };
            let mut current: Option<RawFrame> = None;

            while !cancel.load(Ordering::Relaxed) {
                let tier = TIERS[tier_idx.load(Ordering::Relaxed)].clamped(&config);
                let interval = Duration::from_micros(1_000_000 / tier.fps as u64);
                let started = Instant::now();

                if let Some(frame) = slot.lock().unwrap().take() {
                    current = Some(frame);
                }

                if let Some(frame) = &current {
                    match pipeline.process(frame, tier, want_preview) {
                        Ok(outputs) => {
                            for out in outputs {
                                // Blocking send keeps natural backpressure if
                                // the RTP writer falls behind.
                                if output_tx.blocking_send(out).is_err() {
                                    return;
                                }
                            }
                        }
                        Err(e) => {
                            tracing::warn!("encode failed: {e}");
                        }
                    }
                }

                let elapsed = started.elapsed();
                if elapsed < interval {
                    std::thread::sleep(interval - elapsed);
                }
            }
            // output_tx drops here, closing the writer task.
            tracing::info!("encode thread ended");
        })
        .expect("failed to spawn encode thread");
}

impl EncodePipeline {
    fn process(
        &mut self,
        frame: &RawFrame,
        tier: QualityTier,
        want_preview: bool,
    ) -> anyhow::Result<Vec<EncodeOutput>> {
        let (target_w, target_h) = fit_dimensions(frame.width, frame.height, tier);
        if target_w == 0 || target_h == 0 {
            return Ok(Vec::new());
        }

        // Hash the source frame BEFORE resize to skip all downstream work
        // (resize + YUV conversion + encode) on static scenes.
        let hash = xxh3_64(&frame.rgba);
        let refresh_due = self.last_encoded_at.elapsed() >= Duration::from_secs(1);
        if hash == self.last_hash && !refresh_due {
            return Ok(Vec::new());
        }
        let scene_changed = hash != self.last_hash;
        self.last_hash = hash;

        let use_source = frame.width == target_w && frame.height == target_h;
        if !use_source {
            resize_into(
                &mut self.resizer,
                &mut self.resized,
                frame,
                target_w,
                target_h,
            )?;
        }
        let rgba: &[u8] = if use_source {
            &frame.rgba
        } else {
            self.resized
                .as_ref()
                .expect("filled by resize_into")
                .buffer()
        };

        ensure_encoder(
            &mut self.encoder,
            &mut self.encoder_dims,
            &mut self.encoder_tier,
            target_w,
            target_h,
            tier,
        )?;

        let planar_stale = self
            .planar
            .as_ref()
            .map(|p| p.width != target_w || p.height != target_h)
            .unwrap_or(true);
        if planar_stale {
            self.planar = Some(YuvPlanarImageMut::<u8>::alloc(
                target_w,
                target_h,
                YuvChromaSubsampling::Yuv420,
            ));
        }
        let planar = self.planar.as_mut().expect("allocated above");
        yuv::rgba_to_yuv420(
            planar,
            rgba,
            target_w * 4,
            YuvRange::Limited,
            YuvStandardMatrix::Bt601,
            YuvConversionMode::Fast,
        )
        .map_err(|e| anyhow::anyhow!("rgba->i420 conversion failed: {e}"))?;

        let y_stride = planar.y_plane.borrow().len() / target_h as usize;
        let u_stride = planar.u_plane.borrow().len() / (target_h as usize).div_ceil(2);
        let v_stride = planar.v_plane.borrow().len() / (target_h as usize).div_ceil(2);
        let image = I420Frame {
            width: target_w as usize,
            height: target_h as usize,
            strides: (y_stride, u_stride, v_stride),
            y: planar.y_plane.borrow(),
            u: planar.u_plane.borrow(),
            v: planar.v_plane.borrow(),
        };

        // Timestamps drive openh264's rate control, so feed it the tier's
        // nominal frame interval rather than wall-clock: frames are only
        // encoded when the scene changes, and real elapsed time between two
        // of them would read as a huge frame gap and blow the bitrate budget.
        let timestamp =
            openh264::Timestamp::from_millis(self.frame_counter * 1000 / tier.fps as u64);
        let encoder = self.encoder.as_mut().expect("encoder ensured above");
        let data = encoder
            .encode_at(&image, timestamp)
            .map_err(|e| anyhow::anyhow!("H.264 encode failed: {e:?}"))?
            .to_vec();

        self.last_encoded_at = Instant::now();
        self.frame_counter += 1;

        let mut outputs = Vec::with_capacity(2);
        if !data.is_empty() {
            outputs.push(EncodeOutput::Nal {
                data,
                duration: Duration::from_micros(1_000_000 / tier.fps as u64),
            });
        }

        if want_preview && scene_changed {
            let preview_step = if tier.fps > 15 { 2 } else { 1 };
            if self.frame_counter.is_multiple_of(preview_step) {
                let (pw, ph) = ((target_w / 2) & !1, (target_h / 2) & !1);
                if pw > 0 && ph > 0 {
                    let src = ImageRef::new(target_w, target_h, rgba, PixelType::U8x4)
                        .map_err(|e| anyhow::anyhow!("preview src view failed: {e}"))?;
                    let mut dst = Image::new(pw, ph, PixelType::U8x4);
                    self.resizer
                        .resize(
                            &src,
                            &mut dst,
                            Some(&ResizeOptions::new().resize_alg(ResizeAlg::Nearest)),
                        )
                        .map_err(|e| anyhow::anyhow!("preview resize failed: {e}"))?;
                    outputs.push(EncodeOutput::Preview {
                        rgba: dst.into_vec(),
                        width: pw,
                        height: ph,
                    });
                }
            }
        }

        Ok(outputs)
    }
}

/// Downscale the frame into the reusable encode-resolution buffer.
fn resize_into(
    resizer: &mut Resizer,
    resized: &mut Option<Image<'static>>,
    frame: &RawFrame,
    target_w: u32,
    target_h: u32,
) -> anyhow::Result<()> {
    let needs_alloc = resized
        .as_ref()
        .map(|img| img.width() != target_w || img.height() != target_h)
        .unwrap_or(true);
    if needs_alloc {
        *resized = Some(Image::new(target_w, target_h, PixelType::U8x4));
    }

    let src = ImageRef::new(frame.width, frame.height, &frame.rgba, PixelType::U8x4)
        .map_err(|e| anyhow::anyhow!("resize src view failed: {e}"))?;
    let dst = resized.as_mut().expect("allocated above");
    resizer
        .resize(
            &src,
            dst,
            Some(&ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Bilinear))),
        )
        .map_err(|e| anyhow::anyhow!("frame resize failed: {e}"))?;

    Ok(())
}

/// Borrows the planes `yuv::rgba_to_yuv420` already filled so openh264 can
/// read them in place - no copy, the frame lives only for the encode call.
struct I420Frame<'a> {
    width: usize,
    height: usize,
    strides: (usize, usize, usize),
    y: &'a [u8],
    u: &'a [u8],
    v: &'a [u8],
}

impl openh264::formats::YUVSource for I420Frame<'_> {
    fn dimensions(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    fn strides(&self) -> (usize, usize, usize) {
        self.strides
    }

    fn y(&self) -> &[u8] {
        self.y
    }

    fn u(&self) -> &[u8] {
        self.u
    }

    fn v(&self) -> &[u8] {
        self.v
    }
}

fn ensure_encoder(
    encoder: &mut Option<openh264::encoder::Encoder>,
    encoder_dims: &mut (u32, u32),
    encoder_tier: &mut Option<QualityTier>,
    width: u32,
    height: u32,
    tier: QualityTier,
) -> anyhow::Result<()> {
    let dims_changed = *encoder_dims != (width, height);
    let tier_changed = *encoder_tier != Some(tier);
    if encoder.is_some() && !dims_changed && !tier_changed {
        return Ok(());
    }

    if encoder.is_some() {
        tracing::info!(
            "encoder reconfigured: {}x{} @ {}fps, {}kbps",
            width,
            height,
            tier.fps,
            tier.bitrate_kbps
        );
    }

    let config = openh264::encoder::EncoderConfig::new()
        .usage_type(openh264::encoder::UsageType::ScreenContentRealTime)
        .rate_control_mode(openh264::encoder::RateControlMode::Bitrate)
        .bitrate(openh264::encoder::BitRate::from_bps(
            tier.bitrate_kbps * 1000,
        ))
        .max_frame_rate(openh264::encoder::FrameRate::from_hz(tier.fps as f32))
        .intra_frame_period(openh264::encoder::IntraFramePeriod::from_num_frames(
            tier.fps,
        ))
        // The capture loop already gates on its own scene-change hash, so
        // openh264's detector would only duplicate that work and insert
        // keyframes we did not ask for.
        .scene_change_detect(false)
        .complexity(openh264::encoder::Complexity::Low)
        .profile(openh264::encoder::Profile::Baseline);

    let enc =
        openh264::encoder::Encoder::with_api_config(openh264::OpenH264API::from_source(), config)
            .map_err(|e| anyhow::anyhow!("failed to create openh264 encoder: {e:?}"))?;

    *encoder = Some(enc);
    *encoder_dims = (width, height);
    *encoder_tier = Some(tier);

    Ok(())
}

/// Largest size fitting within the tier cap, preserving aspect ratio,
/// dimensions forced even for 4:2:0.
fn fit_dimensions(src_w: u32, src_h: u32, tier: QualityTier) -> (u32, u32) {
    if src_w == 0 || src_h == 0 {
        return (0, 0);
    }
    let scale = f64::min(
        1.0,
        f64::min(
            tier.max_w as f64 / src_w as f64,
            tier.max_h as f64 / src_h as f64,
        ),
    );
    let w = ((src_w as f64 * scale) as u32) & !1;
    let h = ((src_h as f64 * scale) as u32) & !1;
    (w, h)
}

// ─── Output stage ────────────────────────────────────────────────────────────

pub(crate) async fn write_outputs(
    mut output_rx: tokio::sync::mpsc::Receiver<EncodeOutput>,
    track: Arc<TrackLocalStaticSample>,
    preview_bus: Option<Arc<EventBus>>,
) {
    while let Some(output) = output_rx.recv().await {
        match output {
            EncodeOutput::Nal { data, duration } => {
                let sample = Sample {
                    data: data.into(),
                    duration,
                    ..Default::default()
                };
                if let Err(e) = track.write_sample(&sample).await {
                    tracing::warn!("failed to write video sample: {e}");
                }
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

// ─── Network adaptation ──────────────────────────────────────────────────────

/// Steps the quality tier based on RTCP receiver reports from the viewer.
/// Sustained loss above 5% degrades; ~10 clean reports upgrade.
async fn adapt_quality(
    sender: Arc<RTCRtpSender>,
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
                    tracing::info!("rtcp reader ended: {e}");
                    break;
                }
            },
        };

        let mut worst_loss: f64 = -1.0;
        for packet in &packets {
            if let Some(rr) = packet
                .as_any()
                .downcast_ref::<webrtc::rtcp::receiver_report::ReceiverReport>()
            {
                for report in &rr.reports {
                    worst_loss = worst_loss.max(report.fraction_lost as f64 / 256.0);
                }
            }
        }
        if worst_loss < 0.0 {
            continue;
        }

        let current = tier_idx.load(Ordering::Relaxed);
        let (next, bad, good) = step_tier(
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
            if next > current {
                tracing::info!(
                    "network degraded (loss {:.1}%), stepping down to {}x{} @ {}fps {}kbps",
                    worst_loss * 100.0,
                    t.max_w,
                    t.max_h,
                    t.fps,
                    t.bitrate_kbps
                );
            } else {
                tracing::info!(
                    "network recovered, stepping up to {}x{} @ {}fps {}kbps",
                    t.max_w,
                    t.max_h,
                    t.fps,
                    t.bitrate_kbps
                );
            }
        }
    }
}
