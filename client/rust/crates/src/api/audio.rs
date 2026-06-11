//! Bidirectional voice chat.
//!
//! Send path mirrors the screen-capture architecture: a dedicated capture
//! thread owns the OS input stream (cpal streams are not `Send`), receives a
//! control channel for mute / source switching, downmixes and resamples to
//! 48 kHz mono, Opus-encodes 20 ms frames, and hands packets to an async
//! writer task feeding the pre-negotiated WebRTC audio track.
//!
//! Receive path: remote Opus track → decode (with packet-loss concealment on
//! sequence gaps) → bounded jitter queue → playback thread owning the cpal
//! output stream.
//!
//! Muting drops the input stream entirely so the OS microphone-in-use
//! indicator turns off; unmuting reopens it.

use anyhow::Context;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SizedSample};
use media::Sample;
use once_cell::sync::Lazy;
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{RecvTimeoutError, TryRecvError};
use std::sync::Arc;
use std::time::Duration;
use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
use webrtc::track::track_remote::TrackRemote;

use super::webrtc::get_session;

pub(crate) const OPUS_SAMPLE_RATE: u32 = 48_000;
/// 20 ms @ 48 kHz mono — the canonical Opus voice frame.
pub(crate) const FRAME_SAMPLES: usize = 960;
pub(crate) const FRAME_DURATION: Duration = Duration::from_millis(20);
const VOICE_BITRATE_BPS: i32 = 32_000;
/// Decoded remote audio is interleaved stereo.
const PLAYBACK_CHANNELS: usize = 2;
/// Bound the playback queue at ~300 ms so latency cannot accumulate.
const MAX_QUEUED_PLAYBACK_SAMPLES: usize = OPUS_SAMPLE_RATE as usize * PLAYBACK_CHANNELS * 3 / 10;
/// Conceal at most this many consecutive lost packets before resyncing.
const MAX_PLC_PACKETS: u16 = 5;
const DEFAULT_SOURCE_ID: &str = "default";

static AUDIO_CAPTURES: Lazy<std::sync::Mutex<HashMap<String, AudioCaptureHandle>>> =
    Lazy::new(|| std::sync::Mutex::new(HashMap::new()));

struct AudioCaptureHandle {
    control_tx: std::sync::mpsc::Sender<CaptureControl>,
    muted: Arc<AtomicBool>,
}

enum CaptureControl {
    SetMuted(bool),
    SetSource(Option<String>),
    Stop,
}

#[derive(Debug, Clone)]
pub struct AudioSourceDto {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

// ─── Public API ──────────────────────────────────────────────────────────────

#[flutter_rust_bridge::frb]
pub async fn list_audio_sources() -> anyhow::Result<Vec<AudioSourceDto>> {
    // Device probing can block for a while on ALSA; keep it off the runtime.
    tokio::task::spawn_blocking(|| {
        let host = cpal::default_host();
        let default_name = host
            .default_input_device()
            .and_then(|d| d.description().ok().map(|desc| desc.name().to_string()));

        let mut sources = vec![AudioSourceDto {
            id: DEFAULT_SOURCE_ID.to_string(),
            name: match &default_name {
                Some(name) => format!("System default · {name}"),
                None => "System default".to_string(),
            },
            is_default: true,
        }];

        let mut seen = std::collections::HashSet::new();
        if let Ok(devices) = host.input_devices() {
            for device in devices {
                let Ok(id) = device.id() else { continue };
                let id = id.to_string();
                if !seen.insert(id.clone()) {
                    continue;
                }
                // Skip pseudo-devices that cannot actually be opened.
                if device.default_input_config().is_err() {
                    continue;
                }
                let name = device
                    .description()
                    .ok()
                    .map(|desc| desc.name().to_string())
                    .unwrap_or_else(|| id.clone());
                sources.push(AudioSourceDto {
                    id,
                    name,
                    is_default: false,
                });
            }
        }

        Ok(sources)
    })
    .await
    .context("audio source enumeration task failed")?
}

#[flutter_rust_bridge::frb]
pub async fn start_audio_capture(
    connection_id: String,
    source_id: Option<String>,
) -> anyhow::Result<()> {
    {
        let captures = AUDIO_CAPTURES.lock().unwrap();
        if captures.contains_key(&connection_id) {
            anyhow::bail!("audio capture already active for connection {connection_id}");
        }
    }

    let session = get_session(&connection_id).await?;
    let audio_track = session.audio_track.lock().await.clone().ok_or_else(|| {
        anyhow::anyhow!("no pre-negotiated audio track for connection {connection_id}")
    })?;

    let muted = Arc::new(AtomicBool::new(false));
    let (control_tx, control_rx) = std::sync::mpsc::channel::<CaptureControl>();
    let (packet_tx, packet_rx) = tokio::sync::mpsc::channel::<Vec<u8>>(32);

    // Device + encoder setup happens inside the capture thread; the result is
    // reported back so a bad device fails fast instead of silently.
    let (setup_tx, setup_rx) = tokio::sync::oneshot::channel::<anyhow::Result<()>>();
    spawn_capture_thread(
        source_id,
        Arc::clone(&muted),
        control_rx,
        packet_tx,
        setup_tx,
    );

    match tokio::time::timeout(Duration::from_secs(15), setup_rx).await {
        Ok(result) => result
            .map_err(|_| anyhow::anyhow!("audio capture thread terminated during setup"))??,
        Err(_) => {
            let _ = control_tx.send(CaptureControl::Stop);
            anyhow::bail!("audio capture setup timed out");
        }
    }

    {
        let mut captures = AUDIO_CAPTURES.lock().unwrap();
        captures.insert(
            connection_id.clone(),
            AudioCaptureHandle { control_tx, muted },
        );
    }

    let cid = connection_id.clone();
    tokio::spawn(async move {
        write_packets(packet_rx, audio_track).await;
        AUDIO_CAPTURES.lock().unwrap().remove(&cid);
        tracing::info!(connection_id = %cid, "audio capture pipeline ended");
    });

    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn set_audio_muted(connection_id: String, muted: bool) -> anyhow::Result<()> {
    let captures = AUDIO_CAPTURES.lock().unwrap();
    let handle = captures
        .get(&connection_id)
        .ok_or_else(|| anyhow::anyhow!("no active audio capture for connection {connection_id}"))?;
    handle.muted.store(muted, Ordering::Relaxed);
    handle
        .control_tx
        .send(CaptureControl::SetMuted(muted))
        .map_err(|_| anyhow::anyhow!("audio capture thread is gone"))?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn set_audio_source(
    connection_id: String,
    source_id: Option<String>,
) -> anyhow::Result<()> {
    let captures = AUDIO_CAPTURES.lock().unwrap();
    let handle = captures
        .get(&connection_id)
        .ok_or_else(|| anyhow::anyhow!("no active audio capture for connection {connection_id}"))?;
    handle
        .control_tx
        .send(CaptureControl::SetSource(source_id))
        .map_err(|_| anyhow::anyhow!("audio capture thread is gone"))?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn stop_audio_capture(connection_id: String) -> anyhow::Result<()> {
    stop_capture_for_connection(&connection_id);
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_audio_capture_active(connection_id: String) -> bool {
    AUDIO_CAPTURES.lock().unwrap().contains_key(&connection_id)
}

/// Returns false when no capture is active.
#[flutter_rust_bridge::frb(sync)]
pub fn is_audio_muted(connection_id: String) -> bool {
    AUDIO_CAPTURES
        .lock()
        .unwrap()
        .get(&connection_id)
        .map(|h| h.muted.load(Ordering::Relaxed))
        .unwrap_or(false)
}

/// Tear down capture when the WebRTC session closes.
pub(crate) fn stop_capture_for_connection(connection_id: &str) {
    let control_tx = AUDIO_CAPTURES
        .lock()
        .unwrap()
        .get(connection_id)
        .map(|h| h.control_tx.clone());
    if let Some(tx) = control_tx {
        let _ = tx.send(CaptureControl::Stop);
    }
}

// ─── Capture stage ───────────────────────────────────────────────────────────

/// Incremental linear resampler (good enough for voice); carries fractional
/// position and the previous sample across chunk boundaries.
pub(crate) struct LinearResampler {
    src_rate: u32,
    dst_rate: u32,
    /// Position of the next output sample, in input samples, relative to the
    /// start of the next `process` chunk. May be negative (between the carried
    /// `prev` sample and the chunk's first sample).
    pos: f64,
    prev: f32,
    primed: bool,
}

impl LinearResampler {
    pub(crate) fn new(src_rate: u32, dst_rate: u32) -> Self {
        Self {
            src_rate,
            dst_rate,
            pos: 0.0,
            prev: 0.0,
            primed: false,
        }
    }

    pub(crate) fn process(&mut self, input: &[f32], output: &mut Vec<f32>) {
        if input.is_empty() {
            return;
        }
        if self.src_rate == self.dst_rate {
            output.extend_from_slice(input);
            return;
        }

        let step = self.src_rate as f64 / self.dst_rate as f64;
        if !self.primed {
            self.prev = input[0];
            self.primed = true;
        }

        // Virtual timeline: `prev` sits at index -1, `input` at 0..len.
        let mut pos = self.pos;
        loop {
            let idx = pos.floor() as isize;
            let frac = (pos - idx as f64) as f32;
            let (a, b) = if idx < 0 {
                (self.prev, input[0])
            } else if (idx as usize) + 1 < input.len() {
                (input[idx as usize], input[idx as usize + 1])
            } else {
                break;
            };
            output.push(a + (b - a) * frac);
            pos += step;
        }

        self.pos = pos - input.len() as f64;
        self.prev = *input.last().expect("non-empty input");
    }
}

/// An open microphone stream delivering mono 48 kHz samples.
struct MicStream {
    // Held only to keep the device stream alive.
    _stream: cpal::Stream,
    pcm_rx: std::sync::mpsc::Receiver<Vec<f32>>,
    resampler: LinearResampler,
}

impl MicStream {
    fn open(source_id: Option<&str>) -> anyhow::Result<Self> {
        let host = cpal::default_host();
        let device = match source_id {
            None | Some(DEFAULT_SOURCE_ID) => host
                .default_input_device()
                .ok_or_else(|| anyhow::anyhow!("no default audio input device"))?,
            Some(id_str) => {
                let device_id: cpal::DeviceId = id_str
                    .parse()
                    .map_err(|e| anyhow::anyhow!("invalid audio device id '{id_str}': {e}"))?;
                host.device_by_id(&device_id)
                    .ok_or_else(|| anyhow::anyhow!("audio input device '{id_str}' not found"))?
            }
        };

        // Prefer a native 48 kHz config so no resampling is needed.
        let supported = device
            .supported_input_configs()
            .ok()
            .and_then(|mut configs| {
                configs.find_map(|range| range.try_with_sample_rate(OPUS_SAMPLE_RATE))
            });
        let supported = match supported {
            Some(config) => config,
            None => device
                .default_input_config()
                .context("no usable audio input configuration")?,
        };

        let sample_format = supported.sample_format();
        let config: cpal::StreamConfig = supported.config();
        let channels = config.channels.max(1) as usize;
        let device_rate = config.sample_rate;

        let (pcm_tx, pcm_rx) = std::sync::mpsc::channel::<Vec<f32>>();

        let stream = match sample_format {
            cpal::SampleFormat::F32 => build_input::<f32>(&device, config, channels, pcm_tx)?,
            cpal::SampleFormat::I16 => build_input::<i16>(&device, config, channels, pcm_tx)?,
            cpal::SampleFormat::U16 => build_input::<u16>(&device, config, channels, pcm_tx)?,
            cpal::SampleFormat::I32 => build_input::<i32>(&device, config, channels, pcm_tx)?,
            cpal::SampleFormat::U32 => build_input::<u32>(&device, config, channels, pcm_tx)?,
            cpal::SampleFormat::I8 => build_input::<i8>(&device, config, channels, pcm_tx)?,
            cpal::SampleFormat::U8 => build_input::<u8>(&device, config, channels, pcm_tx)?,
            cpal::SampleFormat::F64 => build_input::<f64>(&device, config, channels, pcm_tx)?,
            other => anyhow::bail!("unsupported audio input sample format: {other:?}"),
        };
        stream
            .play()
            .context("failed to start audio input stream")?;

        Ok(Self {
            _stream: stream,
            pcm_rx,
            resampler: LinearResampler::new(device_rate, OPUS_SAMPLE_RATE),
        })
    }

    /// Receive the next chunk, downmixed (in the callback) and resampled to
    /// 48 kHz mono, appended to `out`.
    fn recv_into(&mut self, out: &mut Vec<f32>, timeout: Duration) -> Result<bool, ()> {
        match self.pcm_rx.recv_timeout(timeout) {
            Ok(chunk) => {
                self.resampler.process(&chunk, out);
                Ok(true)
            }
            Err(RecvTimeoutError::Timeout) => Ok(false),
            Err(RecvTimeoutError::Disconnected) => Err(()),
        }
    }
}

fn build_input<T>(
    device: &cpal::Device,
    config: cpal::StreamConfig,
    channels: usize,
    pcm_tx: std::sync::mpsc::Sender<Vec<f32>>,
) -> anyhow::Result<cpal::Stream>
where
    T: SizedSample,
    f32: FromSample<T>,
{
    let stream = device
        .build_input_stream(
            config,
            move |data: &[T], _: &cpal::InputCallbackInfo| {
                if data.is_empty() {
                    return;
                }
                let mut mono = Vec::with_capacity(data.len() / channels + 1);
                for frame in data.chunks_exact(channels) {
                    let mut sum = 0.0f32;
                    for sample in frame {
                        sum += (*sample).to_sample::<f32>();
                    }
                    mono.push(sum / channels as f32);
                }
                let _ = pcm_tx.send(mono);
            },
            |e| tracing::warn!("audio input stream error: {e}"),
            None,
        )
        .context("failed to build audio input stream")?;
    Ok(stream)
}

fn spawn_capture_thread(
    initial_source: Option<String>,
    muted_flag: Arc<AtomicBool>,
    control_rx: std::sync::mpsc::Receiver<CaptureControl>,
    packet_tx: tokio::sync::mpsc::Sender<Vec<u8>>,
    setup_tx: tokio::sync::oneshot::Sender<anyhow::Result<()>>,
) {
    std::thread::Builder::new()
        .name("relink-audio-capture".into())
        .spawn(move || {
            let mut encoder = match opus::Encoder::new(
                OPUS_SAMPLE_RATE,
                opus::Channels::Mono,
                opus::Application::Voip,
            ) {
                Ok(mut enc) => {
                    let _ = enc.set_bitrate(opus::Bitrate::Bits(VOICE_BITRATE_BPS));
                    let _ = enc.set_inband_fec(true);
                    let _ = enc.set_packet_loss_perc(10);
                    enc
                }
                Err(e) => {
                    let _ =
                        setup_tx.send(Err(anyhow::anyhow!("failed to create Opus encoder: {e}")));
                    return;
                }
            };

            let mut source_id = initial_source;
            let mut mic = match MicStream::open(source_id.as_deref()) {
                Ok(m) => Some(m),
                Err(e) => {
                    let _ = setup_tx.send(Err(e));
                    return;
                }
            };
            let _ = setup_tx.send(Ok(()));

            // Mono 48 kHz accumulation buffer, encoded in 20 ms slices.
            let mut pcm: Vec<f32> = Vec::with_capacity(FRAME_SAMPLES * 4);

            'run: loop {
                // Apply all pending control messages first.
                loop {
                    match control_rx.try_recv() {
                        Ok(control) => {
                            if apply_control(
                                control,
                                &mut mic,
                                &mut source_id,
                                &muted_flag,
                                &mut pcm,
                            ) {
                                break 'run;
                            }
                        }
                        Err(TryRecvError::Empty) => break,
                        Err(TryRecvError::Disconnected) => break 'run,
                    }
                }

                let mut mic_failed = false;
                match &mut mic {
                    Some(stream) => {
                        if stream
                            .recv_into(&mut pcm, Duration::from_millis(100))
                            .is_err()
                        {
                            mic_failed = true;
                        }
                    }
                    None => {
                        // Muted: just wait for the next control message.
                        match control_rx.recv_timeout(Duration::from_millis(200)) {
                            Ok(control) => {
                                if apply_control(
                                    control,
                                    &mut mic,
                                    &mut source_id,
                                    &muted_flag,
                                    &mut pcm,
                                ) {
                                    break 'run;
                                }
                            }
                            Err(RecvTimeoutError::Timeout) => {}
                            Err(RecvTimeoutError::Disconnected) => break 'run,
                        }
                        continue;
                    }
                }
                if mic_failed {
                    tracing::warn!("microphone stream ended unexpectedly; muting");
                    mic = None;
                    pcm.clear();
                    muted_flag.store(true, Ordering::Relaxed);
                    continue;
                }

                while pcm.len() >= FRAME_SAMPLES {
                    match encoder.encode_vec_float(&pcm[..FRAME_SAMPLES], 1500) {
                        Ok(packet) => {
                            if !packet.is_empty() && packet_tx.blocking_send(packet).is_err() {
                                // Writer gone — session closed.
                                break 'run;
                            }
                        }
                        Err(e) => tracing::warn!("opus encode failed: {e}"),
                    }
                    pcm.drain(..FRAME_SAMPLES);
                }
            }
            // packet_tx drops here, ending the writer task.
            tracing::info!("audio capture thread ended");
        })
        .expect("failed to spawn audio capture thread");
}

/// Returns true when the thread should stop.
fn apply_control(
    control: CaptureControl,
    mic: &mut Option<MicStream>,
    source_id: &mut Option<String>,
    muted_flag: &Arc<AtomicBool>,
    pcm: &mut Vec<f32>,
) -> bool {
    match control {
        CaptureControl::Stop => true,
        CaptureControl::SetMuted(true) => {
            // Drop the stream entirely: releases the device and turns the OS
            // microphone indicator off.
            *mic = None;
            pcm.clear();
            false
        }
        CaptureControl::SetMuted(false) => {
            if mic.is_none() {
                match MicStream::open(source_id.as_deref()) {
                    Ok(stream) => *mic = Some(stream),
                    Err(e) => {
                        tracing::warn!("failed to reopen microphone: {e}");
                        muted_flag.store(true, Ordering::Relaxed);
                    }
                }
            }
            false
        }
        CaptureControl::SetSource(new_source) => {
            *source_id = new_source;
            if mic.is_some() {
                match MicStream::open(source_id.as_deref()) {
                    Ok(stream) => {
                        *mic = Some(stream);
                        pcm.clear();
                    }
                    Err(e) => tracing::warn!("audio source switch failed: {e}"),
                }
            }
            false
        }
    }
}

// ─── Output stage (send) ─────────────────────────────────────────────────────

pub(crate) async fn write_packets(
    mut packet_rx: tokio::sync::mpsc::Receiver<Vec<u8>>,
    track: Arc<TrackLocalStaticSample>,
) {
    while let Some(packet) = packet_rx.recv().await {
        let sample = Sample {
            data: packet.into(),
            duration: FRAME_DURATION,
            ..Default::default()
        };
        if let Err(e) = track.write_sample(&sample).await {
            tracing::warn!("failed to write audio sample: {e}");
        }
    }
}

// ─── Receive / playback ──────────────────────────────────────────────────────

type PlaybackQueue = Arc<std::sync::Mutex<VecDeque<f32>>>;

fn push_playback_samples(queue: &PlaybackQueue, samples: &[f32]) {
    let mut q = queue.lock().unwrap();
    q.extend(samples.iter().copied());
    if q.len() > MAX_QUEUED_PLAYBACK_SAMPLES {
        // Drop the oldest audio to bound latency after stalls.
        let excess = q.len() - MAX_QUEUED_PLAYBACK_SAMPLES;
        q.drain(..excess);
    }
}

/// Decode a remote Opus track and play it on the default output device.
/// Ends (and releases the device) when the track read fails, i.e. when the
/// peer connection closes.
pub(crate) fn spawn_remote_audio_playback(track: Arc<TrackRemote>) {
    tokio::spawn(async move {
        let queue: PlaybackQueue = Arc::new(std::sync::Mutex::new(VecDeque::new()));
        let done = Arc::new(AtomicBool::new(false));
        spawn_playback_thread(Arc::clone(&queue), Arc::clone(&done));

        let mut decoder = match opus::Decoder::new(OPUS_SAMPLE_RATE, opus::Channels::Stereo) {
            Ok(d) => d,
            Err(e) => {
                tracing::error!("failed to create Opus decoder: {e}");
                done.store(true, Ordering::Relaxed);
                return;
            }
        };

        // 120 ms (the maximum Opus frame) of stereo.
        let mut pcm = vec![0.0f32; 5760 * PLAYBACK_CHANNELS];
        // One 20 ms frame for packet-loss concealment.
        let mut plc = vec![0.0f32; FRAME_SAMPLES * PLAYBACK_CHANNELS];
        let mut last_seq: Option<u16> = None;

        loop {
            let (packet, _) = match track.read_rtp().await {
                Ok(pair) => pair,
                Err(e) => {
                    tracing::info!("remote audio track read ended: {e}");
                    break;
                }
            };
            if packet.payload.is_empty() {
                continue;
            }

            // Conceal short gaps so they don't click.
            if let Some(prev) = last_seq {
                let lost = packet
                    .header
                    .sequence_number
                    .wrapping_sub(prev.wrapping_add(1));
                if lost > 0 && lost <= MAX_PLC_PACKETS {
                    for _ in 0..lost {
                        if let Ok(n) = decoder.decode_float(&[], &mut plc, false) {
                            push_playback_samples(&queue, &plc[..n * PLAYBACK_CHANNELS]);
                        }
                    }
                }
            }
            last_seq = Some(packet.header.sequence_number);

            match decoder.decode_float(&packet.payload, &mut pcm, false) {
                Ok(samples_per_channel) => {
                    push_playback_samples(&queue, &pcm[..samples_per_channel * PLAYBACK_CHANNELS]);
                }
                Err(e) => tracing::warn!("opus decode error: {e}"),
            }
        }

        done.store(true, Ordering::Relaxed);
    });
}

/// Pulls interleaved stereo 48 kHz samples from the shared queue and converts
/// them to the device's rate/channel-count on the fly.
struct PlaybackPump {
    queue: PlaybackQueue,
    out_channels: usize,
    /// Input samples consumed per output frame.
    step: f64,
    pos: f64,
    cur: [f32; 2],
    next: [f32; 2],
    primed: bool,
    staging: VecDeque<f32>,
}

impl PlaybackPump {
    fn new(queue: PlaybackQueue, out_rate: u32, out_channels: usize) -> Self {
        Self {
            queue,
            out_channels,
            step: OPUS_SAMPLE_RATE as f64 / out_rate as f64,
            pos: 0.0,
            cur: [0.0; 2],
            next: [0.0; 2],
            primed: false,
            staging: VecDeque::new(),
        }
    }

    /// Refill local staging from the shared queue (one lock per callback).
    fn refill(&mut self, out_frames: usize) {
        let needed_src_frames = ((self.pos + self.step * out_frames as f64).ceil() as usize) + 2;
        let needed_samples = needed_src_frames * PLAYBACK_CHANNELS;
        if self.staging.len() >= needed_samples {
            return;
        }
        let mut q = self.queue.lock().unwrap();
        let take = (needed_samples - self.staging.len()).min(q.len());
        self.staging.extend(q.drain(..take));
    }

    fn pop_src_frame(&mut self) -> Option<[f32; 2]> {
        if self.staging.len() < PLAYBACK_CHANNELS {
            return None;
        }
        let l = self.staging.pop_front().unwrap_or(0.0);
        let r = self.staging.pop_front().unwrap_or(0.0);
        Some([l, r])
    }

    fn fill<T>(&mut self, data: &mut [T])
    where
        T: SizedSample + FromSample<f32>,
    {
        let out_frames = data.len() / self.out_channels.max(1);
        self.refill(out_frames);

        if !self.primed {
            if let (Some(a), Some(b)) = (self.pop_src_frame(), self.pop_src_frame()) {
                self.cur = a;
                self.next = b;
                self.primed = true;
                self.pos = 0.0;
            }
        }

        for frame in data.chunks_mut(self.out_channels.max(1)) {
            let (l, r) = if self.primed {
                // Advance the source position; consume frames as we pass them.
                while self.pos >= 1.0 {
                    match self.pop_src_frame() {
                        Some(f) => {
                            self.cur = self.next;
                            self.next = f;
                            self.pos -= 1.0;
                        }
                        None => {
                            // Underrun: fabricate decaying frames so the
                            // output glides to silence instead of holding a
                            // DC level.
                            self.cur = self.next;
                            self.next = [self.next[0] * 0.9, self.next[1] * 0.9];
                            self.pos -= 1.0;
                        }
                    }
                }
                let t = self.pos.clamp(0.0, 1.0) as f32;
                let l = self.cur[0] + (self.next[0] - self.cur[0]) * t;
                let r = self.cur[1] + (self.next[1] - self.cur[1]) * t;
                self.pos += self.step;
                (l, r)
            } else {
                (0.0, 0.0)
            };

            match self.out_channels {
                1 => frame[0] = T::from_sample((l + r) * 0.5),
                _ => {
                    frame[0] = T::from_sample(l);
                    if frame.len() > 1 {
                        frame[1] = T::from_sample(r);
                    }
                    for slot in frame.iter_mut().skip(2) {
                        *slot = T::from_sample(0.0f32);
                    }
                }
            }
        }
    }
}

fn spawn_playback_thread(queue: PlaybackQueue, done: Arc<AtomicBool>) {
    std::thread::Builder::new()
        .name("relink-audio-playback".into())
        .spawn(move || {
            let stream = match open_playback_stream(queue) {
                Ok(stream) => stream,
                Err(e) => {
                    tracing::error!("audio playback unavailable: {e}");
                    return;
                }
            };
            if let Err(e) = stream.play() {
                tracing::error!("failed to start audio output stream: {e}");
                return;
            }
            // The cpal stream is driven by its own callback thread; this
            // thread only keeps it alive until the decode task finishes.
            while !done.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(100));
            }
            tracing::info!("audio playback thread ended");
        })
        .expect("failed to spawn audio playback thread");
}

fn open_playback_stream(queue: PlaybackQueue) -> anyhow::Result<cpal::Stream> {
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or_else(|| anyhow::anyhow!("no default audio output device"))?;

    // Prefer a native 48 kHz config so no resampling is needed.
    let supported = device
        .supported_output_configs()
        .ok()
        .and_then(|mut configs| {
            configs.find_map(|range| range.try_with_sample_rate(OPUS_SAMPLE_RATE))
        });
    let supported = match supported {
        Some(config) => config,
        None => device
            .default_output_config()
            .context("no usable audio output configuration")?,
    };

    let sample_format = supported.sample_format();
    let config: cpal::StreamConfig = supported.config();
    let out_channels = config.channels.max(1) as usize;
    let out_rate = config.sample_rate;
    let pump = PlaybackPump::new(queue, out_rate, out_channels);

    let stream = match sample_format {
        cpal::SampleFormat::F32 => build_output::<f32>(&device, config, pump)?,
        cpal::SampleFormat::I16 => build_output::<i16>(&device, config, pump)?,
        cpal::SampleFormat::U16 => build_output::<u16>(&device, config, pump)?,
        cpal::SampleFormat::I32 => build_output::<i32>(&device, config, pump)?,
        cpal::SampleFormat::U32 => build_output::<u32>(&device, config, pump)?,
        cpal::SampleFormat::I8 => build_output::<i8>(&device, config, pump)?,
        cpal::SampleFormat::U8 => build_output::<u8>(&device, config, pump)?,
        cpal::SampleFormat::F64 => build_output::<f64>(&device, config, pump)?,
        other => anyhow::bail!("unsupported audio output sample format: {other:?}"),
    };

    Ok(stream)
}

fn build_output<T>(
    device: &cpal::Device,
    config: cpal::StreamConfig,
    mut pump: PlaybackPump,
) -> anyhow::Result<cpal::Stream>
where
    T: SizedSample + FromSample<f32>,
{
    let stream = device
        .build_output_stream(
            config,
            move |data: &mut [T], _: &cpal::OutputCallbackInfo| {
                pump.fill(data);
            },
            |e| tracing::warn!("audio output stream error: {e}"),
            None,
        )
        .context("failed to build audio output stream")?;
    Ok(stream)
}
