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
  /// they are closest – for any outline, including ones with holes (a ring)
  /// or notches (a star).
  ///
  /// Two rounded rects use the exact (and cheapest) rect calculation. Other
  /// shapes search for the point that is closest to both at once: where the
  /// larger of the two distances is smallest. At that point each distance
  /// is half the gap; if it is inside both, the shapes overlap. The search
  /// samples the area around both shapes and then refines, so it never
  /// reports a contact that is not there, and it does not get lost in a
  /// hole the way following one edge to the other can.
  ///
  /// Results are cached per pair of shapes (shapes are per-frame snapshots),
  /// so every painter in a frame shares one measurement.
  static (double gap, Offset focus) measure(GooeyShape a, GooeyShape b) {
    if (a.isRoundedRect && b.isRoundedRect) {
      return (boxGap(a.rect, b.rect), focusBetween(a.rect, b.rect));
    }
    final cachedA = _cache[a];
    if (cachedA != null && identical(cachedA.$1, b)) return cachedA.$2;
    final cachedB = _cache[b];
    if (cachedB != null && identical(cachedB.$1, a)) return cachedB.$2;
    final result = _search(a, b);
    _cache[a] = (b, result);
    return result;
  }

  static final _cache = Expando<(GooeyShape, (double, Offset))>();

  /// How far beyond the shapes the search looks (px). Gaps up to twice this
  /// are measured exactly; larger ones only matter as "far apart".
  static const _searchReach = 16.0;
  static const _samples = 20;

  static (double, Offset) _search(GooeyShape a, GooeyShape b) {
    final area = a.rect
        .inflate(_searchReach + a.maxBulge)
        .intersect(b.rect.inflate(_searchReach + b.maxBulge));
    if (area.width <= 0 || area.height <= 0) {
      return (boxGap(a.rect, b.rect), focusBetween(a.rect, b.rect));
    }
    double worse(double x, double y) =>
        math.max(a.distance(x, y), b.distance(x, y));

    // Coarse: a grid over the area both shapes can reach.
    final sx = area.width / _samples, sy = area.height / _samples;
    var best = double.infinity, bx = area.center.dx, by = area.center.dy;
    for (var j = 0; j <= _samples; j++) {
      final y = area.top + j * sy;
      for (var i = 0; i <= _samples; i++) {
        final x = area.left + i * sx;
        final v = worse(x, y);
        if (v < best) {
          best = v;
          bx = x;
          by = y;
        }
      }
    }
    // Fine: search around the best point with ever smaller steps.
    var step = math.max(sx, sy);
    for (var round = 0; round < 7; round++) {
      step /= 2;
      var cx = bx, cy = by;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final x = bx + dx * step, y = by + dy * step;
          final v = worse(x, y);
          if (v < best) {
            best = v;
            cx = x;
            cy = y;
          }
        }
      }
      bx = cx;
      by = cy;
    }
    final focus = Offset(bx, by);
    // Inside both: they overlap. Otherwise each distance is half the gap.
    return (best <= 0 ? 0.0 : 2 * best, focus);
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
