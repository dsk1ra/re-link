import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps the remote video display and forwards pointer/keyboard input to the
/// host over the control channel (see `WebRTCManager.sendInputMouseMove` and
/// friends, and `input_inject.rs` on the receiving end).
///
/// Coordinates are normalized to [0,1] *within the actual video content*,
/// replicating `TextureVideoView`'s own letterbox math (`applyBoxFit`) so a
/// click lands on the same pixel the host sees, not the widget's raw bounds.
class RemoteInputCapture extends StatefulWidget {
  const RemoteInputCapture({
    super.key,
    required this.webrtcManager,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.child,
    required this.enabled,
    this.fit = BoxFit.contain,
  });

  final WebRTCManager webrtcManager;
  final double? sourceWidth;
  final double? sourceHeight;
  final BoxFit fit;
  final Widget child;

  /// When false, pointer/keyboard events pass through untouched instead of
  /// being forwarded to the host - lets the viewer use their own local
  /// shortcuts (Alt+Tab, typing elsewhere in the app) without also
  /// controlling the remote session. Off by default; the viewer opts in.
  final bool enabled;

  @override
  State<RemoteInputCapture> createState() => _RemoteInputCaptureState();
}

class _RemoteInputCaptureState extends State<RemoteInputCapture> {
  final FocusNode _focusNode = FocusNode();
  int _heldButtons = 0;
  Offset _lastNormalized = const Offset(0.5, 0.5);

  // Keyed by logical key so KeyUpEvent (which carries no `character`) can
  // send a matching release for whatever was pressed - real press/hold/
  // release semantics, so the host's own key-repeat-on-hold just works.
  final Map<LogicalKeyboardKey, ({int? unicode, String? named})> _pressed = {};

  @override
  void didUpdateWidget(RemoteInputCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _releaseEverythingHeld();
    }
  }

  @override
  void dispose() {
    if (widget.enabled) _releaseEverythingHeld();
    _focusNode.dispose();
    super.dispose();
  }

  /// Toggling input off (or tearing down the widget) mid-gesture must not
  /// leave a key or mouse button stuck down on the host - release whatever
  /// was physically still held.
  void _releaseEverythingHeld() {
    for (final held in _pressed.values) {
      widget.webrtcManager.sendInputKey(unicode: held.unicode, named: held.named, pressed: false);
    }
    _pressed.clear();
    if (_heldButtons != 0) {
      widget.webrtcManager.sendInputMouseButton(
        _lastNormalized.dx,
        _lastNormalized.dy,
        _buttonName(_heldButtons),
        false,
      );
      _heldButtons = 0;
    }
  }

  Offset _normalize(Offset local, Size box) {
    final sw = widget.sourceWidth;
    final sh = widget.sourceHeight;
    Size dest = box;
    Offset topLeft = Offset.zero;
    if (sw != null && sh != null && sw > 0 && sh > 0 && box.width > 0 && box.height > 0) {
      final fitted = applyBoxFit(widget.fit, Size(sw, sh), box);
      dest = fitted.destination;
      topLeft = Offset((box.width - dest.width) / 2, (box.height - dest.height) / 2);
    }
    if (dest.width <= 0 || dest.height <= 0) return const Offset(0.5, 0.5);
    final rel = local - topLeft;
    return Offset(
      (rel.dx / dest.width).clamp(0.0, 1.0),
      (rel.dy / dest.height).clamp(0.0, 1.0),
    );
  }

  String _buttonName(int buttons) {
    if (buttons & kSecondaryMouseButton != 0) return 'right';
    if (buttons & kMiddleMouseButton != 0) return 'middle';
    return 'left';
  }

  static String? _namedKeyFor(LogicalKeyboardKey key) {
    final names = {
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.numpadEnter: 'Enter',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.escape: 'Escape',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.arrowUp: 'ArrowUp',
      LogicalKeyboardKey.arrowDown: 'ArrowDown',
      LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
      LogicalKeyboardKey.arrowRight: 'ArrowRight',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      // Modifiers: sent as their own press/release, same as any other key.
      // The host composes chord state itself from real keycode order (see
      // input_inject.rs) - nothing extra to track here.
      LogicalKeyboardKey.controlLeft: 'ControlLeft',
      LogicalKeyboardKey.controlRight: 'ControlRight',
      LogicalKeyboardKey.shiftLeft: 'ShiftLeft',
      LogicalKeyboardKey.shiftRight: 'ShiftRight',
      LogicalKeyboardKey.altLeft: 'AltLeft',
      LogicalKeyboardKey.altRight: 'AltRight',
      LogicalKeyboardKey.metaLeft: 'MetaLeft',
      LogicalKeyboardKey.metaRight: 'MetaRight',
    };
    return names[key];
  }

  /// `character` is null whenever a modifier is held (e.g. Ctrl+C) - Flutter
  /// only fills it in for an unmodified press. Falls back to the logical
  /// key's own id, which Flutter defines as the key's unmodified Unicode
  /// codepoint for the ASCII printable range (`keyA`..`keyZ`, `digit0`..
  /// `digit9`, punctuation), so a chord's base letter still resolves.
  static int? _unmodifiedUnicodeFor(LogicalKeyboardKey key) {
    final id = key.keyId;
    return (id >= 0x20 && id <= 0x7e) ? id : null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final manager = widget.webrtcManager;

    if (event is KeyUpEvent) {
      final held = _pressed.remove(event.logicalKey);
      if (held == null) return KeyEventResult.ignored;
      manager.sendInputKey(unicode: held.unicode, named: held.named, pressed: false);
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent) {
      // The X server's own auto-repeat handles held keys once pressed.
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent) {
      final named = _namedKeyFor(event.logicalKey);
      final character = event.character;
      final unicode = named != null
          ? null
          : (character != null && character.isNotEmpty)
              ? character.runes.first
              : _unmodifiedUnicodeFor(event.logicalKey);
      if (named == null && unicode == null) return KeyEventResult.ignored;

      _pressed[event.logicalKey] = (unicode: unicode, named: named);
      manager.sendInputKey(unicode: unicode, named: named, pressed: true);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = Size(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (!widget.enabled) return;
              _focusNode.requestFocus();
              _heldButtons = event.buttons;
              final n = _lastNormalized = _normalize(event.localPosition, box);
              widget.webrtcManager
                  .sendInputMouseButton(n.dx, n.dy, _buttonName(event.buttons), true);
            },
            onPointerMove: (event) {
              if (!widget.enabled) return;
              final n = _lastNormalized = _normalize(event.localPosition, box);
              widget.webrtcManager.sendInputMouseMove(n.dx, n.dy);
            },
            onPointerUp: (event) {
              if (!widget.enabled) return;
              final n = _lastNormalized = _normalize(event.localPosition, box);
              widget.webrtcManager
                  .sendInputMouseButton(n.dx, n.dy, _buttonName(_heldButtons), false);
              _heldButtons = 0;
            },
            onPointerSignal: (event) {
              if (!widget.enabled) return;
              if (event is PointerScrollEvent) {
                final n = _normalize(event.localPosition, box);
                widget.webrtcManager.sendInputMouseScroll(n.dx, n.dy, event.scrollDelta.dy);
              }
            },
            child: widget.child,
          );
        },
      ),
    );
  }
}
