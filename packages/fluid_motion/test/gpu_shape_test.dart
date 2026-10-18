import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

const _box = Rect.fromLTWH(10, 20, 100, 100);

GooeyGpuShape? _gpu(GooeyGeometry g, [Rect rect = _box]) => g.resolve(rect).gpu;

void main() {
  test('every built-in outline has a GPU description', () {
    expect(_gpu(const GooeyRoundedRect())!.type, GooeyGpuShape.typeRoundedRect);
    expect(_gpu(const GooeyCircle())!.type, GooeyGpuShape.typeRoundedRect);
    expect(
      _gpu(const GooeyCircle(), const Rect.fromLTWH(0, 0, 200, 100))!.type,
      GooeyGpuShape.typeRing,
    );
    expect(_gpu(const GooeyRing())!.type, GooeyGpuShape.typeRing);
    expect(_gpu(const GooeyStar())!.type, GooeyGpuShape.typePolygon);
    expect(_gpu(GooeyPolygon.regular(6))!.type, GooeyGpuShape.typePolygon);
    final path = GooeyPathGeometry((s) => Path()..addOval(Offset.zero & s));
    expect(_gpu(path)!.type, GooeyGpuShape.typeField);
  });

  test('ring: outer radius and half thickness', () {
    final g = _gpu(const GooeyRing(thickness: 0.4))!;
    expect(g.p1, 50);
    expect(g.p2, 10);
  });

  test('polygon: absolute vertices, too many corners falls back to CPU', () {
    final g = _gpu(const GooeyStar(points: 5))!;
    expect(g.vertices!.length, 20); // 10 corners, x and y
    // The top tip sits at the top centre of the rect.
    expect(g.vertices![0], closeTo(60, 1e-4));
    expect(g.vertices![1], closeTo(20, 1e-4));
    expect(_gpu(GooeyPolygon.regular(GooeyGpuShape.maxVertices + 1)), isNull);
  });

  test('path field: grid mapping matches the CPU field', () {
    final geometry = GooeyPathGeometry((s) => Path()..addOval(Offset.zero & s));
    final sdf = geometry.resolve(_box);
    final f = sdf.gpu!.field!;
    // The rect's top left maps to the margin (24 px / 2 px cells = 12).
    expect(10 * f.ax + f.bx, closeTo(12, 1e-9));
    expect(20 * f.ay + f.by, closeTo(12, 1e-9));
    // The sampled value at the centre is the distance there.
    final gx = 60 * f.ax + f.bx, gy = 70 * f.ay + f.by;
    final v = f.values[gy.round() * f.cols + gx.round()] * f.distanceScale;
    expect(v, closeTo(sdf.distance(60, 70), 1.5));
    expect(f.padded.left, closeTo(10 - 24, 1e-9));
  });

  test('without a loaded shader nothing claims to be drawable', () {
    expect(GooeyShader.isReady, isFalse);
    expect(
      GooeyShader.canDraw(GooeyShape(_box, const Color(0xFF000000))),
      isFalse,
    );
  });
}
