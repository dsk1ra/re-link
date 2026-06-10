# Research 1: Efficient PipeWire Screen Capture in Rust

## Current Pipeline Analysis

The current pipeline in RE:LINK follows this path:

```
PipeWire (ScreenCast portal) → RGBA frame (xcap) → FrameSlot (std::Mutex)
  → encode thread takes frame → xxh3 hash (skip static) → bilinear resize
  → RGBA→I420 (yuv crate) → OpenH264 encode → NAL bytes
  → mpsc channel → TrackLocalStaticSample::write_sample → RTP
```

### Identified Bottlenecks

1. **Format conversion waste**: PipeWire delivers RGB/RGBA/RGBx/BGRx. The encoder
   needs I420. The pipeline does: `compositor GPU framebuffer → (GPU readback to CPU
   RGBA) → CPU resize RGBA → CPU RGBA→I420 → CPU H.264 encode`. Two unnecessary
   CPU-intensive transformations.

2. **Per-frame allocation in xcap**: The `process` callback in
   `wayland_video_recorder.rs` does `.to_vec()` on every frame, allocating
   `width × height × 4` bytes (~8MB at 1080p) each time. At 30fps that's 240MB/s
   of allocations.

3. **No DMA-BUF support**: The xcap PipeWire integration only handles MemFd/MemPtr
   buffer types. DMA-BUF would allow the GPU framebuffer to be shared without CPU
   readback — critical for a GPU-side encode path.

4. **FrameSlot mutex contention**: Capture thread writes to `Arc<Mutex<Option<RawFrame>>>`,
   encode thread reads it. The encode thread may hold the mutex during slow hash+resize+encode,
   causing capture thread to block.

5. **OpenH264 limitations for screen content**: The warnings `AdaptiveQuant(1) is not
   supported yet for screen content` and `BackgroundDetection(1) is not supported yet
   for screen content` confirm OpenH264 disables these features internally. More
   critically, OpenH264 is a software-only, single-threaded Baseline profile encoder
   that struggles with text-heavy screen content. It has known issues with dramatic FPS
   drops on text-heavy scenes (cisco/openh264#2443).

## Research Findings

### A. DMA-BUF Zero-Copy Capture

PipeWire supports three buffer types for screen capture:
- **MemPtr**: Direct pointer to shared memory (current xcap approach via `.data()`)
- **MemFd**: File descriptor to shared memory region
- **DMA-BUF** (`SPA_DATA_DmaBuf`): GPU buffer file descriptor — zero CPU copy

GNOME Mutter and KDE KWin both support DMA-BUF delivery via the ScreenCast portal
since ~2020. The compositor renders to a GPU framebuffer and passes the DMA-BUF fd
to PipeWire; the consumer can import it directly into their GPU context (EGL, Vulkan)
without any CPU-side readback.

**Key insight**: With DMA-BUF, the captured frame never touches CPU memory. Combined
with VAAPI hardware encoding, the entire path stays on GPU:
`Compositor GPU → DMA-BUF → VAAPI encode → H.264 NALs (to CPU for RTP only)`.

### B. Format Negotiation

The current xcap code negotiates ONLY RGB formats:
```rust
VideoFormat::RGB,
VideoFormat::RGBA,
VideoFormat::RGBx,
VideoFormat::BGRx,
// VideoFormat::YUY2,  // commented out
// VideoFormat::I420,  // commented out
```

PipeWire compositors can deliver various formats. Requesting I420 or NV12 directly
would eliminate the RGBA→I420 CPU conversion (~5-10ms at 1080p). However:
- **GNOME Mutter** currently only delivers RGB/RGBA via ScreenCast portal DMA-BUFs.
  Its internal rendering pipeline uses GPU textures in RGBA.
- **KDE KWin** similarly delivers RGBA/BGRA.
- **Wlroots (Sway)** delivers whatever the compositor's render format is, typically RGBA.

**Conclusion**: Requesting I420 from the compositor won't help — they all output RGBA.
The conversion must happen somewhere, and the question is: CPU or GPU?

### C. Hardware Encoding (VAAPI)

VAAPI provides GPU-accelerated H.264 encoding via `/dev/dri/renderD128`. The pipeline:
1. Import DMA-BUF as VA surface (zero-copy)
2. GPU does RGBA→NV12 color space conversion internally
3. GPU encodes H.264 in hardware
4. Read back encoded NAL bitstream (tiny compared to raw frames)

**Rust crates available**:
- `cros-libva` (BSD-3): Safe Rust bindings to libva. Used in ChromeOS but portable.
- `cros-codecs`: Higher-level encode/decode API on top of cros-libva. Supports H.264
  VAAPI encoding.

**Compatibility**: Intel (Sandy Bridge+), AMD (GCN+), NVIDIA via nvidia-vaapi-driver.
Covers ~95% of desktop Linux GPUs made in the last 10 years.

### D. Software Encoder Alternatives

If sticking with software encoding (e.g., for VMs or GPUs without VAAPI):
- **x264** (`x264` crate): Much faster than OpenH264, supports multi-threading,
  `ultrafast` preset with `zerolatency` tune. The gold standard for real-time
  software H.264 encoding.
- **OpenH264 with NASM**: The `openh264` crate gains up to 3x speed with NASM
  assembly optimizations enabled.
- **SVT-AV1**: Newer, more efficient codec but requires AV1 decode support on
  the receiver.

### E. Existing Rust Libraries for PipeWire Capture

- **wlx-capture**: Supports PipeWire (MemFd, MemPtr, DmaBuf), Wlr-Dmabuf, XSHM.
  Channel-based frame delivery. Highly experimental but demonstrates the pattern.
- **lamco-pipewire**: DMA-BUF zero-copy support, format negotiation, cursor
  extraction. More recent (2026).
- **scap**: Cross-platform screen capture. Linux support via PipeWire.

## Recommended Architecture

### Tier 1: GPU pipeline (optimal, when VAAPI available)
```
ScreenCast portal → PipeWire stream (DMA-BUF) → VAAPI surface import
  → GPU color conversion (RGBA→NV12) → GPU H.264 encode
  → NAL bitstream readback → RTP packetization
```
- **Zero CPU copies** for the entire frame path
- GPU handles color conversion + encode
- Only NAL bytes (1-50KB/frame) cross GPU→CPU boundary
- ~1-3ms encode time for 1080p on modern Intel/AMD

### Tier 2: Optimized software pipeline (fallback)
```
ScreenCast portal → PipeWire stream (MemPtr/MemFd, avoid .to_vec())
  → ring buffer (no mutex) → RGBA→I420 (SIMD, libyuv-style)
  → x264 ultrafast/zerolatency → NAL → RTP
```
- Reuse frame buffers to avoid per-frame allocation
- Replace OpenH264 with x264 for 2-5x better speed/quality tradeoff
- Use lock-free triple buffering instead of `Mutex<Option<RawFrame>>`

### Tier 3: Current pipeline with quick wins
- Enable NASM for OpenH264 (up to 3x speedup)
- Eliminate per-frame allocations in xcap process callback
- Request framerate hint matching target tier fps
- Use atomic swap instead of mutex for FrameSlot

## Sources

- [PipeWire DMA-BUF Sharing](https://docs.pipewire.org/page_dma_buf.html)
- [GNOME Mutter DMA-BUF screencast](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1939)
- [wlx-capture](https://github.com/galister/wlx-capture)
- [cros-libva](https://docs.rs/cros-libva)
- [cros-codecs](https://docs.rs/cros-codecs)
- [OpenH264 screen content issues](https://github.com/cisco/openh264/issues/2443)
- [OpenH264 Rust bindings](https://docs.rs/openh264/latest/openh264/)
- [OBS Studio PipeWire zero-copy](https://obsproject.com/forum/threads/experimental-zero-copy-screen-capture-on-linux.101262/)
- [lamco-pipewire](https://crates.io/crates/lamco-pipewire)
