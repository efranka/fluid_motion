import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;

import 'package:flutter/painting.dart';

import 'contact.dart';
import 'shape.dart';

/// One continuous colour field for shapes that can flow together.
///
/// The colour at each point depends on how close it is to the two nearest
/// shapes (the difference in distance). Far from a contact the colour is the
/// shape's own; close to one it glides smoothly into the other shape's
/// colour. Because the shapes AND the neck are painted from the same field,
/// there is no edge anywhere – not even where one shape lies on top of
/// another.
///
/// The width of the transition grows with the contact: apart it is sharp
/// (each shape has its own colour), connected the blend spreads into the
/// shapes.
///
/// With more than two shapes, each point blends the nearest shape with up
/// to [neighbours] of the next nearest at once – so a shape that touches two
/// others blends towards both, without an edge where one takes over.
class GooeyColorField {
  GooeyColorField(
    this.shapes, {
    required double meetAt,
    this.minWidth = 4,
    this.maxWidth = 60,
    this.neighbours = 3,
  })  : assert(neighbours >= 1, 'a field blends at least two shapes'),
        _n = shapes.length {
    _strength = Float64List(_n * _n);
    var maxStrength = 0.0;
    for (var i = 0; i < _n; i++) {
      for (var j = i + 1; j < _n; j++) {
        final s = GooeyContact.betweenShapes(
          shapes[i],
          shapes[j],
          meetAt: meetAt,
        ).strength;
        _strength[i * _n + j] = s;
        _strength[j * _n + i] = s;
        maxStrength = math.max(maxStrength, s);
      }
    }
    strength = maxStrength;
    _argb = Int32List.fromList([
      for (final s in shapes) s.color.toARGB32(),
    ]);
    _dist = Float64List(_n);
  }

  final List<GooeyShape> shapes;
  final double minWidth, maxWidth;

  /// How many other shapes each point blends towards (1 = only the second
  /// nearest).
  final int neighbours;
  final int _n;
  late final Float64List _strength;
  late final Int32List _argb;
  late final Float64List _dist;

  /// The strongest contact between any two of the shapes (0..1).
  late final double strength;

  /// The contact between shape [i] and [j] (0..1).
  double strengthOf(int i, int j) => i == j ? 0 : _strength[i * _n + j];

  /// The transition's width (px) between shape [i] and [j].
  double widthOf(int i, int j) =>
      lerpDouble(minWidth, maxWidth, strengthOf(i, j))!;

  /// Whether any shapes are connected enough for their colours to blend.
  bool get mixing => strength > 0.001;

  /// The shapes that shape [index] is connected to, most connected first –
  /// at most [max] of them.
  List<int> neighboursOf(int index, int max) {
    if (max <= 0) return const [];
    final result = <int>[
      for (var j = 0; j < _n; j++)
        if (j != index && strengthOf(index, j) > 0.001) j,
    ]..sort((x, y) => strengthOf(index, y).compareTo(strengthOf(index, x)));
    return result.length > max ? result.sublist(0, max) : result;
  }

  /// The colour at a point as a packed ARGB int (no objects allocated).
  ///
  /// The nearest shape has weight 1; each of the next nearest (up to
  /// [neighbours]) pulls the colour towards itself with weight u/(1-u),
  /// where u is how far the blend between the two has come. With one
  /// neighbour that is exactly a blend of the two nearest; with more, the
  /// pulls add up smoothly.
  int argbAt(double x, double y) {
    if (_n == 0) return 0;
    if (_n == 1) return _argb[0];
    var i0 = 0;
    for (var k = 0; k < _n; k++) {
      final d = shapes[k].distance(x, y);
      _dist[k] = d;
      if (d < _dist[i0]) i0 = k;
    }
    final c0 = _argb[i0];
    var total = 1.0;
    var a = ((c0 >> 24) & 0xFF).toDouble(), r = ((c0 >> 16) & 0xFF).toDouble();
    var g = ((c0 >> 8) & 0xFF).toDouble(), b = (c0 & 0xFF).toDouble();
    // The next nearest shapes, one at a time (marked as used with infinity).
    final d0 = _dist[i0];
    _dist[i0] = double.infinity;
    final count = math.min(neighbours, _n - 1);
    for (var m = 0; m < count; m++) {
      var k = -1;
      for (var q = 0; q < _n; q++) {
        if (_dist[q] != double.infinity && (k < 0 || _dist[q] < _dist[k])) {
          k = q;
        }
      }
      if (k < 0) break;
      final u = blendBetween(d0, _dist[k], widthOf(i0, k));
      _dist[k] = double.infinity;
      if (u <= 0) continue;
      final weight = math.min(u, 0.999) / (1 - math.min(u, 0.999));
      final c = _argb[k];
      a += ((c >> 24) & 0xFF) * weight;
      r += ((c >> 16) & 0xFF) * weight;
      g += ((c >> 8) & 0xFF) * weight;
      b += (c & 0xFF) * weight;
      total += weight;
    }
    int ch(double v) => (v / total).round().clamp(0, 255);
    return (ch(a) << 24) | (ch(r) << 16) | (ch(g) << 8) | ch(b);
  }

  /// How far (0..1) the colour at a point has moved from the shape at
  /// distance [da] towards the one at distance [db], over [width] px.
  static double blendBetween(double da, double db, double width) {
    final u = (0.5 + (da - db) / (2 * width)).clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }

  Color colorAt(double x, double y) => Color(argbAt(x, y));

  /// The part of shape [index] where the colour differs from the shape's own
  /// at all (in field coordinates). Outside it the blend is 0, so the shape
  /// can be painted as one flat fill and only this part needs the grid.
  Rect activeRect(int index) {
    final shape = shapes[index];
    Rect? result;
    for (var j = 0; j < _n; j++) {
      if (j == index) continue;
      final other = shapes[j];
      final ripple = shape.maxAmplitude + other.maxAmplitude;
      final r = shape.rect.inflate(ripple).intersect(
            other.rect.inflate(2 * widthOf(index, j) + 2 + ripple),
          );
      if (r.width <= 0 || r.height <= 0) continue;
      result = result == null ? r : result.expandToInclude(r);
    }
    return result ?? Rect.zero;
  }

  // Reused buffers (Vertices.raw copies the data, so they can be reused
  // between frames) and triangle indices that only depend on the grid size.
  static Float32List _positions = Float32List(0);
  static Int32List _colors = Int32List(0);
  static final Map<int, Uint16List> _indexCache = {};

  static Uint16List _indicesFor(int cols, int rows) {
    final key = cols * 65536 + rows;
    final cached = _indexCache[key];
    if (cached != null) return cached;
    if (_indexCache.length > 24) _indexCache.clear();
    final indices = Uint16List(cols * rows * 6);
    var m = 0;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final tl = j * (cols + 1) + i, tr = tl + 1;
        final bl = tl + cols + 1, br = bl + 1;
        indices[m++] = tl;
        indices[m++] = tr;
        indices[m++] = bl;
        indices[m++] = tr;
        indices[m++] = br;
        indices[m++] = bl;
      }
    }
    return _indexCache[key] = indices;
  }

  /// Paints the field in [rect] (field coordinates), shifted by -[origin].
  /// Colours are computed on a grid and interpolated smoothly by the GPU
  /// (drawVertices), so only a few hundred points need computing.
  void paint(
    Canvas canvas,
    Rect rect, {
    Offset origin = Offset.zero,
    double cell = 4,
  }) {
    if (rect.width <= 0 || rect.height <= 0) return;
    final cols = math.max(1, (rect.width / cell).ceil());
    final rows = math.max(1, (rect.height / cell).ceil());
    final n = (cols + 1) * (rows + 1);
    if (n > 65000) return;
    final dx = rect.width / cols, dy = rect.height / rows;

    if (_positions.length < n * 2) _positions = Float32List(n * 3);
    if (_colors.length < n) _colors = Int32List(n * 3 ~/ 2);
    final positions = Float32List.sublistView(_positions, 0, n * 2);
    final colors = Int32List.sublistView(_colors, 0, n);

    var k = 0;
    for (var j = 0; j <= rows; j++) {
      final y = rect.top + j * dy;
      for (var i = 0; i <= cols; i++) {
        final x = rect.left + i * dx;
        positions[2 * k] = x - origin.dx;
        positions[2 * k + 1] = y - origin.dy;
        colors[k] = argbAt(x, y);
        k++;
      }
    }

    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: _indicesFor(cols, rows),
      ),
      BlendMode.dst, // use the vertex colours
      Paint(),
    );
  }
}
