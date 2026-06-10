// Receive-side H.264 decode via GStreamer + NVDEC.
//
//   appsrc(h264 byte-stream) → h264parse → nvh264dec
//      → cudaconvert (NV12 → RGBA, on GPU)
//      → cudadownload (CUDA memory → system memory)
//      → capsfilter(video/x-raw, RGBA)
//      → appsink (we pump frames into push_video_frame)
//
// Replaces the openh264 software decode path, which costs ~300 ms per 1080p
// frame and back-pressures the RTP read loop. NVDEC + GPU CSC bring the
// per-frame transit time to single-digit milliseconds.

use std::fs::OpenOptions;
use std::io::Write as _;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context as _};
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_app as gst_app;
use once_cell::sync::Lazy;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::rtp::codecs::h264::H264Packet;
use webrtc::track::track_remote::TrackRemote;

use super::webrtc::EventBus;

// ─── Per-stage instrumentation (mirrors sender's PIPELINE_STATS shape) ─────

#[derive(Default)]
struct StageStats {
    count: AtomicU64,
    sum_us: AtomicU64,
    max_us: AtomicU64,
}

impl StageStats {
    fn record(&self, us: u64) {
        self.count.fetch_add(1, Ordering::Relaxed);
        self.sum_us.fetch_add(us, Ordering::Relaxed);
        self.max_us.fetch_max(us, Ordering::Relaxed);
    }
    fn take(&self) -> (u64, u64, u64) {
        let c = self.count.swap(0, Ordering::Relaxed);
        let s = self.sum_us.swap(0, Ordering::Relaxed);
        let m = self.max_us.swap(0, Ordering::Relaxed);
        (c, if c == 0 { 0 } else { s / c }, m)
    }
}

#[derive(Default)]
struct RecvStats {
    rtp_packets: AtomicU64,
    samples_total: AtomicU64,
    samples_empty: AtomicU64,
    /// `appsrc.push_buffer` duration. High values mean the decode chain is
    /// backpressuring the RTP loop.
    appsrc_push_us: StageStats,
    /// End-to-end pipeline transit, measured from the wall-clock PTS we stamp
    /// in `appsrc.push_buffer` to the moment the buffer exits `appsink`.
    gst_transit_us: StageStats,
    /// Time inside `push_video_frame` total (the FRB hop to Flutter).
    push_us: StageStats,
    /// Decomposition: time to acquire the EventBus's `video_sink` Mutex.
    push_lock_us: StageStats,
    /// Decomposition: time inside `StreamSink::add` itself — i.e. the
    /// FRB-side copy + Dart_PostCObject. If this is most of `push_us`,
    /// shipping pointers instead of buffers will fix the bottleneck.
    push_sink_add_us: StageStats,
    decoded: AtomicU64,
    decode_bytes: AtomicU64,
}

static STATS: Lazy<RecvStats> = Lazy::new(RecvStats::default);

fn stats_jsonl_path() -> PathBuf {
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

fn open_stats_jsonl() -> Option<std::fs::File> {
    let path = stats_jsonl_path();
    if let Some(parent) = path.parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            tracing::warn!("recv_stats (gst): could not create {}: {e}", parent.display());
            return None;
        }
    }
    match OpenOptions::new().create(true).append(true).open(&path) {
        Ok(f) => {
            tracing::info!("recv_stats (gst): appending JSONL to {}", path.display());
            Some(f)
        }
        Err(e) => {
            tracing::warn!("recv_stats (gst): could not open {}: {e}", path.display());
            None
        }
    }
}

async fn run_stats_reporter(mut cancel_rx: tokio::sync::watch::Receiver<bool>) {
    let mut jsonl = open_stats_jsonl();
    let session_id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let mut ticker = tokio::time::interval(Duration::from_secs(2));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    ticker.tick().await; // burn the immediate first tick
    loop {
        tokio::select! {
            _ = cancel_rx.changed() => break,
            _ = ticker.tick() => {
                let rtp = STATS.rtp_packets.swap(0, Ordering::Relaxed);
                let st = STATS.samples_total.swap(0, Ordering::Relaxed);
                let se = STATS.samples_empty.swap(0, Ordering::Relaxed);
                let ap = STATS.appsrc_push_us.take();
                let tr = STATS.gst_transit_us.take();
                let pu = STATS.push_us.take();
                let pl = STATS.push_lock_us.take();
                let pa = STATS.push_sink_add_us.take();
                let dec = STATS.decoded.swap(0, Ordering::Relaxed);
                let bytes = STATS.decode_bytes.swap(0, Ordering::Relaxed);
                let fps = dec as f64 / 2.0;
                tracing::info!(
                    target: "relink::recv_stats",
                    "2s recv(gst): rtp={} samples={} (empty={}) appsrc_push {{n={} avg={}µs max={}µs}} gst_transit {{n={} avg={}µs max={}µs}} push {{n={} avg={}µs max={}µs}} push_lock {{avg={}µs max={}µs}} push_sink_add {{avg={}µs max={}µs}} decoded={} ({:.1} fps) bytes={}",
                    rtp, st, se,
                    ap.0, ap.1, ap.2,
                    tr.0, tr.1, tr.2,
                    pu.0, pu.1, pu.2,
                    pl.1, pl.2,
                    pa.1, pa.2,
                    dec, fps, bytes,
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
                        "path": "gst",
                        "rtp_packets": rtp,
                        "samples_total": st,
                        "samples_empty": se,
                        "decoded": dec,
                        "decoded_fps": fps,
                        "decode_bytes": bytes,
                        "appsrc_push_us":   {"n": ap.0, "avg": ap.1, "max": ap.2},
                        "gst_transit_us":   {"n": tr.0, "avg": tr.1, "max": tr.2},
                        "push_us":          {"n": pu.0, "avg": pu.1, "max": pu.2},
                        "push_lock_us":     {"n": pl.0, "avg": pl.1, "max": pl.2},
                        "push_sink_add_us": {"n": pa.0, "avg": pa.1, "max": pa.2},
                    });
                    if let Err(e) = writeln!(f, "{}", row).and_then(|()| f.flush()) {
                        tracing::warn!("recv_stats (gst): JSONL write failed, disabling: {e}");
                        jsonl = None;
                    }
                }
            }
        }
    }
}

// ─── Public API ────────────────────────────────────────────────────────────

pub(crate) fn is_available() -> bool {
    let _ = gst::init();
    let has = |name: &str| gst::ElementFactory::make(name).build().is_ok();
    // cudaconvert/cudadownload are NOT required: they need NVRTC, which is
    // often missing even where NVDEC works. Without them nvh264dec outputs
    // system-memory NV12 and a multithreaded CPU videoconvert does the RGBA
    // conversion (a few ms at 1080p) — still far ahead of openh264.
    let ok = has("h264parse") && has("nvh264dec");
    tracing::info!("GStreamer NVDEC receive: available={ok}");
    ok
}

pub(crate) async fn run_decode_pipeline(
    track: Arc<TrackRemote>,
    bus: Arc<EventBus>,
    pc: Arc<RTCPeerConnection>,
) -> anyhow::Result<()> {
    let _ = gst::init();

    let pipeline = gst::Pipeline::new();

    let src_caps = gst::Caps::builder("video/x-h264")
        .field("stream-format", "byte-stream")
        .field("alignment", "au")
        .build();

    let appsrc = gst_app::AppSrc::builder()
        .caps(&src_caps)
        .format(gst::Format::Time)
        .is_live(true)
        // We stamp wall-clock PTS ourselves so appsink can measure transit
        // latency. Same trick as the sender pipeline.
        .do_timestamp(false)
        .build();

    let h264parse = gst::ElementFactory::make("h264parse")
        .build()
        .context("h264parse")?;
    let decoder = gst::ElementFactory::make("nvh264dec")
        .build()
        .context("nvh264dec")?;

    // GPU CSC when the CUDA converters registered (they need NVRTC); else
    // nvh264dec hands us system-memory NV12 and the CPU converts to RGBA.
    let convert_chain: Vec<gst::Element> = match (
        gst::ElementFactory::make("cudaconvert").build(),
        gst::ElementFactory::make("cudadownload").build(),
    ) {
        (Ok(cc), Ok(cd)) => vec![cc, cd],
        _ => {
            let n_threads = std::thread::available_parallelism()
                .map(|n| n.get() as u32)
                .unwrap_or(4)
                .min(8);
            tracing::info!("CUDA postproc unavailable; decoding via CPU videoconvert");
            vec![gst::ElementFactory::make("videoconvert")
                .property("n-threads", n_threads)
                .build()
                .context("videoconvert")?]
        }
    };

    let out_caps = gst::Caps::builder("video/x-raw")
        .field("format", "RGBA")
        .build();
    let out_capsfilter = gst::ElementFactory::make("capsfilter")
        .property("caps", &out_caps)
        .build()
        .context("output capsfilter")?;

    let appsink = gst_app::AppSink::builder()
        .sync(false)
        .drop(true)
        .max_buffers(2)
        .build();

    let mut elements: Vec<&gst::Element> = vec![
        appsrc.upcast_ref::<gst::Element>(),
        &h264parse,
        &decoder,
    ];
    elements.extend(convert_chain.iter());
    elements.push(&out_capsfilter);
    elements.push(appsink.upcast_ref::<gst::Element>());
    pipeline
        .add_many(elements.iter().copied())
        .context("pipeline.add_many")?;
    gst::Element::link_many(elements.iter().copied()).context("link_many decode chain")?;

    // Appsink callback runs on a GStreamer streaming thread. Frames are
    // published into VIDEO_TEXTURE directly; the Flutter compositor reads
    // them via the FlPixelBufferTexture subclass in the runner. On the
    // first frame we also poke a sentinel through the FRB video stream so
    // Track the last frame dimensions signaled to Dart so we can re-send
    // the sentinel whenever the source resolution changes (e.g. the host
    // switches monitors or resizes the capture window).
    let signaled_width = Arc::new(AtomicU32::new(0));
    let signaled_height = Arc::new(AtomicU32::new(0));
    let bus_for_callback = bus.clone();
    let runtime = tokio::runtime::Handle::current();
    let sig_w = Arc::clone(&signaled_width);
    let sig_h = Arc::clone(&signaled_height);
    appsink.set_callbacks(
        gst_app::AppSinkCallbacks::builder()
            .new_sample(move |sink| {
                let sample = sink.pull_sample().map_err(|_| gst::FlowError::Eos)?;
                let buffer = sample.buffer().ok_or(gst::FlowError::Error)?;

                if let Some(pts) = buffer.pts() {
                    let now_ns = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .map(|d| d.as_nanos() as u64)
                        .unwrap_or(0);
                    let us = now_ns.saturating_sub(pts.nseconds()) / 1000;
                    STATS.gst_transit_us.record(us);
                }

                let caps = sample.caps().ok_or(gst::FlowError::Error)?;
                let structure = caps.structure(0).ok_or(gst::FlowError::Error)?;
                let width = structure.get::<i32>("width").unwrap_or(0) as u32;
                let height = structure.get::<i32>("height").unwrap_or(0) as u32;

                // Phase 3 step 1: receive path no longer goes through the
                // ring buffer / FRB stream — the responder consumes via the
                // Flutter Texture widget directly, which reads from
                // VIDEO_TEXTURE. Skipping the ring write saves an 8 MB
                // memcpy per frame (and a slot claim + descriptor send).
                //
                // Phase 3 step 2 holds the mapped GstBuffer inside
                // VIDEO_TEXTURE to remove this memcpy too.
                crate::api::video_texture::VIDEO_TEXTURE.publish_buffer(
                    buffer.to_owned(),
                    width,
                    height,
                );

                STATS.decoded.fetch_add(1, Ordering::Relaxed);
                STATS.decode_bytes.fetch_add(buffer.size() as u64, Ordering::Relaxed);

                // Sentinel: poke a zero-length frame with the real source
                // dimensions down the FRB video stream so Dart can set up
                // aspect-ratio-correct rendering. Re-sent whenever the
                // resolution changes (e.g. host switches monitors). Slot
                // u32::MAX is out-of-range, so releaseVideoFrame is a no-op.
                let prev_w = sig_w.load(Ordering::Relaxed);
                let prev_h = sig_h.load(Ordering::Relaxed);
                if prev_w != width || prev_h != height {
                    sig_w.store(width, Ordering::Relaxed);
                    sig_h.store(height, Ordering::Relaxed);
                    let b = bus_for_callback.clone();
                    runtime.spawn(async move {
                        b.push_video_frame(0, 0, width, height, u32::MAX, 0).await;
                    });
                }

                Ok(gst::FlowSuccess::Ok)
            })
            .build(),
    );

    let cancel_flag_for_bus = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let cancel_flag_for_loop = Arc::clone(&cancel_flag_for_bus);
    let _bus_watch = pipeline.bus().and_then(|bus| {
        let cancel = cancel_flag_for_bus;
        bus.add_watch(move |_, msg| {
            use gst::glib;
            match msg.view() {
                gst::MessageView::Error(err) => {
                    tracing::error!(
                        "GStreamer decode error: {} (debug: {:?})",
                        err.error(),
                        err.debug()
                    );
                    cancel.store(true, Ordering::Relaxed);
                    glib::ControlFlow::Break
                }
                gst::MessageView::Eos(_) => {
                    tracing::info!("GStreamer decode pipeline EOS");
                    cancel.store(true, Ordering::Relaxed);
                    glib::ControlFlow::Break
                }
                _ => glib::ControlFlow::Continue,
            }
        })
        .ok()
    });

    pipeline
        .set_state(gst::State::Playing)
        .map_err(|_| anyhow!("decode pipeline set_state Playing failed"))?;

    tracing::info!("GStreamer NVDEC decode pipeline started");

    // Kick the sender for a fresh keyframe so we don't have to wait up to a
    // full GOP for the first frame to display.
    let media_ssrc = track.ssrc();
    let pli = rtcp::payload_feedbacks::picture_loss_indication::PictureLossIndication {
        sender_ssrc: 0,
        media_ssrc,
    };
    let _ = pc.write_rtcp(&[Box::new(pli)]).await;

    // Stats reporter
    let (stats_cancel_tx, stats_cancel_rx) = tokio::sync::watch::channel(false);
    tokio::spawn(run_stats_reporter(stats_cancel_rx));

    // RTP read loop → appsrc
    // 128 packets ≈ 250 ms at 5 Mbps — bounds how long a loss gap can stall
    // frame delivery. 512 held frames back for over a second under loss.
    let mut sample_builder =
        media::io::sample_builder::SampleBuilder::new(128, H264Packet::default(), 90000);

    let result: anyhow::Result<()> = loop {
        if cancel_flag_for_loop.load(Ordering::Relaxed) {
            break Err(anyhow!("decode pipeline reported a fatal error"));
        }
        let (rtp_packet, _attr) = match track.read_rtp().await {
            Ok(p) => p,
            Err(e) => {
                tracing::info!("remote video track read ended (gst decode): {e}");
                break Ok(());
            }
        };
        STATS.rtp_packets.fetch_add(1, Ordering::Relaxed);
        sample_builder.push(rtp_packet);

        while let Some(sample) = sample_builder.pop() {
            STATS.samples_total.fetch_add(1, Ordering::Relaxed);
            if sample.data.is_empty() {
                STATS.samples_empty.fetch_add(1, Ordering::Relaxed);
                continue;
            }

            let now_ns = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(0);
            // `Bytes` satisfies from_slice's bounds — wrap it zero-copy
            // instead of cloning every assembled access unit.
            let mut buffer = gst::Buffer::from_slice(sample.data);
            buffer
                .make_mut()
                .set_pts(gst::ClockTime::from_nseconds(now_ns));

            let push_started = Instant::now();
            if appsrc.push_buffer(buffer).is_err() {
                tracing::warn!("appsrc.push_buffer failed; tearing down decode pipeline");
                break;
            }
            STATS
                .appsrc_push_us
                .record(push_started.elapsed().as_micros() as u64);
        }
    };

    let _ = stats_cancel_tx.send(true);
    let _ = appsrc.end_of_stream();
    let _ = pipeline.set_state(gst::State::Null);

    result
}
