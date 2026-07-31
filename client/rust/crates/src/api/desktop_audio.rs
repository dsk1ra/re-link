//! System/desktop audio capture: loops back whatever the OS is currently
//! playing into a second, pre-negotiated Opus track (see
//! `WebRtcSession::system_audio_track`), so a shared screen carries its
//! sound too.
//!
//! This module is deliberately platform-independent and always compiled.
//! flutter_rust_bridge emits a single unconditional dispatch table, so every
//! module in the `api` surface has to exist on every target - gating this one
//! to Linux made the generated bridge reference functions that were not there
//! on Windows, and broke both the Dart analyzer and the Rust build.
//!
//! The real work lives in [`super::desktop_audio_pipewire`], which is gated
//! the same way `screen_capture_gst` is.
//!
//! ponytail: Linux/PipeWire only. Windows/macOS loopback capture is a
//! different, unrelated API (WASAPI loopback / CoreAudio taps) - add when
//! there is a reason to.

#[cfg(all(target_os = "linux", feature = "gstreamer"))]
use super::desktop_audio_pipewire as imp;

#[cfg(not(all(target_os = "linux", feature = "gstreamer")))]
mod imp {
    pub(crate) async fn start_capture(_connection_id: String) -> anyhow::Result<()> {
        anyhow::bail!("desktop audio capture is only available on Linux with PipeWire")
    }

    pub(crate) fn is_active(_connection_id: &str) -> bool {
        false
    }

    pub(crate) fn stop_for_connection(_connection_id: &str) {}
}

#[flutter_rust_bridge::frb]
pub async fn start_desktop_audio_capture(connection_id: String) -> anyhow::Result<()> {
    imp::start_capture(connection_id).await
}

#[flutter_rust_bridge::frb]
pub async fn stop_desktop_audio_capture(connection_id: String) -> anyhow::Result<()> {
    imp::stop_for_connection(&connection_id);
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_desktop_audio_capture_active(connection_id: String) -> bool {
    imp::is_active(&connection_id)
}

/// Tear down capture when the WebRTC session closes.
pub(crate) fn stop_capture_for_connection(connection_id: &str) {
    imp::stop_for_connection(connection_id);
}
