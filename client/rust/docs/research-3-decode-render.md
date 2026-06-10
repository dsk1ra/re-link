# Research 3: Efficient Decode and Flutter Rendering

## Current Pipeline Analysis

### Receiver Decode Path
```
RTP → SampleBuilder (max_late=512) → H264Packet depacketizer
  → openh264::Decoder::decode(&nal_bytes)
  → DecodedYUV → write_rgba8(&mut rgba_vec)    ← CPU YUV→RGBA
  → push_video_frame(bus, rgba, w, h)            ← StreamSink
  → Flutter Dart: RawVideoFrame { data: Uint8List, width, height }
  → VideoFrameData → decodeImageFromPixels       ← CPU→GPU upload
  → ui.Image (GPU texture) → CustomPaint → screen
```

### Identified Bottlenecks

1. **OpenH264 write_rgba8**: Software YUV→RGBA conversion on CPU. At 1080p
   (~6.2M pixels), benchmarks show ~1.36ms per frame on modern CPUs (with
   NASM/native target). Without `target-cpu=native`, this can be 3-4x slower
   (~4-5ms). For 30fps that's 15% of frame budget on conversion alone.

2. **Per-frame Vec allocation**: `vec![0u8; width * height * 4]` allocates
   ~8MB per 1080p frame. At 30fps = 240MB/s of allocations + GC pressure.

3. **StreamSink data copy**: The `RawVideoFrame { data: Vec<u8> }` is
   serialized across the FFI boundary. FRB v2 uses zero-copy for `Vec<u8>`
   in async mode via `Dart_PostCObject` — the Rust Vec's backing memory is
   transferred to Dart without copying, and freed when Dart's GC collects
   the Uint8List. This means the StreamSink path should already be zero-copy
   for the video data. **Not a bottleneck.**

4. **decodeImageFromPixels**: This is the biggest Flutter-side bottleneck.
   It takes raw RGBA bytes on CPU, uploads them to a GPU texture, and returns
   a `ui.Image`. The upload involves:
   - Dart copies bytes into an internal buffer
   - Engine creates an OpenGL/Vulkan texture
   - Engine uploads pixel data to GPU
   - Returns ui.Image handle
   
   At 720p this takes ~5ms, at 1080p ~8-10ms. At 30fps, this alone
   consumes 25-30% of frame budget.

5. **`_decoding` guard drops frames**: The `RawVideoFrameView` widget has a
   boolean guard `_decoding` that drops all incoming frames while the previous
   `decodeImageFromPixels` is still running. If decode+upload takes 10ms and
   frames arrive every 33ms, ~30% of frames are dropped. This is actually
   correct behavior (prevents frame queue buildup), but it means the effective
   display rate is lower than the source rate.

## Research Findings

### A. Hardware H.264 Decoding (VAAPI)

**cros-codecs** supports VAAPI-accelerated H.264 decoding. The decoded output
is a VA surface (GPU memory) in NV12 format. Benefits:
- Decode happens entirely on GPU: ~0.5ms for 1080p vs ~5-10ms software
- Output is already a GPU surface — no CPU→GPU upload needed
- Eliminates `write_rgba8` CPU conversion entirely

**Challenge**: Getting the decoded GPU surface into Flutter's rendering pipeline.
Options:
1. **FlTextureGL**: Register a native OpenGL texture with Flutter's texture
   registrar. The VAAPI decoded surface can be exported as an EGL image, then
   bound as a GL texture. Flutter renders it via the `Texture` widget.
2. **DMA-BUF → EGL → FlTextureGL**: VAAPI surface → DMA-BUF export →
   EGLImage → GL texture → FlTextureGL. Entire path stays on GPU.

**Risk**: FlTextureGL has had regressions in Flutter 3.9.x and 3.22.x. The
API is stable but the implementation has bugs. Flutter 3.44 (current) should
have fixes, but needs testing.

### B. Optimized Software Decode Pipeline

If hardware decode is too risky/complex, optimize the software path:

1. **Keep YUV, skip RGBA conversion on Rust side**: Instead of `write_rgba8`,
   send the raw I420 planes to Flutter and do the conversion on GPU via a
   shader or via `decodeImageFromPixels` with YUV format support.
   
   **Problem**: Flutter's `decodeImageFromPixels` only accepts `PixelFormat.rgba8888`
   and `PixelFormat.bgra8888`. There is no YUV input option. So YUV→RGBA
   conversion must happen somewhere before Flutter.

2. **Use libyuv-style SIMD conversion**: The `yuv` crate used on the encode
   side supports SIMD-accelerated YUV↔RGBA conversion. OpenH264's
   `write_rgba8` is also SIMD-capable when compiled with `target-cpu=native`.
   Ensure this compiler flag is set.

3. **Reuse decode buffers**: Pre-allocate the RGBA buffer once and reuse it
   across frames. Replace `vec![0u8; w*h*4]` with a persistent buffer that's
   only reallocated on dimension change.

4. **decodeImageFromPixels → ImageDescriptor**: The modern Flutter API path:
   ```dart
   final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
   final descriptor = ui.ImageDescriptor.raw(
     buffer, width, height, ui.PixelFormat.rgba8888,
   );
   final codec = await descriptor.instantiateCodec();
   final frame = await codec.getNextFrame();
   final image = frame.image;
   ```
   This may be slightly faster as it uses the newer engine path, but the
   fundamental CPU→GPU upload cost remains the same.

### C. Flutter Texture Widget (Native Texture Path)

The optimal path for video rendering in Flutter on Linux:

1. **Native side** (C/Rust via FFI): Register an OpenGL texture with Flutter's
   `FlTextureRegistrar`. Implement `FlTextureGL` subclass that provides the
   OpenGL texture name.

2. **When a new frame arrives**: Upload RGBA data to the GL texture (or if using
   VAAPI, the decoded surface is already a GL texture). Call
   `fl_texture_registrar_mark_texture_frame_available()`.

3. **Flutter side**: Use `Texture(textureId: id)` widget. Flutter composites
   the native texture directly — no `decodeImageFromPixels`, no CPU→GPU copy
   for the widget layer.

**Benefits**:
- Eliminates `decodeImageFromPixels` entirely
- If combined with VAAPI decode, the entire path is GPU-only
- Flutter's Impeller renderer (default on Linux in 3.44) efficiently
  composites external textures

**Challenges**:
- Requires C native plugin code for Linux (FlTextureGL registration)
- flutter_rust_bridge can't directly register native textures — needs a thin
  C/C++ layer in the Linux runner
- More complex architecture

### D. Flutter Rendering: Current Approach Analysis

The current `RawVideoFrameView` uses `CustomPaint` with `canvas.drawImageRect`.
This is efficient once you have a `ui.Image` — the bottleneck is creating the
`ui.Image` from raw pixels, not the rendering itself.

Flutter 3.44 uses Impeller by default on Linux, which provides consistent
rendering performance. The `CustomPaint` approach is fine — the widget is
not the bottleneck.

## Performance Budget Analysis (1080p @ 30fps)

### Frame budget: 33ms

| Stage | Current (est.) | Optimized SW | GPU Path |
|-------|---------------|-------------|----------|
| H.264 decode | 5-10ms | 3-5ms (NASM) | <1ms (VAAPI) |
| YUV→RGBA | 1.4-5ms | 1-2ms (SIMD) | 0ms (GPU shader) |
| Vec alloc | 0.5-1ms | ~0ms (reuse) | 0ms |
| Rust→Dart FFI | ~0ms (zero-copy) | ~0ms | ~0ms |
| decodeImageFromPixels | 5-10ms | 5-10ms | 0ms (Texture widget) |
| **Total** | **12-26ms** | **9-17ms** | **<1ms** |

The GPU path is dramatically faster but requires VAAPI + native texture
registration. The optimized software path brings it within budget but with
little headroom.

## Key Recommendations

### Quick Wins (no architecture change)
1. **Compile with `target-cpu=native`** for 2-3x faster YUV→RGBA conversion
2. **Reuse RGBA decode buffer** — allocate once, reuse per frame
3. **Use `ImmutableBuffer.fromUint8List` path** — minor improvement

### Medium Effort
4. **FlTextureGL native texture** — eliminate `decodeImageFromPixels` entirely.
   Requires ~200 lines of C in the Linux runner, but halves the render latency.
5. **Double-buffer decode** — decode frame N+1 while frame N is being uploaded
   to GPU. Overlap CPU work with GPU work.

### Full GPU Pipeline (future, aligns with Portal plan)
6. **VAAPI decode + FlTextureGL**: Decode on GPU, render on GPU, zero CPU
   involvement for video. Combined with VAAPI encode on the sender side,
   the entire screen share path is GPU-accelerated end-to-end.

## Sources

- [openh264-rs benchmarks](https://docs.rs/openh264/latest/openh264/)
- [Flutter Texture widget on Linux](https://github.com/flutter/flutter/issues/64188)
- [FlTextureGL API](https://api.flutter.dev/linux-embedder/fl__texture__gl_8cc.html)
- [decodeImageFromPixels latency](https://github.com/flutter/flutter/issues/173016)
- [Flutter external texture rendering](https://www.alibabacloud.com/blog/flutter-analysis-and-practice-same-layer-external-texture-rendering_596580)
- [cros-codecs VAAPI decode](https://github.com/chromeos/cros-codecs)
- [FRB zero-copy](https://cjycode.com/flutter_rust_bridge/guides/types/translatable/zero-copy)
- [ImmutableBuffer API](https://api.flutter.dev/flutter/dart-ui/ImmutableBuffer-class.html)
