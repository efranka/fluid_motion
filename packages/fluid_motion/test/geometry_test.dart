import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

const _c = Color(0xFF000000);
const _box = Rect.fromLTWH(0, 0, 100, 100);

double _d(GooeyGeometry g, double x, double y, [Rect rect = _box]) =>
    g.resolve(rect).distance(x, y);

void main() {
  group('geometries', () {
    test('circle: centre, edge, outside', () {
      const g = GooeyCircle();
      expect(_d(g, 50, 50), closeTo(-50, 1e-9));
      expect(_d(g, 100, 50), closeTo(0, 1e-9));
      expect(_d(g, 110, 50), closeTo(10, 1e-9));
      // A circle in a wide rect stays round and centred.
      const wide = Rect.fromLTWH(0, 0, 200, 100);
      expect(_d(g, 100, 50, wide), closeTo(-50, 1e-9));
      expect(_d(g, 160, 50, wide), closeTo(10, 1e-9));
    });

    test('a circle in a square uses the rounded rect fast path', () {
      final shape = GooeyShape(_box, _c, geometry: const GooeyCircle());
      expect(shape.isRoundedRect, isTrue);
      expect(shape.cornerRadius, 50);
      final wide = GooeyShape(
        const Rect.fromLTWH(0, 0, 200, 100),
        _c,
        geometry: const GooeyCircle(),
      );
      expect(wide.isRoundedRect, isFalse);
    });

    test('ring: the hole is outside', () {
      const g = GooeyRing(thickness: 0.4); // outer 50, inner 30
      expect(_d(g, 50, 50), greaterThan(0)); // centre of the hole
      expect(_d(g, 50, 10), lessThan(0)); // in the band
      expect(_d(g, 50, 0), closeTo(0, 1e-9)); // outer edge
      expect(_d(g, 50, 20), closeTo(0, 1e-9)); // inner edge
    });

    test('polygon: a square polygon matches the square', () {
      const g = GooeyPolygon([
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ]);
      expect(_d(g, 50, 50), closeTo(-50, 1e-9));
      expect(_d(g, 50, -10), closeTo(10, 1e-9));
      expect(_d(g, 110, 110), closeTo(math.sqrt(200), 1e-9));
    });

    test('rounded polygon stays inside its rect', () {
      final g = GooeyPolygon.regular(6, cornerRadius: 8);
      final sdf = g.resolve(_box);
      // Just outside every side of the rect.
      expect(sdf.distance(50, -1), greaterThan(0));
      expect(sdf.distance(101, 50), greaterThan(0));
      expect(sdf.distance(50, 50), lessThan(0));
      expect(sdf.path.getBounds().inflate(0.5).contains(const Offset(50, 50)),
          isTrue);
    });

    test('star: tips inside, notches deeper than tips', () {
      const g = GooeyStar(points: 5, innerRatio: 0.4);
      expect(_d(g, 50, 50), lessThan(0)); // centre
      expect(_d(g, 50, 1), lessThan(0.5)); // near the top tip
      // Between two tips (36° off the top) the star is much narrower.
      final a = -math.pi / 2 + math.pi / 5;
      final x = 50 + 45 * math.cos(a), y = 50 + 45 * math.sin(a);
      expect(_d(g, x, y), greaterThan(0));
    });

    test('path geometry follows the path', () {
      final g = GooeyPathGeometry(
        (size) => Path()..addOval(Offset.zero & size),
      );
      expect(_d(g, 50, 50), lessThan(-45));
      expect(_d(g, 50, 0).abs(), lessThan(2));
      expect(_d(g, 50, -10), closeTo(10, 2));
    });
  });

  test('an empty rect never produces a broken outline', () {
    final g = GooeyPathGeometry((size) => Path()..addOval(Offset.zero & size));
    for (final geometry in <GooeyGeometry>[
      g,
      const GooeyCircle(),
      const GooeyRing(),
      const GooeyStar(),
      GooeyPolygon.regular(5, cornerRadius: 4),
    ]) {
      final shape = GooeyShape(Rect.zero, _c, geometry: geometry);
      expect(shape.distance(10, 0).isFinite, isTrue);
      expect(() => shape.basePath.getBounds(), returnsNormally);
    }
    // And the real size still works afterwards.
    expect(_d(g, 50, 50), lessThan(-45));
  });

  group('contact between any shapes', () {
    test('two circles: gap along the line between them', () {
      final a = GooeyShape(_box, _c, geometry: const GooeyCircle());
      final b = GooeyShape(
        const Rect.fromLTWH(110, 0, 100, 100),
        _c,
        geometry: const GooeyRing(),
      );
      final (gap, focus) = GooeyContact.measure(a, b);
      expect(gap, closeTo(10, 0.5));
      expect(focus.dx, closeTo(105, 0.5));
      expect(focus.dy, closeTo(50, 0.5));
    });

    test('diagonal circles: much further apart than their boxes', () {
      final a = GooeyShape(_box, _c, geometry: const GooeyCircle());
      final b = GooeyShape(
        const Rect.fromLTWH(105, 105, 100, 100),
        _c,
        geometry: const GooeyRing(thickness: 1),
      );
      final (gap, _) = GooeyContact.measure(a, b);
      // Centres are 105·√2 ≈ 148 apart, minus two radii of 50.
      expect(gap, closeTo(105 * math.sqrt2 - 100, 1));
      expect(GooeyContact.boxGap(a.rect, b.rect), lessThan(10));
    });

    test('a shape deep inside a ring still overlaps it', () {
      // Ring: outer radius 50, inner radius 30, centred at (50, 50).
      final ring =
          GooeyShape(_box, _c, geometry: const GooeyRing(thickness: 0.4));
      // A circle (radius 20) centred on the band, at the hole's edge.
      final circle = GooeyShape(
        const Rect.fromLTWH(60, 30, 40, 40),
        _c,
        geometry: const GooeyCircle(),
      );
      expect(GooeyContact.measure(circle, ring).$1, 0);
      expect(GooeyContact.measure(ring, circle).$1, 0);
    });

    test('a small shape inside the hole of a ring is apart from it', () {
      final ring =
          GooeyShape(_box, _c, geometry: const GooeyRing(thickness: 0.4));
      // Radius 10 in the middle of a hole with radius 30: 20 px apart.
      final dot = GooeyShape(
        const Rect.fromLTWH(40, 40, 20, 20),
        _c,
        geometry: const GooeyCircle(),
      );
      expect(GooeyContact.measure(dot, ring).$1, closeTo(20, 0.5));
    });

    test('overlapping shapes have no gap', () {
      final a = GooeyShape(_box, _c, geometry: const GooeyStar());
      final b = GooeyShape(
        const Rect.fromLTWH(40, 40, 100, 100),
        _c,
        geometry: const GooeyRing(thickness: 1),
      );
      expect(GooeyContact.measure(a, b).$1, 0);
    });
  });
}
