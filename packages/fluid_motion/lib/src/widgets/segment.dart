import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../foundation/springs.dart';

/// The left and right edge of an indicator, each with its own spring. The
/// leading edge (in the direction of travel) is stiff, the trailing edge
/// soft, so the indicator stretches like a droplet and contracts again.
///
/// Values are in segment units: segment i spans from i to i+1.
class SegmentSpring {
  SegmentSpring({
    required TickerProvider vsync,
    required int index,
    this.stretchy = true,
    SpringDescription? lead,
    SpringDescription? trail,
  })  : _index = index,
        lead = lead ?? _defaultLead,
        trail = trail ?? _defaultTrail,
        _left = AnimationController.unbounded(
          vsync: vsync,
          value: index.toDouble(),
        ),
        _right = AnimationController.unbounded(
          vsync: vsync,
          value: index + 1.0,
        );

  final AnimationController _left, _right;
  int _index;

  /// false = the indicator jumps directly (e.g. for "Reduce motion").
  bool stretchy;

  /// The leading edge's spring (stiff) and the trailing edge's (soft).
  SpringDescription lead, trail;

  static final _defaultLead =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 700, ratio: 0.7);
  static final _defaultTrail =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 240, ratio: 0.8);

  late final Listenable listenable = Listenable.merge([_left, _right]);

  double get left => _left.value;
  double get right => _right.value;
  double get center => (left + right) / 2;
  int get index => _index;

  void moveTo(int index) {
    if (index == _index) return;
    final forward = index > _index;
    _index = index;
    final l = index.toDouble(), r = index + 1.0;
    if (!stretchy) {
      _left.value = l;
      _right.value = r;
      return;
    }
    _left.springTo(l, forward ? trail : lead, velocity: _left.velocity);
    _right.springTo(r, forward ? lead : trail, velocity: _right.velocity);
  }

  void dispose() {
    _left.dispose();
    _right.dispose();
  }
}

/// Paints a [SegmentSpring] as a pill (or a rounded rect with [radius]).
/// When stretched it gets slightly lower (squash & stretch). Repaints
/// without rebuilding.
class SegmentIndicatorPainter extends CustomPainter {
  SegmentIndicatorPainter({
    required this.segments,
    required this.count,
    required this.color,
    this.inset = 4,
    this.radius,
  }) : super(repaint: segments.listenable);

  final SegmentSpring segments;
  final int count;
  final Color color;
  final double inset;

  /// Corner radius; null = a pill (half the height).
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final seg = size.width / count;
    final x0 = segments.left * seg + inset;
    final x1 = segments.right * seg - inset;
    final width = math.max(x1 - x0, 1.0);
    final rest = seg - inset * 2;
    final fullHeight = size.height - inset * 2;
    final height =
        fullHeight * math.pow(rest / width, 0.25).toDouble().clamp(0.8, 1.0);
    final cy = size.height / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(
        x0,
        cy - height / 2,
        x0 + width,
        cy + height / 2,
        Radius.circular(radius ?? height / 2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(SegmentIndicatorPainter old) =>
      old.segments != segments ||
      old.count != count ||
      old.color != color ||
      old.inset != inset ||
      old.radius != radius;
}
