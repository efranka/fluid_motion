import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The outline of a gooey shape, described as a signed distance field (SDF):
/// for any point, how far it is from the edge (negative inside, positive
/// outside). Everything in the gooey system – the neck, colour blending,
/// blobs, content dissolving – only ever asks "how far is this point from the
/// shape?", so any outline that can answer that works.
///
/// A geometry is resolution independent: it is fitted into the shape's
/// bounding rect each frame with [resolve].
///
/// Built in: [GooeyRoundedRect] (default, also pills), [GooeyCircle],
/// [GooeyRing], [GooeyPolygon], [GooeyStar] and [GooeyPathGeometry] (any
/// [Path]). Implement this class to add your own.
@immutable
abstract class GooeyGeometry {
  const GooeyGeometry();

  /// The outline fitted into [rect] (in scene coordinates).
  GooeySdf resolve(Rect rect);
}

/// A geometry fitted into a concrete rect, ready to answer distance queries
/// fast (they run thousands of times per frame).
abstract class GooeySdf {
  /// Signed distance from (x, y) to the edge: negative inside.
  double distance(double x, double y);

  /// The outline as a path (used to paint the shape when it is not
  /// deformed).
  Path get path;

  /// If the outline is an axis-aligned rounded rect, its corner radius;
  /// otherwise null. Rounded rects get faster painting and the GPU shader.
  double? get roundedRectRadius => null;
}

// ---------------------------------------------------------------------------
// Rounded rect / pill
// ---------------------------------------------------------------------------

/// An axis-aligned rounded rect. Without a [radius] it is a pill (fully
/// rounded ends). The default geometry.
class GooeyRoundedRect extends GooeyGeometry {
  const GooeyRoundedRect({this.radius});

  /// Corner radius in px (clamped to half the shortest side); null = pill.
  final double? radius;

  @override
  GooeySdf resolve(Rect rect) => _RoundedRectSdf(
        rect,
        math.min(radius ?? rect.shortestSide / 2, rect.shortestSide / 2),
      );

  @override
  bool operator ==(Object other) =>
      other is GooeyRoundedRect && other.radius == radius;

  @override
  int get hashCode => radius.hashCode;
}

class _RoundedRectSdf extends GooeySdf {
  _RoundedRectSdf(this.rect, this.r)
      : _cx = rect.center.dx,
        _cy = rect.center.dy,
        _hx = rect.width / 2 - r,
        _hy = rect.height / 2 - r;

  final Rect rect;
  final double r;
  final double _cx, _cy, _hx, _hy;

  @override
  double distance(double x, double y) {
    final qx = (x - _cx).abs() - _hx;
    final qy = (y - _cy).abs() - _hy;
    final ox = qx > 0 ? qx : 0.0, oy = qy > 0 ? qy : 0.0;
    final inside = qx > qy ? qx : qy;
    return math.sqrt(ox * ox + oy * oy) + (inside < 0 ? inside : 0.0) - r;
  }

  @override
  Path get path =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));

  @override
  double get roundedRectRadius => r;
}

// ---------------------------------------------------------------------------
// Circle and ring
// ---------------------------------------------------------------------------

/// A circle centred in the rect, as large as fits.
class GooeyCircle extends GooeyGeometry {
  const GooeyCircle();

  @override
  GooeySdf resolve(Rect rect) => (rect.width - rect.height).abs() < 0.5
      // In a square a circle IS a fully rounded rect – and gets the GPU path.
      ? _RoundedRectSdf(rect, rect.shortestSide / 2)
      : _RingSdf(rect, null);

  @override
  bool operator ==(Object other) => other is GooeyCircle;

  @override
  int get hashCode => (GooeyCircle).hashCode;
}

/// A ring (a circle with a hole), centred in the rect, as large as fits.
class GooeyRing extends GooeyGeometry {
  const GooeyRing({this.thickness = 0.4})
      : assert(thickness > 0 && thickness <= 1);

  /// How thick the ring is, as a fraction of its outer radius (1 = a full
  /// circle).
  final double thickness;

  @override
  GooeySdf resolve(Rect rect) => _RingSdf(rect, thickness);

  @override
  bool operator ==(Object other) =>
      other is GooeyRing && other.thickness == thickness;

  @override
  int get hashCode => thickness.hashCode;
}

class _RingSdf extends GooeySdf {
  _RingSdf(Rect rect, double? thickness)
      : _cx = rect.center.dx,
        _cy = rect.center.dy,
        _outer = rect.shortestSide / 2,
        _half = thickness == null ? null : rect.shortestSide / 4 * thickness;

  final double _cx, _cy, _outer;
  final double? _half; // half the ring's thickness (null = full circle)

  @override
  double distance(double x, double y) {
    final dx = x - _cx, dy = y - _cy;
    final len = math.sqrt(dx * dx + dy * dy);
    final half = _half;
    if (half == null) return len - _outer;
    return (len - (_outer - half)).abs() - half;
  }

  @override
  Path get path {
    final c = Offset(_cx, _cy);
    final p = Path()..addOval(Rect.fromCircle(center: c, radius: _outer));
    final half = _half;
    if (half != null) {
      p
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: _outer - 2 * half));
    }
    return p;
  }
}

// ---------------------------------------------------------------------------
// Polygon and star
// ---------------------------------------------------------------------------

/// Any simple polygon. [points] are fractions of the rect (0..1 on both
/// axes), so the polygon stretches with its rect. [cornerRadius] rounds all
/// corners (in px).
class GooeyPolygon extends GooeyGeometry {
  /// [points] needs at least three corners.
  const GooeyPolygon(this.points, {this.cornerRadius = 0});

  final List<Offset> points;
  final double cornerRadius;

  /// A regular polygon with [sides] corners, pointing up.
  factory GooeyPolygon.regular(int sides, {double cornerRadius = 0}) =>
      GooeyPolygon(
        [
          for (var i = 0; i < sides; i++)
            _onUnitCircle(-math.pi / 2 + 2 * math.pi * i / sides, 1),
        ],
        cornerRadius: cornerRadius,
      );

  @override
  GooeySdf resolve(Rect rect) => _PolygonSdf(rect, points, cornerRadius);

  @override
  bool operator ==(Object other) =>
      other is GooeyPolygon &&
      other.cornerRadius == cornerRadius &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(cornerRadius, Object.hashAll(points));
}

/// A star with [points] tips. [innerRatio] is how deep the notches between
/// the tips go (inner radius / outer radius). [cornerRadius] rounds the tips
/// and notches (in px).
class GooeyStar extends GooeyGeometry {
  const GooeyStar({
    this.points = 5,
    this.innerRatio = 0.5,
    this.cornerRadius = 0,
  }) : assert(points >= 3 && innerRatio > 0 && innerRatio < 1);

  final int points;
  final double innerRatio;
  final double cornerRadius;

  @override
  GooeySdf resolve(Rect rect) => _PolygonSdf(
        rect,
        [
          for (var i = 0; i < points * 2; i++)
            _onUnitCircle(
              -math.pi / 2 + math.pi * i / points,
              i.isEven ? 1 : innerRatio,
            ),
        ],
        cornerRadius,
      );

  @override
  bool operator ==(Object other) =>
      other is GooeyStar &&
      other.points == points &&
      other.innerRatio == innerRatio &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(points, innerRatio, cornerRadius);
}

/// A point on a circle of radius [r] (0..1) in unit coordinates (0..1).
Offset _onUnitCircle(double angle, double r) =>
    Offset(0.5 + 0.5 * r * math.cos(angle), 0.5 + 0.5 * r * math.sin(angle));

class _PolygonSdf extends GooeySdf {
  _PolygonSdf(Rect rect, List<Offset> unitPoints, double cornerRadius)
      : _round = rect.width < 1 || rect.height < 1 ? 0 : cornerRadius {
    // Rounding grows the shape by [cornerRadius]; shrink the polygon by the
    // same amount first so the result still fits its rect.
    final inner = rect.deflate(math.min(cornerRadius, rect.shortestSide / 2));
    _v = Float64List(unitPoints.length * 2);
    for (var i = 0; i < unitPoints.length; i++) {
      _v[2 * i] = inner.left + unitPoints[i].dx * inner.width;
      _v[2 * i + 1] = inner.top + unitPoints[i].dy * inner.height;
    }
  }

  late final Float64List _v;
  final double _round;

  // Exact signed distance to a simple polygon (after Inigo Quilez).
  @override
  double distance(double x, double y) {
    final v = _v;
    final n = v.length ~/ 2;
    var d = double.infinity;
    var s = 1.0;
    for (var i = 0, j = n - 1; i < n; j = i, i++) {
      final vix = v[2 * i], viy = v[2 * i + 1];
      final ex = v[2 * j] - vix, ey = v[2 * j + 1] - viy;
      final wx = x - vix, wy = y - viy;
      final ee = ex * ex + ey * ey;
      final t = ee < 1e-12 ? 0.0 : ((wx * ex + wy * ey) / ee).clamp(0.0, 1.0);
      final bx = wx - ex * t, by = wy - ey * t;
      final dd = bx * bx + by * by;
      if (dd < d) d = dd;
      final c1 = y >= viy;
      final c2 = y < v[2 * j + 1];
      final c3 = ex * wy > ey * wx;
      if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
    }
    return s * math.sqrt(d) - _round;
  }

  @override
  late final Path path = _roundedPolygonPath(_v, _round);
}

/// The outline of polygon [v] (x, y pairs) grown by [r]: every edge moves
/// out by [r]; convex corners become arcs around the original corner,
/// concave corners (like a star's notches) stay sharp where the moved edges
/// meet. Exactly the zero line of the polygon's distance minus [r].
Path _roundedPolygonPath(Float64List v, double r) {
  final n = v.length ~/ 2;
  final path = Path();
  if (r <= 0) {
    path.moveTo(v[0], v[1]);
    for (var i = 1; i < n; i++) {
      path.lineTo(v[2 * i], v[2 * i + 1]);
    }
    return path..close();
  }
  // Orientation, so "outward" is known.
  var area = 0.0;
  for (var i = 0, j = n - 1; i < n; j = i, i++) {
    area += v[2 * j] * v[2 * i + 1] - v[2 * i] * v[2 * j + 1];
  }
  final sign = area > 0 ? 1.0 : -1.0;
  Offset pt(int i) => Offset(v[2 * (i % n)], v[2 * (i % n) + 1]);
  Offset normal(Offset a, Offset b) {
    final e = b - a;
    final len = e.distance;
    if (len < 1e-9) return Offset.zero;
    // Outward normal for the polygon's orientation.
    return Offset(e.dy, -e.dx) / len * sign;
  }

  var first = true;
  for (var i = 0; i < n; i++) {
    final prev = pt(i + n - 1), cur = pt(i), next = pt(i + 1);
    final n1 = normal(prev, cur), n2 = normal(cur, next);
    final e1 = cur - prev, e2 = next - cur;
    final cross = (e1.dx * e2.dy - e1.dy * e2.dx) * sign;
    if (cross >= 0) {
      // Convex: arc around the corner.
      final a = cur + n1 * r;
      if (first) {
        path.moveTo(a.dx, a.dy);
        first = false;
      } else {
        path.lineTo(a.dx, a.dy);
      }
      final start = math.atan2(n1.dy, n1.dx);
      var sweep = math.atan2(n2.dy, n2.dx) - start;
      while (sweep <= -math.pi) {
        sweep += 2 * math.pi;
      }
      while (sweep > math.pi) {
        sweep -= 2 * math.pi;
      }
      path.arcTo(Rect.fromCircle(center: cur, radius: r), start, sweep, false);
    } else {
      // Concave: where the two moved edges meet.
      final p1 = prev + n1 * r, d1 = e1;
      final p2 = cur + n2 * r, d2 = e2;
      final den = d1.dx * d2.dy - d1.dy * d2.dx;
      final t = den.abs() < 1e-9
          ? 1.0
          : ((p2.dx - p1.dx) * d2.dy - (p2.dy - p1.dy) * d2.dx) / den;
      final x = p1 + d1 * t;
      if (first) {
        path.moveTo(x.dx, x.dy);
        first = false;
      } else {
        path.lineTo(x.dx, x.dy);
      }
    }
  }
  return path..close();
}

// ---------------------------------------------------------------------------
// Any path
// ---------------------------------------------------------------------------

/// Any outline, drawn as a [Path] by [builder] for a given size (with its
/// top left at 0, 0).
///
/// The distance field is computed once from the path (sampled every
/// [resolution] px) and reused; when the rect changes size it is stretched,
/// and recomputed only if the size changes a lot. Prefer the analytic
/// geometries above when one fits – they are exact and cheaper.
class GooeyPathGeometry extends GooeyGeometry {
  const GooeyPathGeometry(this.builder, {this.resolution = 2});

  final Path Function(Size size) builder;
  final double resolution;

  // The computed field, per geometry instance (geometries are immutable).
  static final _fields = Expando<_PathField>();

  @override
  GooeySdf resolve(Rect rect) {
    // An empty rect (e.g. before the first layout) has no outline to sample.
    if (rect.width < 1 || rect.height < 1) return _PointSdf(rect.center);
    var f = _fields[this];
    if (f == null || !f.closeEnough(rect.size)) {
      f = _fields[this] = _PathField(builder(rect.size), rect.size, resolution);
    }
    return _PathSdf(f, rect);
  }
}

class _PathField {
  _PathField(this.path, this.size, this.cell) {
    // Edge samples.
    final pts = <double>[];
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += cell / 2) {
        final p = m.getTangentForOffset(d)!.position;
        pts
          ..add(p.dx)
          ..add(p.dy);
      }
    }
    final pad = margin;
    cols = ((size.width + 2 * pad) / cell).ceil() + 1;
    rows = ((size.height + 2 * pad) / cell).ceil() + 1;
    values = Float32List(cols * rows);
    for (var j = 0; j < rows; j++) {
      final y = -pad + j * cell;
      for (var i = 0; i < cols; i++) {
        final x = -pad + i * cell;
        var best = double.infinity;
        for (var k = 0; k < pts.length; k += 2) {
          final dx = x - pts[k], dy = y - pts[k + 1];
          final dd = dx * dx + dy * dy;
          if (dd < best) best = dd;
        }
        final d = math.sqrt(best);
        values[j * cols + i] = path.contains(Offset(x, y)) ? -d : d;
      }
    }
  }

  static const margin = 24.0;
  final Path path;
  final Size size;
  final double cell;
  late final int cols, rows;
  late final Float32List values;

  bool closeEnough(Size other) {
    final rx = other.width / size.width, ry = other.height / size.height;
    return rx > 0.8 && rx < 1.25 && ry > 0.8 && ry < 1.25;
  }

  /// Bilinear lookup in the field's own (unscaled) coordinates.
  double sample(double x, double y) {
    final gx = ((x + margin) / cell).clamp(0.0, cols - 1.001);
    final gy = ((y + margin) / cell).clamp(0.0, rows - 1.001);
    final i = gx.floor(), j = gy.floor();
    final fx = gx - i, fy = gy - j;
    final a = values[j * cols + i], b = values[j * cols + i + 1];
    final c = values[(j + 1) * cols + i], d = values[(j + 1) * cols + i + 1];
    var v = (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
    // Beyond the sampled area: add the distance to it.
    final ox = x < -margin
        ? -margin - x
        : (x > size.width + margin ? x - size.width - margin : 0.0);
    final oy = y < -margin
        ? -margin - y
        : (y > size.height + margin ? y - size.height - margin : 0.0);
    if (ox > 0 || oy > 0) v += math.sqrt(ox * ox + oy * oy);
    return v;
  }
}

/// A degenerate outline: just a point.
class _PointSdf extends GooeySdf {
  _PointSdf(this.c);
  final Offset c;

  @override
  double distance(double x, double y) => (Offset(x, y) - c).distance;

  @override
  Path get path => Path();
}

class _PathSdf extends GooeySdf {
  _PathSdf(this.field, this.rect)
      : _sx = rect.width / field.size.width,
        _sy = rect.height / field.size.height;

  final _PathField field;
  final Rect rect;
  final double _sx, _sy;

  @override
  double distance(double x, double y) {
    final d = field.sample((x - rect.left) / _sx, (y - rect.top) / _sy);
    // Stretching changes distances; scale by the smaller factor so the
    // shape never seems closer than it is.
    return d * math.min(_sx, _sy);
  }

  @override
  Path get path => field.path.transform(Float64List.fromList([
        _sx, 0, 0, 0, //
        0, _sy, 0, 0, //
        0, 0, 1, 0, //
        rect.left, rect.top, 0, 1, //
      ]));
}
