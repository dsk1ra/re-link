import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class VideoFrameData {
  const VideoFrameData({
    required this.rgba,
    required this.width,
    required this.height,
    required this.release,
  });

  /// Zero-copy view onto a Rust-side ring-buffer slot. Valid only until
  /// `release()` is called; do NOT hold a reference past that point.
  final Uint8List rgba;
  final int width;
  final int height;

  /// Hands the slot back to Rust. MUST be called exactly once per frame —
  /// either after the bytes have been copied somewhere safe (e.g. into a
  /// Skia image via `ui.decodeImageFromPixels`) or immediately if the
  /// frame is being dropped.
  final void Function() release;
}

class RawVideoFrameView extends StatefulWidget {
  const RawVideoFrameView({
    super.key,
    required this.frameStream,
    this.fit = BoxFit.contain,
  });

  final Stream<VideoFrameData> frameStream;
  final BoxFit fit;

  @override
  State<RawVideoFrameView> createState() => _RawVideoFrameViewState();
}

class _RawVideoFrameViewState extends State<RawVideoFrameView> {
  StreamSubscription<VideoFrameData>? _subscription;
  ui.Image? _currentImage;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(RawVideoFrameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frameStream != widget.frameStream) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.frameStream.listen(_onFrame);
  }

  void _onFrame(VideoFrameData frame) async {
    // Dimension-only sentinel (len==0): no pixels to decode, and feeding an
    // empty buffer to decodeImageFromPixels with a nonzero size is invalid.
    if (frame.rgba.isEmpty) {
      frame.release();
      return;
    }
    if (_decoding || !mounted) {
      // Frame skipped — release the ring slot immediately so the decoder
      // can reuse it.
      frame.release();
      return;
    }
    _decoding = true;

    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        frame.rgba,
        frame.width,
        frame.height,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );

      final image = await completer.future;
      // Skia has copied the bytes into its own image; the ring slot is no
      // longer needed and can be recycled by the decoder.
      frame.release();

      if (!mounted) {
        image.dispose();
        return;
      }

      final old = _currentImage;
      setState(() => _currentImage = image);
      old?.dispose();
    } finally {
      _decoding = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _currentImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _currentImage;
    if (image == null) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: _VideoFramePainter(image: image, fit: widget.fit),
      size: Size.infinite,
    );
  }
}

class _VideoFramePainter extends CustomPainter {
  _VideoFramePainter({required this.image, required this.fit});

  final ui.Image image;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final fittedSizes = applyBoxFit(fit, src.size, size);
    final dst = Alignment.center.inscribe(fittedSizes.destination, Offset.zero & size);

    canvas.drawImageRect(image, src, dst, Paint());
  }

  @override
  bool shouldRepaint(_VideoFramePainter oldDelegate) =>
      oldDelegate.image != image;
}
