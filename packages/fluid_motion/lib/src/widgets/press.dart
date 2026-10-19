import 'package:flutter/widgets.dart';

import '../foundation/springs.dart';
import '../tokens.dart';

/// A shared press spring. Use it when several layers should be pressed as
/// one (e.g. a shape's background and its content in separate layers).
class PressSpring {
  PressSpring({
    required TickerProvider vsync,
    this.pressedScale = 0.96,
    SpringDescription? down,
    SpringDescription? up,
  })  : scale = AnimationController.unbounded(vsync: vsync, value: 1),
        _down = down ?? _defaultDown,
        _up = up ?? _defaultUp;

  final AnimationController scale;
  final double pressedScale;
  final SpringDescription _down, _up;

  static final _defaultDown =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 900, ratio: 1);
  static final _defaultUp =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 0.5);

  void press(bool down) => scale.springTo(
        down ? pressedScale : 1,
        down ? _down : _up,
        velocity: scale.velocity,
      );

  void dispose() => scale.dispose();
}

/// Squeezes on touch and springs back on release. Uses a Listener, so it
/// does not compete with the children's gestures. With a shared [spring]
/// several layers follow the same press; [listen] = false means the layer
/// only follows along and does not react to touch itself.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.96,
    this.spring,
    this.listen = true,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;
  final PressSpring? spring;
  final bool listen;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  PressSpring? _own;
  PressSpring get _spring => widget.spring ?? (_own ??= _createSpring());

  PressSpring _createSpring() {
    final tokens = MotionScope.of(context);
    return PressSpring(
      vsync: this,
      pressedScale: widget.pressedScale,
      down: tokens.pressDown,
      up: tokens.pressUp,
    );
  }

  void _press(bool down) {
    if (widget.enabled) _spring.press(down);
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaled = ScaleTransition(scale: _spring.scale, child: widget.child);
    if (!widget.listen) return scaled;
    return Listener(
      onPointerDown: (_) => _press(true),
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: scaled,
    );
  }
}
