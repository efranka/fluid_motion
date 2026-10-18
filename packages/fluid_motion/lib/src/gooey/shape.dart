import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'contour.dart';
import 'geometry.dart';

/// A local, organic deformation of a shape: the edge is pushed out (positive
/// [amplitude]) or pulled in (negative) around [center]. Animate the
/// amplitude with a loose spring and the shape "blobs" at that spot.
class GooeyRipple {
  const GooeyRipple(this.center, this.amplitude, {this.radius = 22});
  final Offset center;
  final double amplitude; // px
  final double radius; // px
}

/// One shape in one frame: where it is ([rect]), its colour, its outline
/// ([geometry], a pill by default) and any [ripples] deforming it.
///
/// Shapes are cheap, immutable snapshots – a new one is made every frame.
class GooeyShape {
  GooeyShape(
    this.rect,
    this.color, {
    double? radius,
    GooeyGeometry? geometry,
    List<GooeyRipple> ripples = const [],
  })  : geometry = geometry ?? GooeyRoundedRect(radius: radius),
        ripples = List.unmodifiable(ripples) {
    _sdf = this.geometry.resolve(rect);
    final rr = _sdf.roundedRectRadius;
    _rr = rr;
    if (rr != null) {
      // Fast path for rounded rects: inline distance, no virtual call.
      _cx = rect.center.dx;
      _cy = rect.center.dy;
      _hx = rect.width / 2 - rr;
      _hy = rect.height / 2 - rr;
    }
    // Ripples are packed into a number array: cx, cy, amplitude, 1/r².
    _rip = Float64List(this.ripples.length * 4);
    var bulge = 0.0, strongest = 0.0;
    for (var i = 0; i < this.ripples.length; i++) {
      final r = this.ripples[i];
      _rip[4 * i] = r.center.dx;
      _rip[4 * i + 1] = r.center.dy;
      _rip[4 * i + 2] = r.amplitude;
      _rip[4 * i + 3] = 1 / (r.radius * r.radius);
      if (r.amplitude > 0) bulge += r.amplitude;
      strongest = math.max(strongest, r.amplitude.abs());
    }
    maxBulge = bulge;
    maxAmplitude = strongest;
  }

  /// The shape's bounding box (before any ripples).
  final Rect rect;
  final Color color;
  final GooeyGeometry geometry;
  final List<GooeyRipple> ripples;

  // Precomputed so distance() never allocates – it runs thousands of times
  // per frame.
  late final GooeySdf _sdf;
  double? _rr;
  double _cx = 0, _cy = 0, _hx = 0, _hy = 0;
  late final Float64List _rip;

  /// How far the shape bulges OUT at most (px) – the sum of positive
  /// ripples.
  late final double maxBulge;

  /// The largest deformation (out or in) in px.
  late final double maxAmplitude;

  /// Whether the outline is an axis-aligned rounded rect (fast painting and
  /// the GPU shader).
  bool get isRoundedRect => _rr != null;

  /// Corner radius if [isRoundedRect], else 0.
  double get cornerRadius => _rr ?? 0;

  /// Whether the shape is deformed enough to be visible.
  bool get rippling => maxAmplitude > 0.2;

  /// The ripple that deforms the most (or null).
  GooeyRipple? get strongestRipple {
    GooeyRipple? best;
    for (final r in ripples) {
      if (best == null || r.amplitude.abs() > best.amplitude.abs()) best = r;
    }
    return best;
  }

  /// Signed distance: negative inside the shape, positive outside.
  double distance(double x, double y) {
    double d;
    final rr = _rr;
    if (rr != null) {
      final qx = (x - _cx).abs() - _hx;
      final qy = (y - _cy).abs() - _hy;
      final ox = qx > 0 ? qx : 0.0, oy = qy > 0 ? qy : 0.0;
      final inside = qx > qy ? qx : qy;
      d = math.sqrt(ox * ox + oy * oy) + (inside < 0 ? inside : 0.0) - rr;
    } else {
      d = _sdf.distance(x, y);
    }
    for (var i = 0; i < _rip.length; i += 4) {
      final dx = x - _rip[i], dy = y - _rip[i + 1];
      d -= _rip[i + 2] * math.exp(-(dx * dx + dy * dy) * _rip[i + 3]);
    }
    return d;
  }

  /// The point on the shape's edge closest to [p], found by stepping along
  /// the distance field's gradient. Exact for convex shapes, a good
  /// approximation for the rest.
  Offset closestOnEdge(Offset p) {
    var x = p.dx, y = p.dy;
    for (var i = 0; i < 3; i++) {
      final d = distance(x, y);
      if (d.abs() < 0.05) break;
      const e = 0.5;
      var gx = distance(x + e, y) - distance(x - e, y);
      var gy = distance(x, y + e) - distance(x, y - e);
      final len = math.sqrt(gx * gx + gy * gy);
      if (len < 1e-9) break;
      gx /= len;
      gy /= len;
      x -= gx * d;
      y -= gy * d;
    }
    return Offset(x, y);
  }

  /// The undeformed outline.
  Path get basePath => _basePath ??= _sdf.path;
  Path? _basePath;

  // The outline is computed at most once per shape (shapes are shared by all
  // painters in a frame), and the work buffer is reused between frames.
  Path? _outlineCache;
  double? _outlineCell;
  static Float64List _outlineBuf = Float64List(0);

  /// The outline as one smooth path – including the deformation.
  Path outline({double cell = 3}) {
    if (_outlineCache != null && _outlineCell == cell) return _outlineCache!;
    _outlineCell = cell;
    return _outlineCache = _computeOutline(cell);
  }

  Path _computeOutline(double cell) {
    if (!rippling) return basePath;
    final margin = maxBulge + 2 * cell;
    final area = rect.inflate(margin);
    final left = (area.left / cell).floorToDouble() * cell;
    final top = (area.top / cell).floorToDouble() * cell;
    final cols = ((area.right - left) / cell).ceil();
    final rows = ((area.bottom - top) / cell).ceil();
    final stride = cols + 1;
    final needed = stride * (rows + 1);
    if (_outlineBuf.length < needed) _outlineBuf = Float64List(needed);
    final f = _outlineBuf;
    for (var j = 0; j <= rows; j++) {
      final y = top + j * cell;
      for (var i = 0; i <= cols; i++) {
        var v = distance(left + i * cell, y);
        if ((j == 0 || j == rows || i == 0 || i == cols) && v < 1e-3) {
          v = 1e-3;
        }
        f[j * stride + i] = v;
      }
    }
    return traceContour(f, cols, rows, left, top, cell) ?? basePath;
  }
}
