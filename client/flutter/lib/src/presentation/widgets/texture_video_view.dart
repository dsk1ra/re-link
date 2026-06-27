import 'package:flutter/material.dart';

import 'package:application/src/rust/api/video_texture.dart' as rust_texture;

/// Zero-copy receiver video display.
///
/// Pixel data lives in a Rust-side double buffer; the GTK runner registers
/// a `FlPixelBufferTexture` subclass whose `copy_pixels` callback reads
/// straight from that buffer. The Flutter compositor uploads to a GL
/// texture and composites it — no `Image.memory`, no per-frame `setState`,
/// no pixel bytes ever touch the Dart isolate.
///
/// The texture is registered once at app startup from `my_application.cc`.
/// The id is published into the Rust crate and exposed here via the
/// FRB-sync `getVideoTextureId()` getter.
class TextureVideoView extends StatelessWidget {
  const TextureVideoView({
    super.key,
    this.sourceWidth,
    this.sourceHeight,
    this.fit = BoxFit.contain,
  });

  /// Source frame dimensions. When both are provided and positive the
  /// texture is laid out at the correct aspect ratio using [fit] (default
  /// `BoxFit.contain`). When unknown the texture stretches to fill its
  /// parent.
  final double? sourceWidth;
  final double? sourceHeight;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final id = rust_texture.getVideoTextureId();
    if (id == 0) {
      // Texture not registered yet (very early in startup, or running on a
      // platform where the runner doesn't register it). Nothing to draw —
      // an empty SizedBox keeps the layout from collapsing while the
      // surrounding widget keeps polling on rebuild.
      return const SizedBox.shrink();
    }

    final texture = Texture(textureId: id.toInt());
    final sw = sourceWidth;
    final sh = sourceHeight;
    if (sw != null && sh != null && sw > 0 && sh > 0) {
      // Use LayoutBuilder to compute the exact layout bounds that
      // maintain the source aspect ratio within the available space.
      // We give the Texture widget those exact bounds so the engine
      // composites the platform texture at the correct proportions.
      // (FittedBox won't work here because it applies a visual
      // transform but the engine still stretches the texture to fill
      // the Texture widget's layout size.)
      return LayoutBuilder(
        builder: (context, constraints) {
          final parentSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final sourceSize = Size(sw, sh);
          final fitted = applyBoxFit(fit, sourceSize, parentSize);
          return Center(
            child: SizedBox(
              width: fitted.destination.width,
              height: fitted.destination.height,
              child: texture,
            ),
          );
        },
      );
    }
    // Dimensions unknown — fill the parent.
    return SizedBox.expand(child: texture);
  }
}
