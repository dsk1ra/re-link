# Screen Share Performance: Implementation Plan

Compiled from three research areas:
- [Research 1: PipeWire Capture](research-1-pipewire-capture.md)
- [Research 2: WebRTC Transport](research-2-webrtc-transport.md)
- [Research 3: Decode & Render](research-3-decode-render.md)

---

## Problem Statement

Screen sharing delivers sub-optimal framerate with OpenH264 warnings:
```
[OpenH264] AdaptiveQuant(1) is not supported yet for screen content, auto turned off
[OpenH264] BackgroundDetection(1) is not supported yet for screen content, auto turned off
```

Priority: **fps > resolution > quality > frame loss**

## Root Cause Summary

The pipeline has bottlenecks at every stage:

| Stage | Issue | Impact |
|-------|-------|--------|
| **Capture** | Per-frame 8MB allocation in xcap | 240MB/s alloc pressure at 30fps |
| **Capture** | No DMA-BUF, CPU-only pixel access | Unnecessary GPU→CPU readback |
| **Encode** | OpenH264 without NASM assembly | Up to 3x slower than optimized |
| **Encode** | OpenH264 struggles with text content | Known encoder limitation |
| **Encode** | RGBA→I420 conversion on CPU | 1-5ms per frame at 1080p |
| **Transport** | SampleBuilder ring buffer bugs | Keyframe corruption, visual artifacts |
| **Transport** | No PLI feedback on decode error | Up to 1s recovery after corruption |
| **Decode** | OpenH264 software decode | 5-10ms per frame |
| **Decode** | YUV→RGBA on CPU (write_rgba8) | 1-5ms per frame |
| **Decode** | Per-frame 8MB Vec allocation | Another 240MB/s alloc pressure |
| **Render** | decodeImageFromPixels CPU→GPU | 5-10ms per frame at 1080p |

**Total estimated per-frame cost: 12-26ms** (budget: 33ms at 30fps)

---

## Implementation Phases

### Phase 0: Quick Wins (1-2 hours, no architecture change)

These fixes require minimal code changes and address the most impactful issues.

#### 0.1 Install NASM and enable assembly optimizations

NASM is **not installed** on the build machine. OpenH264 with `features = ["source"]`
compiles from source but falls back to pure C without NASM — up to **3x slower**.

```bash
# Fedora
sudo dnf install nasm
```

No code changes needed. The `openh264` crate auto-detects NASM at build time.
Run `cargo clean -p openh264-sys2 && cargo build --release` after installing.

**Expected impact**: 2-3x faster encode AND decode.

#### 0.2 Add `target-cpu=native` build flag

Create `/home/denys/projects/re-link/client/rust/.cargo/config.toml`:
```toml
[target.'cfg(target_arch = "x86_64")']
rustflags = ["-C", "target-cpu=native"]
```

Enables AVX2/SSE4 SIMD for the `yuv` crate's RGBA↔I420 conversion and for
OpenH264's internal SIMD paths. The `yuv` crate already has `fast_mode` feature
enabled but can't use AVX2 without this flag.

**Expected impact**: 2-3x faster color conversion.

#### 0.3 Reuse decode RGBA buffer

In `decode_incoming_track` (webrtc.rs:1196), replace per-frame allocation:
```rust
// Before:
let mut rgba = vec![0u8; width * height * 4];

// After: reuse buffer, only reallocate on dimension change
if rgba_buf.len() != width * height * 4 {
    rgba_buf.resize(width * height * 4, 0);
}
```

**Expected impact**: Eliminates 240MB/s allocation pressure on decode side.

#### 0.4 Suppress OpenH264 warnings

The `AdaptiveQuant` and `BackgroundDetection` warnings are harmless — OpenH264
already disables them internally for screen content. But they're noisy. These
are C-level warnings from the OpenH264 library and can't be suppressed from
Rust. They're informational only and not a performance issue themselves.

---

### Phase 1: Encoder Upgrade (2-4 hours)

OpenH264 is the weakest link in the pipeline. It's a Baseline-profile-only,
single-threaded, software encoder that struggles with text-heavy screen content
(the most common screen sharing scenario).

#### Option A: Switch to x264 (Recommended)

The `x264` crate provides Rust bindings to libx264, the industry-standard
H.264 encoder used by OBS, FFmpeg, and most streaming software.

**Advantages over OpenH264**:
- Multi-threaded encoding (uses all CPU cores)
- `ultrafast` preset: ~5x faster than OpenH264 at comparable quality
- `zerolatency` tune: eliminates lookahead latency
- Supports High profile (better compression than Baseline)
- Excellent screen content encoding (no degradation with text)

**Configuration**:
```
preset = ultrafast
tune = zerolatency
profile = baseline  (for WebRTC compatibility, or high if both sides support it)
rc = ABR with target bitrate from tier
keyint = fps (1s IDR interval)
threads = 0 (auto-detect)
```

**Dependency**: libx264 system library (Fedora: `sudo dnf install x264-devel`)

**Changes**:
- Add `x264 = "0.6"` to workspace Cargo.toml
- Rewrite `ensure_encoder` in screen_capture.rs to use x264
- Keep OpenH264 as fallback if x264 is not available

#### Option B: VAAPI Hardware Encode (Better, more complex)

Use `cros-libva` + `cros-codecs` for GPU-accelerated H.264 encoding.

**Advantages**:
- ~1-3ms encode time for 1080p (vs 10-20ms software)
- Frees CPU entirely for other work
- Can accept DMA-BUF input (zero-copy from PipeWire)

**Disadvantages**:
- Requires VAAPI-capable GPU (Intel Sandy Bridge+, AMD GCN+)
- More complex setup (libva, DRM device)
- Needs DMA-BUF capture path to get full benefit

**Recommendation**: Implement as Phase 3 (GPU pipeline), not here.

---

### Phase 2: Decode & Render Pipeline (3-5 hours)

#### 2.1 PLI feedback on decode error

When the decoder fails, request an immediate keyframe from the sender:

```rust
// In decode_incoming_track, after Err(e):
Err(e) => {
    tracing::warn!("H.264 decode error: {e}");
    // Send PLI to request keyframe
    // (requires access to the receiver's RTCP writer)
}
```

This requires wiring the RTCP feedback path. The `TrackRemote` doesn't
directly expose PLI sending — it needs to go through the PeerConnection's
RTCP writer. Check if webrtc-rs exposes `write_rtcp` on the PC.

**Expected impact**: Instant recovery from decode errors instead of waiting
up to 1 second for the next IDR.

#### 2.2 Custom H.264 depacketizer (replace SampleBuilder)

The SampleBuilder has known bugs with sequence number wrapping and visual
artifacts. Replace it with a stateful accumulator:

```rust
struct H264FrameAssembler {
    current_ts: u32,
    fragments: Vec<u8>,
    seen_start: bool,
}

impl H264FrameAssembler {
    fn push(&mut self, rtp: RtpPacket) -> Option<Vec<u8>> {
        // If timestamp changed, flush previous frame
        // Accumulate FU-A fragments for current timestamp
        // On marker bit, yield complete access unit
    }
}
```

**Expected impact**: Eliminates ring buffer corruption, handles large keyframes
correctly regardless of packet count.

#### 2.3 FlTextureGL native texture rendering

**This is the highest-impact single change for the render pipeline.**

Replace `decodeImageFromPixels` (5-10ms CPU→GPU upload per frame) with a
native OpenGL texture registered via Flutter's texture registrar.

**Implementation**:

1. **C plugin** (~100 lines in `linux/` runner):
   - Create `FlTextureGL` subclass
   - Register with `fl_texture_registrar_register_texture()`
   - Expose `update_texture(uint8_t* rgba, int width, int height)` via
     method channel or direct FFI
   - Call `fl_texture_registrar_mark_texture_frame_available()` on update

2. **Rust side**: Instead of pushing `RawVideoFrame` via StreamSink, write
   RGBA directly to the GL texture's pixel buffer via the C plugin FFI.

3. **Flutter side**: Replace `RawVideoFrameView` with `Texture(textureId: id)`.

**Expected impact**: Eliminates 5-10ms per frame of CPU→GPU upload. The GL
texture upload is typically <1ms because the Flutter engine can do it
asynchronously during its own render cycle.

**Risk**: FlTextureGL has had regressions. Test thoroughly on Flutter 3.44.

#### 2.4 Decode buffer reuse (from Phase 0.3)

Already covered in Phase 0.3. Combined with the FlTextureGL path, the decode
pipeline becomes:
```
NAL → openh264 decode → YUV → write_rgba8(reused_buf) → GL texture update → done
```

---

### Phase 3: Full GPU Pipeline (future, 1-2 weeks)

This is the endgame architecture that combines DMA-BUF capture, VAAPI
encode/decode, and native texture rendering for a fully GPU-accelerated
screen sharing path.

#### Sender Side
```
ScreenCast Portal → PipeWire (DMA-BUF) → VAAPI surface import
  → GPU RGBA→NV12 → VAAPI H.264 encode → NAL readback → RTP
```

#### Receiver Side
```
RTP → NAL reassembly → VAAPI H.264 decode → VA surface
  → DMA-BUF export → EGLImage → GL texture → FlTextureGL → Flutter
```

**Zero CPU involvement** for the entire video path. CPU only handles RTP
packet I/O (tiny packets, ~1KB each).

#### Dependencies
- `cros-libva` + `cros-codecs` for VAAPI encode/decode
- Custom PipeWire integration replacing vendored xcap (or modify xcap to
  negotiate DMA-BUF buffers)
- C/Rust FFI layer for EGLImage → FlTextureGL
- Fallback to software path for VMs and unsupported GPUs

---

## Implementation Priority

| Priority | Change | Effort | Impact |
|----------|--------|--------|--------|
| **P0** | Install NASM | 5 min | 2-3x faster encode/decode |
| **P0** | target-cpu=native | 5 min | 2-3x faster color conversion |
| **P0** | Reuse decode buffer | 15 min | Eliminate 240MB/s alloc |
| **P1** | x264 encoder | 2-4 hrs | 5x faster encode, better quality |
| **P1** | PLI feedback | 1-2 hrs | Instant error recovery |
| **P2** | FlTextureGL rendering | 4-6 hrs | Eliminate 5-10ms/frame render |
| **P2** | Custom depacketizer | 2-3 hrs | Eliminate SampleBuilder bugs |
| **P3** | VAAPI encode path | 1 week | <3ms encode, GPU-only |
| **P3** | VAAPI decode path | 1 week | <1ms decode, GPU-only |
| **P3** | DMA-BUF capture | 3-5 days | Zero-copy capture |

**Recommended order**: P0 first (30 minutes, massive impact), then P1 (half day),
then P2 (1 day), then P3 (future sprint).

## Expected Results After P0+P1

With NASM + target-cpu=native + x264 + buffer reuse:
- Encode: 10-20ms → 2-4ms (x264 ultrafast)
- Color conversion: 4-5ms → 1-2ms (SIMD)
- Decode: 5-10ms → 2-4ms (NASM)
- Alloc overhead: ~2ms → ~0ms
- **Total: ~5-10ms per frame** (comfortably within 33ms budget)

## Expected Results After P0+P1+P2

With FlTextureGL added:
- Render: 5-10ms → <1ms
- **Total: ~4-7ms per frame** (>75% headroom for 30fps)
