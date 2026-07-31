// Zero-copy video frame state read by the GTK `FlPixelBufferTexture`
// subclass in the Linux runner (see `linux/runner/relink_video_texture.cc`).
//
// Each slot owns the most recent decoded `gst::Buffer` for that slot,
// kept mapped readable for direct access. The C `copy_pixels` callback
// reads through the buffer's mapped pointer without any intermediate
// memcpy on the Rust side. The previous slot's `MappedBuffer` is dropped
// after a new one is published, releasing the GStreamer-side memory
// back to its pool.
//
// Producer/consumer protocol:
//   * Decoder calls `publish_buffer(buf, w, h)` after a new frame is
//     decoded. The buffer is mapped and stored in the "back" slot (the
//     one not pointed at by `front`); the atomic front index is then
//     flipped to point at it.
//   * The C `copy_pixels` callback calls `relink_video_copy_pixels(...)`,
//     which loads `front` and returns the pointer + dims of that slot's
//     mapped buffer.
//   * Two slots are sufficient as long as the GL upload following each
//     `copy_pixels` call completes before the decoder publishes twice —
//     at our 27 fps source and ~60 Hz vsync, the engine reads many times
//     per decoder cycle, so the back slot the decoder writes to is never
//     the one the engine is currently uploading from.

use gstreamer::buffer::{MappedBuffer, Readable};
use once_cell::sync::Lazy;
use std::cell::UnsafeCell;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU8, Ordering};

/// Backing store for one slot's pixels. The GStreamer decode path keeps its
/// `gst::Buffer` mapped for zero-copy reads; the openh264 software fallback
/// has no gst buffer, only an owned RGBA `Vec`. Both expose a stable pointer
/// for the compositor to read, so `TextureVideoView` renders identically
/// regardless of which decoder produced the frame.
enum FrameStore {
    Gst(MappedBuffer<Readable>),
    Owned(Vec<u8>),
}

impl FrameStore {
    fn as_ptr(&self) -> *const u8 {
        match self {
            FrameStore::Gst(m) => m.as_slice().as_ptr(),
            FrameStore::Owned(v) => v.as_ptr(),
        }
    }
}

struct Slot {
    /// `None` until first publish on this slot.
    frame: UnsafeCell<Option<FrameStore>>,
    width: AtomicU32,
    height: AtomicU32,
}

impl Slot {
    fn new() -> Self {
        Self {
            frame: UnsafeCell::new(None),
            width: AtomicU32::new(0),
            height: AtomicU32::new(0),
        }
    }
}

pub(crate) struct VideoTexture {
    slots: [Slot; 2],
    front: AtomicU8,
    has_data: AtomicBool,
}

// SAFETY: the decoder is the only writer of a slot's `mapped` cell and only
// ever writes to the "back" slot (1 - front). The engine reads from the
// "front" slot via the stable pointer of its `MappedBuffer`. The front index
// only changes via `publish_buffer()` after the back slot's write completes.
unsafe impl Send for VideoTexture {}
unsafe impl Sync for VideoTexture {}

pub(crate) static VIDEO_TEXTURE: Lazy<VideoTexture> = Lazy::new(|| VideoTexture {
    slots: [Slot::new(), Slot::new()],
    front: AtomicU8::new(0),
    has_data: AtomicBool::new(false),
});

impl VideoTexture {
    /// Replace the back slot's buffer with `buf` (mapped readable) and
    /// publish it as the new front. The previous occupant of the back slot
    /// is dropped, releasing it back to the GStreamer buffer pool.
    pub(crate) fn publish_buffer(&self, buf: gstreamer::Buffer, width: u32, height: u32) {
        let mapped = match buf.into_mapped_buffer_readable() {
            Ok(m) => m,
            Err(_) => return,
        };
        self.publish(FrameStore::Gst(mapped), width, height);
    }

    /// Publish an owned RGBA buffer (openh264 software-decode fallback, which
    /// has no `gst::Buffer` to keep mapped). `rgba` must be `width*height*4`
    /// bytes; the compositor reads `width*height*4` from the returned pointer.
    pub(crate) fn publish_owned_rgba(&self, rgba: Vec<u8>, width: u32, height: u32) {
        self.publish(FrameStore::Owned(rgba), width, height);
    }

    fn publish(&self, frame: FrameStore, width: u32, height: u32) {
        let front = self.front.load(Ordering::Acquire);
        let back = 1 - front;
        let slot = &self.slots[back as usize];
        // SAFETY: decoder is the only writer of this slot's `frame` cell.
        // Engine only reads slots[front]; back != front so no aliasing.
        // The previous `Option<FrameStore>` (if any) is dropped here,
        // releasing the old buffer.
        unsafe {
            *slot.frame.get() = Some(frame);
        }
        slot.width.store(width, Ordering::Release);
        slot.height.store(height, Ordering::Release);
        self.front.store(back, Ordering::Release);
        self.has_data.store(true, Ordering::Release);

        // Wake the engine. Safe to call from any thread per the C impl.
        unsafe {
            relink_video_texture_mark_dirty();
        }
    }

    fn current(&self) -> Option<(*const u8, u32, u32)> {
        if !self.has_data.load(Ordering::Acquire) {
            return None;
        }
        let front = self.front.load(Ordering::Acquire);
        let slot = &self.slots[front as usize];
        let width = slot.width.load(Ordering::Acquire);
        let height = slot.height.load(Ordering::Acquire);
        if width == 0 || height == 0 {
            return None;
        }
        // SAFETY: front slot is not written by the decoder until the front
        // index changes (which it won't between this load and the engine's
        // GL upload that follows). The MappedBuffer's pointer is stable for
        // its lifetime.
        let ptr = unsafe {
            let opt = &*slot.frame.get();
            opt.as_ref().map(|f| f.as_ptr())
        }?;
        Some((ptr, width, height))
    }
}

// ─── C-side hooks ──────────────────────────────────────────────────────────
//
// The runner can't link against the Rust dylib (it's an FFI plugin loaded
// at runtime by Dart), so we can't have C reference Rust symbols directly.
// Instead, Rust calls into C symbols at startup to register a callback;
// the FlPixelBufferTexture's `copy_pixels` invokes that pointer.

type CopyPixelsCallback =
    extern "C" fn(out_buffer: *mut *const u8, out_width: *mut u32, out_height: *mut u32) -> bool;

extern "C" {
    fn relink_video_texture_mark_dirty();
    fn relink_video_texture_get_id() -> i64;
    fn relink_video_texture_set_copy_pixels_callback(cb: CopyPixelsCallback);
}

// `cargo test` links a standalone test binary that never includes the
// Linux GTK runner (`linux/runner/relink_video_texture.cc`), which is the
// only place these three symbols are normally defined. Without a stub here,
// no test anywhere in this crate can link, regardless of what it covers.
#[cfg(test)]
#[allow(non_snake_case)]
mod runner_stubs {
    #[no_mangle]
    extern "C" fn relink_video_texture_mark_dirty() {}
    #[no_mangle]
    extern "C" fn relink_video_texture_get_id() -> i64 {
        0
    }
    #[no_mangle]
    extern "C" fn relink_video_texture_set_copy_pixels_callback(_cb: super::CopyPixelsCallback) {}
}

/// The function pointer we hand to C. Has C ABI so we can pass its address
/// across the FFI boundary as a `CopyPixelsCallback`. Not exported by name
/// (no `#[no_mangle]`) — C resolves it only through the registered pointer.
extern "C" fn rust_copy_pixels(
    out_buffer: *mut *const u8,
    out_width: *mut u32,
    out_height: *mut u32,
) -> bool {
    let Some((ptr, w, h)) = VIDEO_TEXTURE.current() else {
        return false;
    };
    // SAFETY: caller provides valid out pointers per the C contract.
    unsafe {
        *out_buffer = ptr;
        *out_width = w;
        *out_height = h;
    }
    true
}

/// Called once from the crate's `#[frb(init)]` hook (in `simple.rs`)
/// to install the `copy_pixels` callback. By then the runner's `activate`
/// has already registered the texture, so it's safe to have the C side
/// start delegating reads to us.
pub(crate) fn install_copy_pixels_callback() {
    unsafe {
        relink_video_texture_set_copy_pixels_callback(rust_copy_pixels);
    }
}

// ─── FRB API ───────────────────────────────────────────────────────────────

/// Returns the Flutter texture id registered by the runner. Returns 0 until
/// registration has completed; Dart should poll or retry briefly at startup.
#[flutter_rust_bridge::frb(sync)]
pub fn get_video_texture_id() -> i64 {
    // SAFETY: the C function returns a plain i64.
    unsafe { relink_video_texture_get_id() }
}

#[cfg(test)]
mod tests {
    use super::*;

    // An owned RGBA frame (openh264 fallback) must expose a readable pointer
    // to the exact bytes just like the gst path — the compositor reads through
    // it, so a wrong pointer/dims here is a black or garbled remote screen.
    #[test]
    fn owned_rgba_frame_is_read_back_through_the_texture_pointer() {
        let tex = VideoTexture {
            slots: [Slot::new(), Slot::new()],
            front: AtomicU8::new(0),
            has_data: AtomicBool::new(false),
        };
        assert!(tex.current().is_none(), "no data before first publish");

        let pixels: Vec<u8> = (0..(2 * 2 * 4)).map(|i| i as u8).collect();
        tex.publish_owned_rgba(pixels.clone(), 2, 2);

        let (ptr, w, h) = tex.current().expect("frame present after publish");
        assert_eq!((w, h), (2, 2));
        let read = unsafe { std::slice::from_raw_parts(ptr, pixels.len()) };
        assert_eq!(read, pixels.as_slice());
    }

    // Publishing again flips to the other slot; the previous owned buffer is
    // dropped only after the front pointer moves off it (double-buffering).
    #[test]
    fn second_publish_flips_front_and_reads_new_pixels() {
        let tex = VideoTexture {
            slots: [Slot::new(), Slot::new()],
            front: AtomicU8::new(0),
            has_data: AtomicBool::new(false),
        };
        tex.publish_owned_rgba(vec![1u8; 16], 2, 2);
        let front_a = tex.front.load(Ordering::Acquire);
        tex.publish_owned_rgba(vec![2u8; 16], 2, 2);
        let front_b = tex.front.load(Ordering::Acquire);
        assert_ne!(front_a, front_b, "front index must flip between publishes");

        let (ptr, _, _) = tex.current().unwrap();
        let read = unsafe { std::slice::from_raw_parts(ptr, 16) };
        assert!(read.iter().all(|&b| b == 2), "reads the most recent frame");
    }
}
