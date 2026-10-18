import 'dart:math' as math;
import 'dart:ui';

import 'shape.dart';

/// Where and how strongly two shapes are connected: [focus] is the point
/// where they are closest (the middle of the overlap if they overlap), and
/// [strength] goes from 0 (not connected) to 1 (touching or overlapping).
class GooeyContact {
  const GooeyContact(this.focus, this.strength, {this.gap = 0});
  final Offset focus;
  final double strength;

  /// The distance between the shapes' edges (0 when touching/overlapping).
  final double gap;

  static const none = GooeyContact(Offset.zero, 0, gap: double.infinity);

  /// The shortest distance between two rects (0 if they touch or overlap).
  static double boxGap(Rect a, Rect b) {
    final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
    final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
    return math.sqrt(dx * dx + dy * dy);
  }

  /// The point between two rects where they are closest (middle of the
  /// overlap, or of the gap between them).
  static Offset focusBetween(Rect a, Rect b) => Offset(
        (math.max(a.left, b.left) + math.min(a.right, b.right)) / 2,
        (math.max(a.top, b.top) + math.min(a.bottom, b.bottom)) / 2,
      );

  /// The gap between two shapes' edges and the point between them where
  /// they are closest – for any outline.
  ///
  /// Two rounded rects use the exact (and cheapest) rect calculation. Other
  /// shapes find their closest points by alternately projecting onto each
  /// other's edge along the distance fields: exact for convex shapes, a
  /// close approximation for the rest.
  static (double gap, Offset focus) measure(GooeyShape a, GooeyShape b) {
    if (a.isRoundedRect && b.isRoundedRect) {
      return (boxGap(a.rect, b.rect), focusBetween(a.rect, b.rect));
    }
    // Far apart: the bounding boxes are good enough and much cheaper.
    final box = boxGap(a.rect, b.rect);
    if (box > 64) return (box, focusBetween(a.rect, b.rect));

    var q = a.closestOnEdge(b.rect.center);
    var r = b.closestOnEdge(q);
    q = a.closestOnEdge(r);
    r = b.closestOnEdge(q);
    final focus = (q + r) / 2;
    // Overlapping when an edge point of one lies inside the other.
    if (b.distance(q.dx, q.dy) <= 0 || a.distance(r.dx, r.dy) <= 0) {
      return (0, focus);
    }
    return ((q - r).distance, focus);
  }

  /// [meetAt] is the gap at which the rects start to connect.
  static GooeyContact between(Rect a, Rect b, {required double meetAt}) =>
      _fromGap(boxGap(a, b), focusBetween(a, b), meetAt);

  /// Like [between], for any two shapes (see [measure]).
  static GooeyContact betweenShapes(
    GooeyShape a,
    GooeyShape b, {
    required double meetAt,
  }) {
    final (gap, focus) = measure(a, b);
    return _fromGap(gap, focus, meetAt);
  }

  static GooeyContact _fromGap(double gap, Offset focus, double meetAt) {
    if (gap >= meetAt) return GooeyContact(focus, 0, gap: gap);
    final t = (1 - gap / meetAt).clamp(0.0, 1.0);
    return GooeyContact(focus, t * t * (3 - 2 * t), gap: gap); // smoothstep
  }
}

/// What happened to a contact in the latest update.
enum ContactEvent { none, caught, released }

/// Watches when two shapes catch or release each other – with hysteresis,
/// so the contact does not flicker while the shapes hover at the threshold –
/// and how fast it happened ([speed], px/s). Generic: use it for anything
/// that should react to a collision or a separation.
class ContactTracker {
  ContactTracker({this.meetAt = 8, this.hysteresis = 0.75});

  double meetAt;
  double hysteresis;

  bool _connected = false;
  double _lastGap = double.infinity;
  int _lastMs = 0;
  final _clock = Stopwatch()..start();

  /// Whether the shapes are connected right now.
  bool get connected => _connected;

  /// How fast the gap changed at the latest update (px/s).
  double speed = 0;

  /// Update with the current gap between the shapes.
  ContactEvent update(double gap) {
    final now = _clock.elapsedMilliseconds;
    final dt = (now - _lastMs).clamp(1, 100) / 1000;
    speed = _lastGap.isFinite ? ((gap - _lastGap) / dt).abs() : 0.0;
    _lastGap = gap;
    _lastMs = now;

    if (!_connected && gap < meetAt - hysteresis) {
      _connected = true;
      return ContactEvent.caught;
    }
    if (_connected && gap > meetAt + hysteresis) {
      _connected = false;
      return ContactEvent.released;
    }
    return ContactEvent.none;
  }

  void reset() {
    _connected = false;
    _lastGap = double.infinity;
    speed = 0;
  }
}
