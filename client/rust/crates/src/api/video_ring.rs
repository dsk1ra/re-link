// Pre-allocated ring buffer for decoded video frames.
//
// Eliminates the per-frame FRB cost identified in Phase 0: instead of copying
// an 8 MB RGBA buffer across the Dart isolate boundary on every frame, the
// decoder writes into one of a small number of fixed-address ring slots and
// hands Dart only the slot's pointer + length + slot id. Dart wraps the
// pointer as a zero-copy `Uint8List` view, consumes the frame, then calls
// `release_video_frame` to mark the slot reusable.
//
// Slot states are held in a `[AtomicU8; N]` table so the producer (decoder)
// and consumer (Dart, via FFI) never share a lock. The producer claims a
// FREE slot via CAS → RUST_OWNS, writes, then publishes → DART_OWNS. Dart
// reads, then releases → FREE.

use once_cell::sync::Lazy;
use std::sync::atomic::{AtomicU8, Ordering};

/// Slot count. With 4 slots and a producer that drops frames when none are
/// free, a momentarily busy Dart consumer never blocks the decoder.
pub(crate) const RING_SLOTS: usize = 4;

/// Bytes per slot. Sized for 1920×1080 RGBA (= 8.3 MB). At 4 slots that's
/// ~33 MB resident, which is fine. Phase 2's NV12 transport would shrink
/// this to ~3 MB/slot.
pub(crate) const SLOT_BYTES: usize = 1920 * 1080 * 4;

const STATE_FREE: u8 = 0;
const STATE_RUST: u8 = 1;
const STATE_DART: u8 = 2;

pub(crate) struct VideoRing {
    slots: [Box<[u8]>; RING_SLOTS],
    states: [AtomicU8; RING_SLOTS],
}

// SAFETY: We hand out `&mut [u8]` only after a CAS from FREE→RUST_OWNS
// succeeds (one winner per slot per cycle). The slot stays exclusively
// Rust-owned until publish(), then exclusively Dart-owned until release().
// No two parties ever alias the same slot at the same time.
unsafe impl Send for VideoRing {}
unsafe impl Sync for VideoRing {}

pub(crate) static VIDEO_RING: Lazy<VideoRing> = Lazy::new(VideoRing::new);

impl VideoRing {
    fn new() -> Self {
        Self {
            slots: std::array::from_fn(|_| vec![0u8; SLOT_BYTES].into_boxed_slice()),
            states: std::array::from_fn(|_| AtomicU8::new(STATE_FREE)),
        }
    }

    /// Try to claim a FREE slot for the producer. Returns the slot index
    /// and an exclusive mutable view of its buffer, or `None` if every
    /// slot is currently in flight to Dart. Callers should drop the frame
    /// on `None`.
    pub(crate) fn claim(&self) -> Option<(u32, &mut [u8])> {
        for i in 0..RING_SLOTS {
            if self.states[i]
                .compare_exchange(STATE_FREE, STATE_RUST, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
            {
                // SAFETY: this thread just won the CAS to RUST_OWNS; the
                // slot's bytes are exclusively ours until publish().
                let buf = unsafe {
                    let ptr = self.slots[i].as_ptr() as *mut u8;
                    std::slice::from_raw_parts_mut(ptr, SLOT_BYTES)
                };
                return Some((i as u32, buf));
            }
        }
        None
    }

    /// Hand a written slot off to Dart.
    pub(crate) fn publish(&self, slot: u32) {
        let i = slot as usize;
        if i < RING_SLOTS {
            self.states[i].store(STATE_DART, Ordering::Release);
        }
    }

    /// Mark a slot reusable. Safe to call regardless of current state — used
    /// both by Dart via the FRB-sync release function and by the producer
    /// to abandon a slot whose downstream channel was full.
    pub(crate) fn release(&self, slot: u32) {
        let i = slot as usize;
        if i < RING_SLOTS {
            self.states[i].store(STATE_FREE, Ordering::Release);
        }
    }

    pub(crate) fn slot_addr(&self, slot: u32) -> i64 {
        let i = slot as usize;
        if i < RING_SLOTS {
            self.slots[i].as_ptr() as i64
        } else {
            0
        }
    }
}

/// Free a slot previously delivered to Dart over the video stream.
///
/// MUST be called after Dart is done reading the slot's bytes — for example
/// after `ui.decodeImageFromPixels` has copied the pixels into a Skia
/// image. Failing to call this leaks the slot; once all four slots leak the
/// decoder will drop every subsequent frame.
#[flutter_rust_bridge::frb(sync)]
pub fn release_video_frame(slot: u32) {
    VIDEO_RING.release(slot);
}
