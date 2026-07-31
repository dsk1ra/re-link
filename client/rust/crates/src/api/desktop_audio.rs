//! System/desktop audio capture (Linux/PipeWire only): loops back whatever
//! the OS is currently playing into a second, pre-negotiated Opus track
//! (see `WebRtcSession::system_audio_track`), so a shared screen carries
//! its sound too.
//!
//! Reuses the exact Opus-encode + track-write pipeline `audio.rs` already
//! has for voice chat (`write_packets`, `LinearResampler`) - the PCM
//! source is the only real difference: a native PipeWire stream capturing
//! the default sink's monitor (the same "capture what's playing" trick
//! `pavucontrol`'s "Monitor of ..." recording uses, via the
//! `stream.capture.sink` property) instead of a cpal microphone. Encoded
//! stereo rather than downmixed to mono, since this is general audio
//! (video/game/music sound), not a voice call.
//!
//! ponytail: Linux/PipeWire only. Windows/macOS loopback capture is a
//! different, unrelated API (WASAPI loopback / CoreAudio taps) - add when
//! there's a Windows/macOS client to justify it.

use super::audio::{write_packets, LinearResampler, FRAME_SAMPLES, OPUS_SAMPLE_RATE};
use super::webrtc::get_session;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::time::Duration;

/// General audio (not voice), so a higher bitrate and Opus's music-tuned
/// mode than the 32kbps/Voip settings `audio.rs` uses for the mic.
const DESKTOP_AUDIO_BITRATE_BPS: i32 = 96_000;
const CHANNELS: usize = 2;
const FRAME_SAMPLES_STEREO: usize = FRAME_SAMPLES * CHANNELS;

static CAPTURES: Lazy<std::sync::Mutex<HashMap<String, DesktopAudioCaptureHandle>>> =
    Lazy::new(|| std::sync::Mutex::new(HashMap::new()));

struct DesktopAudioCaptureHandle {
    quit_tx: pipewire::channel::Sender<()>,
}

#[flutter_rust_bridge::frb]
pub async fn start_desktop_audio_capture(connection_id: String) -> anyhow::Result<()> {
    {
        let captures = CAPTURES.lock().unwrap();
        if captures.contains_key(&connection_id) {
            anyhow::bail!("desktop audio capture already active for connection {connection_id}");
        }
    }

    let session = get_session(&connection_id).await?;
    let track = session
        .system_audio_track
        .lock()
        .await
        .clone()
        .ok_or_else(|| {
            anyhow::anyhow!("no pre-negotiated system audio track for connection {connection_id}")
        })?;

    let (quit_tx, quit_rx) = pipewire::channel::channel::<()>();
    let (raw_tx, raw_rx) = std::sync::mpsc::sync_channel::<RawChunk>(32);
    let (packet_tx, packet_rx) = tokio::sync::mpsc::channel::<Vec<u8>>(32);
    let (setup_tx, setup_rx) = tokio::sync::oneshot::channel::<anyhow::Result<()>>();

    spawn_pipewire_thread(raw_tx, quit_rx);
    spawn_encode_thread(raw_rx, packet_tx, setup_tx);

    match tokio::time::timeout(Duration::from_secs(10), setup_rx).await {
        Ok(result) => result
            .map_err(|_| anyhow::anyhow!("desktop audio thread terminated during setup"))??,
        Err(_) => {
            let _ = quit_tx.send(());
            anyhow::bail!(
                "desktop audio setup timed out - no audio reached PipeWire \
                 (check that a sink monitor is available)"
            );
        }
    }

    {
        let mut captures = CAPTURES.lock().unwrap();
        captures.insert(connection_id.clone(), DesktopAudioCaptureHandle { quit_tx });
    }

    let cid = connection_id.clone();
    tokio::spawn(async move {
        write_packets(packet_rx, track).await;
        CAPTURES.lock().unwrap().remove(&cid);
        tracing::info!(connection_id = %cid, "desktop audio capture pipeline ended");
    });

    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn stop_desktop_audio_capture(connection_id: String) -> anyhow::Result<()> {
    stop_capture_for_connection(&connection_id);
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_desktop_audio_capture_active(connection_id: String) -> bool {
    CAPTURES.lock().unwrap().contains_key(&connection_id)
}

/// Tear down capture when the WebRTC session closes.
pub(crate) fn stop_capture_for_connection(connection_id: &str) {
    let quit_tx = CAPTURES
        .lock()
        .unwrap()
        .get(connection_id)
        .map(|h| h.quit_tx.clone());
    if let Some(tx) = quit_tx {
        let _ = tx.send(());
    }
}

// ─── PipeWire capture thread ─────────────────────────────────────────────────

/// One buffer's worth of interleaved samples at whatever rate/channel count
/// the session graph negotiated - already normalized to stereo (see
/// `to_stereo_interleaved`), but not necessarily 48kHz.
struct RawChunk {
    samples: Vec<f32>,
    rate: u32,
}

/// Duplicates mono to both channels, passes stereo through, and drops
/// anything past the first two channels - PipeWire monitor sources are
/// virtually always mono or stereo, and the RTP track is declared stereo.
fn to_stereo_interleaved(data: &[f32], channels: usize) -> Vec<f32> {
    match channels {
        0 => Vec::new(),
        1 => data.iter().flat_map(|&s| [s, s]).collect(),
        2 => data.to_vec(),
        n => data
            .chunks_exact(n)
            .flat_map(|frame| [frame[0], frame[1]])
            .collect(),
    }
}

fn spawn_pipewire_thread(
    raw_tx: std::sync::mpsc::SyncSender<RawChunk>,
    quit_rx: pipewire::channel::Receiver<()>,
) {
    std::thread::Builder::new()
        .name("relink-desktop-audio-pw".into())
        .spawn(move || {
            if let Err(e) = run_pipewire_capture(raw_tx, quit_rx) {
                tracing::warn!("desktop audio PipeWire capture failed: {e:#}");
            }
        })
        .expect("failed to spawn desktop audio PipeWire thread");
}

fn run_pipewire_capture(
    raw_tx: std::sync::mpsc::SyncSender<RawChunk>,
    quit_rx: pipewire::channel::Receiver<()>,
) -> anyhow::Result<()> {
    use pipewire::{
        context::ContextRc,
        keys::{MEDIA_CATEGORY, MEDIA_ROLE, MEDIA_TYPE, STREAM_CAPTURE_SINK},
        main_loop::MainLoopRc,
        spa::{
            param::{
                audio::{AudioFormat, AudioInfoRaw},
                format::{MediaSubtype, MediaType},
                format_utils, ParamType,
            },
            pod::{serialize::PodSerializer, Object, Pod, Value},
            utils::{Direction, SpaTypes},
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

    // The property that turns this into a loopback capture: instead of
    // opening a real microphone, the session manager routes this input
    // stream to the default sink's monitor - the same mechanism
    // pavucontrol's "Monitor of ..." recordings use.
    let stream = StreamRc::new(
        core,
        "relink-desktop-audio",
        pipewire::properties::properties! {
            *MEDIA_TYPE => "Audio",
            *MEDIA_CATEGORY => "Capture",
            *MEDIA_ROLE => "Music",
            *STREAM_CAPTURE_SINK => "true",
        },
    )
    .map_err(|e| anyhow::anyhow!("Stream::new: {e}"))?;

    struct UserData {
        raw_tx: std::sync::mpsc::SyncSender<RawChunk>,
        format: Option<AudioInfoRaw>,
    }
    let user_data = UserData {
        raw_tx,
        format: None,
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
            if media_type != MediaType::Audio || media_subtype != MediaSubtype::Raw {
                return;
            }

            let mut info = AudioInfoRaw::new();
            if info.parse(param).is_err() {
                tracing::warn!("PipeWire: failed to parse audio format pod");
                return;
            }
            tracing::info!(
                "PipeWire desktop audio: rate={} channels={}",
                info.rate(),
                info.channels()
            );
            user_data.format = Some(info);
        })
        .process(|stream, user_data| {
            let Some(format) = &user_data.format else {
                return;
            };
            let Some(mut buffer) = stream.dequeue_buffer() else {
                return;
            };
            let datas = buffer.datas_mut();
            if datas.is_empty() {
                return;
            }
            let data = &mut datas[0];
            let size = data.chunk().size() as usize;
            let Some(slice) = data.data() else { return };
            if slice.len() < size || size == 0 {
                return;
            }

            let channels = format.channels() as usize;
            let n_floats = size / std::mem::size_of::<f32>();
            let samples: Vec<f32> = slice[..n_floats * std::mem::size_of::<f32>()]
                .chunks_exact(4)
                .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
                .collect();

            let chunk = RawChunk {
                samples: to_stereo_interleaved(&samples, channels),
                rate: format.rate(),
            };
            let _ = user_data.raw_tx.try_send(chunk);
        })
        .register()
        .map_err(|e| anyhow::anyhow!("listener register: {e}"))?;

    // Leave rate/channels unset so we accept whatever the native graph runs
    // at (matching the crate's own audio-capture example) - the encode
    // thread resamples if it isn't 48kHz.
    let mut audio_info = AudioInfoRaw::new();
    audio_info.set_format(AudioFormat::F32LE);
    let obj = Object {
        type_: SpaTypes::ObjectParamFormat.as_raw(),
        id: ParamType::EnumFormat.as_raw(),
        properties: audio_info.into(),
    };
    let pod_bytes = PodSerializer::serialize(std::io::Cursor::new(Vec::new()), &Value::Object(obj))
        .map_err(|e| anyhow::anyhow!("SPA pod serialize: {e}"))?
        .0
        .into_inner();
    let mut params =
        [Pod::from_bytes(&pod_bytes).ok_or_else(|| anyhow::anyhow!("invalid SPA pod"))?];

    stream
        .connect(
            Direction::Input,
            None,
            StreamFlags::AUTOCONNECT | StreamFlags::MAP_BUFFERS,
            &mut params,
        )
        .map_err(|e| anyhow::anyhow!("stream connect: {e}"))?;

    tracing::info!("PipeWire desktop audio stream connected, entering mainloop");
    main_loop.run();
    tracing::info!("PipeWire desktop audio capture thread ended");
    Ok(())
}

// ─── Encode thread ────────────────────────────────────────────────────────────

fn spawn_encode_thread(
    raw_rx: std::sync::mpsc::Receiver<RawChunk>,
    packet_tx: tokio::sync::mpsc::Sender<Vec<u8>>,
    setup_tx: tokio::sync::oneshot::Sender<anyhow::Result<()>>,
) {
    std::thread::Builder::new()
        .name("relink-desktop-audio-encode".into())
        .spawn(move || {
            let mut encoder = match opus::Encoder::new(
                OPUS_SAMPLE_RATE,
                opus::Channels::Stereo,
                opus::Application::Audio,
            ) {
                Ok(mut enc) => {
                    let _ = enc.set_bitrate(opus::Bitrate::Bits(DESKTOP_AUDIO_BITRATE_BPS));
                    enc
                }
                Err(e) => {
                    let _ =
                        setup_tx.send(Err(anyhow::anyhow!("failed to create Opus encoder: {e}")));
                    return;
                }
            };

            // Confirms the PipeWire side actually connected before declaring
            // capture started - same "fail fast on setup" pattern the other
            // capture pipelines use.
            let first = match raw_rx.recv_timeout(Duration::from_secs(9)) {
                Ok(chunk) => chunk,
                Err(_) => {
                    let _ = setup_tx.send(Err(anyhow::anyhow!(
                        "no audio received from PipeWire within the setup window"
                    )));
                    return;
                }
            };
            let _ = setup_tx.send(Ok(()));

            let mut resampler_l = LinearResampler::new(first.rate, OPUS_SAMPLE_RATE);
            let mut resampler_r = LinearResampler::new(first.rate, OPUS_SAMPLE_RATE);
            let mut pcm: Vec<f32> = Vec::with_capacity(FRAME_SAMPLES_STEREO * 4);

            let mut process_chunk = |chunk: RawChunk, pcm: &mut Vec<f32>| {
                if chunk.rate == OPUS_SAMPLE_RATE {
                    pcm.extend_from_slice(&chunk.samples);
                    return;
                }
                let (mut left, mut right) = (Vec::new(), Vec::new());
                for pair in chunk.samples.chunks_exact(CHANNELS) {
                    left.push(pair[0]);
                    right.push(pair[1]);
                }
                let (mut out_l, mut out_r) = (Vec::new(), Vec::new());
                resampler_l.process(&left, &mut out_l);
                resampler_r.process(&right, &mut out_r);
                for (l, r) in out_l.into_iter().zip(out_r) {
                    pcm.push(l);
                    pcm.push(r);
                }
            };

            process_chunk(first, &mut pcm);

            loop {
                while pcm.len() >= FRAME_SAMPLES_STEREO {
                    match encoder.encode_vec_float(&pcm[..FRAME_SAMPLES_STEREO], 1500) {
                        Ok(packet) => {
                            if !packet.is_empty() && packet_tx.blocking_send(packet).is_err() {
                                return; // writer gone — session closed
                            }
                        }
                        Err(e) => tracing::warn!("desktop audio opus encode failed: {e}"),
                    }
                    pcm.drain(..FRAME_SAMPLES_STEREO);
                }

                match raw_rx.recv_timeout(Duration::from_millis(500)) {
                    Ok(chunk) => process_chunk(chunk, &mut pcm),
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
                }
            }
            tracing::info!("desktop audio encode thread ended");
        })
        .expect("failed to spawn desktop audio encode thread");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mono_duplicates_to_both_channels() {
        assert_eq!(
            to_stereo_interleaved(&[1.0, 2.0], 1),
            vec![1.0, 1.0, 2.0, 2.0]
        );
    }

    #[test]
    fn stereo_passes_through_unchanged() {
        assert_eq!(
            to_stereo_interleaved(&[1.0, 2.0, 3.0, 4.0], 2),
            vec![1.0, 2.0, 3.0, 4.0]
        );
    }

    #[test]
    fn extra_channels_beyond_stereo_are_dropped() {
        // 3-channel frames, take only the first two of each.
        assert_eq!(
            to_stereo_interleaved(&[1.0, 2.0, 3.0, 4.0, 5.0, 6.0], 3),
            vec![1.0, 2.0, 4.0, 5.0]
        );
    }

    // Connects to the real PipeWire session and asserts at least one raw
    // chunk actually arrives - proves the sink-monitor routing and format
    // negotiation work on a live system, not just that the pod bytes are
    // well-formed. Needs a running PipeWire session with a default sink,
    // same reason the X11 input tests are excluded from the default run.
    #[test]
    #[ignore = "connects to the live PipeWire session"]
    fn captures_at_least_one_real_chunk_from_the_default_sink_monitor() {
        let (raw_tx, raw_rx) = std::sync::mpsc::sync_channel::<RawChunk>(32);
        let (quit_tx, quit_rx) = pipewire::channel::channel::<()>();

        let handle = std::thread::spawn(move || {
            run_pipewire_capture(raw_tx, quit_rx).expect("pipewire capture failed");
        });

        let chunk = raw_rx
            .recv_timeout(Duration::from_secs(10))
            .expect("no audio chunk arrived from the default sink monitor within 10s");
        assert!(!chunk.samples.is_empty());
        assert!(chunk.rate > 0);

        quit_tx.send(()).expect("failed to signal quit");
        handle.join().expect("pipewire thread panicked");
    }
}
