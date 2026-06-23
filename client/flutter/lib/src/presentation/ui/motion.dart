import 'package:flutter/animation.dart';

/// Motion is subtle and functional everywhere, with one expressive
/// exception: the session-establishment handshake.
class AppMotion {
  /// Hover, press.
  static const Duration micro = Duration(milliseconds: 120);

  /// Panels, fades.
  static const Duration standard = Duration(milliseconds: 200);

  /// Sheets, large transitions.
  static const Duration large = Duration(milliseconds: 320);

  /// The choreographed handshake budget. Skippable, never blocks.
  static const Duration handshake = Duration(milliseconds: 1200);

  /// Decelerate. No bounce, no spring, no overshoot.
  static const Curve easing = Cubic(0.2, 0, 0, 1);
}
