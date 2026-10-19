import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

const _c = Color(0xFF000000);

void main() {
  group('GooeyShape.distance', () {
    final shape = GooeyShape(const Rect.fromLTWH(0, 0, 200, 64), _c);

    test('negative inside, zero on the edge, positive outside', () {
      expect(shape.distance(100, 32), closeTo(-32, 1e-9));
      expect(shape.distance(100, 0), closeTo(0, 1e-9));
      expect(shape.distance(100, -10), closeTo(10, 1e-9));
      expect(shape.cornerRadius, 32);
    });

    test('a positive ripple pushes the edge out', () {
      final rippled = GooeyShape(
        const Rect.fromLTWH(0, 0, 200, 64),
        _c,
        ripples: const [GooeyRipple(Offset(100, 0), 6)],
      );
      expect(rippled.distance(100, -3), lessThan(0));
      expect(rippled.maxBulge, 6);
      expect(rippled.rippling, isTrue);
      expect(shape.rippling, isFalse);
    });
  });

  group('GooeyContact', () {
    const a = Rect.fromLTWH(0, 0, 100, 64);

    test('boxGap', () {
      expect(GooeyContact.boxGap(a, const Rect.fromLTWH(110, 0, 50, 64)), 10);
      expect(GooeyContact.boxGap(a, const Rect.fromLTWH(50, 0, 100, 64)), 0);
      expect(
        GooeyContact.boxGap(a, const Rect.fromLTWH(103, 68, 10, 10)),
        closeTo(5, 1e-9),
      );
    });

    test('strength rises smoothly from 0 to 1 as the shapes approach', () {
      var last = -1.0;
      for (var gap = 10.0; gap >= 0; gap -= 0.5) {
        final s = GooeyContact.between(
          a,
          Rect.fromLTWH(100 + gap, 0, 50, 64),
          meetAt: 8,
        ).strength;
        expect(s, inInclusiveRange(0.0, 1.0));
        expect(s, greaterThanOrEqualTo(last));
        last = s;
      }
      expect(last, 1);
    });
  });

  group('ContactTracker', () {
    test('catches and releases with hysteresis – without flickering', () {
      final t = ContactTracker(meetAt: 8, hysteresis: 0.75);
      expect(t.update(12), ContactEvent.none);
      expect(t.update(7.5), ContactEvent.none); // within the hysteresis
      expect(t.update(7), ContactEvent.caught);
      expect(t.connected, isTrue);
      expect(t.update(8.5), ContactEvent.none); // within the hysteresis
      expect(t.update(7), ContactEvent.none);
      expect(t.update(9), ContactEvent.released);
      expect(t.connected, isFalse);
    });
  });

  group('smoothMin and traceContour', () {
    test('smoothMin is min far apart and softer close together', () {
      expect(smoothMin(0, 10, 4), 0);
      expect(smoothMin(1, 1, 4), lessThan(1));
    });

    test('a circle on a grid gives a closed contour', () {
      const cols = 20, rows = 20;
      final f = Float64List((cols + 1) * (rows + 1));
      for (var j = 0; j <= rows; j++) {
        for (var i = 0; i <= cols; i++) {
          final dx = i - 10.0, dy = j - 10.0;
          f[j * (cols + 1) + i] = (dx * dx + dy * dy) - 36; // r = 6
        }
      }
      final path = traceContour(f, cols, rows, 0, 0, 1);
      expect(path, isNotNull);
      final b = path!.getBounds();
      expect(b.center.dx, closeTo(10, 0.5));
      expect(b.width, closeTo(12, 1.5));
    });

    test('nothing inside gives no contour', () {
      final f = Float64List(11 * 11)..fillRange(0, 121, 1);
      expect(traceContour(f, 10, 10, 0, 0, 1), isNull);
    });
  });

  group('GooeyColorField', () {
    test('only blends while the shapes are connected', () {
      final apart = GooeyColorField([
        GooeyShape(const Rect.fromLTWH(0, 0, 100, 64), const Color(0xFFFF0000)),
        GooeyShape(
            const Rect.fromLTWH(140, 0, 64, 64), const Color(0xFF0000FF)),
      ], meetAt: 8);
      expect(apart.mixing, isFalse);

      final touching = GooeyColorField([
        GooeyShape(const Rect.fromLTWH(0, 0, 100, 64), const Color(0xFFFF0000)),
        GooeyShape(
            const Rect.fromLTWH(100, 0, 64, 64), const Color(0xFF0000FF)),
      ], meetAt: 8);
      expect(touching.mixing, isTrue);
    });

    // A red, B grey and C blue in a row, touching: B lies between two others.
    List<GooeyShape> chain() => [
          GooeyShape(
              const Rect.fromLTWH(0, 0, 100, 64), const Color(0xFFFF0000),
              radius: 8),
          GooeyShape(
              const Rect.fromLTWH(100, 0, 60, 64), const Color(0xFF808080),
              radius: 8),
          GooeyShape(
              const Rect.fromLTWH(160, 0, 100, 64), const Color(0xFF0000FF),
              radius: 8),
        ];

    int maxChannelJump(int a, int b) {
      var most = 0;
      for (final shift in [16, 8, 0]) {
        final d = (((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs();
        if (d > most) most = d;
      }
      return most;
    }

    test('a shape between two others blends towards both, without an edge', () {
      final field =
          GooeyColorField(chain(), meetAt: 8, maxWidth: 120, neighbours: 3);
      // The middle of B, where A and C are equally far away.
      final left = field.argbAt(129.9, 32), right = field.argbAt(130.1, 32);
      expect(maxChannelJump(left, right), lessThanOrEqualTo(2));
      // … and A's red and C's blue pull equally (green has none of either,
      // so it drops below the grey's own).
      final mid = field.argbAt(130, 32);
      expect((((mid >> 16) & 0xFF) - (mid & 0xFF)).abs(), lessThanOrEqualTo(1));
      expect((mid >> 8) & 0xFF, lessThan(100));
    });

    test('with one neighbour the colour jumps where the nearest changes', () {
      final field =
          GooeyColorField(chain(), meetAt: 8, maxWidth: 120, neighbours: 1);
      final left = field.argbAt(129.9, 32), right = field.argbAt(130.1, 32);
      expect(maxChannelJump(left, right), greaterThan(10));
    });

    test('one neighbour blends exactly like the two nearest', () {
      final two = [chain()[0], chain()[1]];
      final one = GooeyColorField(two, meetAt: 8, neighbours: 1);
      final three = GooeyColorField(two, meetAt: 8, neighbours: 3);
      for (var x = 60.0; x < 160; x += 7) {
        expect(maxChannelJump(one.argbAt(x, 32), three.argbAt(x, 32)),
            lessThanOrEqualTo(1));
      }
    });

    test('neighboursOf lists connected shapes, most connected first', () {
      final field = GooeyColorField(chain(), meetAt: 8);
      expect(field.neighboursOf(1, 3).toSet(), {0, 2});
      expect(field.neighboursOf(1, 1), hasLength(1));
      expect(field.neighboursOf(1, 0), isEmpty);
      expect(field.neighboursOf(0, 3), [1]); // A does not touch C
    });
  });

  group('GooeyStyle', () {
    test('blendNeighbours defaults to every slot and survives copyWith', () {
      const style = GooeyStyle();
      expect(style.blendNeighbours, GooeyShader.maxNeighbours);
      expect(style.copyWith(blendNeighbours: 1).blendNeighbours, 1);
      expect(style.copyWith(neck: false).blendNeighbours,
          GooeyShader.maxNeighbours);
    });
  });
}
