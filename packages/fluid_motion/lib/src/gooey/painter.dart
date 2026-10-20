import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'light.dart';
import 'neck.dart';
import 'scene.dart';
import 'shader.dart';
import 'shape.dart';

/// Paints the necks between the shapes in a [GooeyScene] – on the GPU when
/// the shader is loaded (every built-in outline), otherwise with the CPU
/// fallback. Put it UNDER the shapes; the shapes paint themselves on top
/// ([GooeySurface]).
class GooeyPainter extends CustomPainter {
  GooeyPainter(this.scene, {this.pixelRatio = 1})
      : super(repaint: scene.repaint);

  final GooeyScene scene;

  /// Device pixels per logical pixel, for crisp anti-aliasing on the GPU.
  final double pixelRatio;

  // One shader instance per neck (uniforms belong to the instance).
  final List<ui.FragmentShader> _shaders = [];
  final List<ui.FragmentShader> _shadowShaders = [];

  @override
  void paint(Canvas canvas, Size size) {
    final style = scene.style;
    final shapes = scene.shapes;
    if (shapes == null || shapes.isEmpty) return;
    final gpu = style.useShader && GooeyShader.isReady;
    final light = style.light;
    if (gpu && light != null && light.shadows.isNotEmpty) {
      _paintShadows(canvas, shapes, light);
    }
    if (!style.neck || shapes.length < 2) return;
    final field = scene.field;

    var slot = 0;
    for (var i = 0; i < shapes.length; i++) {
      for (var j = i + 1; j < shapes.length; j++) {
        final g = scene.neckBetween(i, j);
        if (g == null) continue;
        final a = shapes[i], b = shapes[j];
        if (gpu && GooeyShader.canDraw(a) && GooeyShader.canDraw(b)) {
          while (_shaders.length <= slot) {
            _shaders.add(GooeyShader.newShader());
          }
          GooeyShader.paintNeck(
            canvas,
            _shaders[slot++],
            a,
            b,
            g,
            blendWidth: GooeyShader.blendWidthFor(field, i, j),
            pixelRatio: pixelRatio,
            light: light,
          );
        } else {
          GooeyNeckCpu.paint(
            canvas,
            a,
            b,
            g,
            style.neckStyle.cell,
            field: field,
          );
        }
      }
    }
  }

  /// The shadows under the merged shapes, in groups of four (the shader's
  /// slots); the first two of each group merge with their neck.
  void _paintShadows(Canvas canvas, List<GooeyShape> shapes, GooeyLight light) {
    if (!shapes.every(GooeyShader.canDraw)) return;
    var slot = 0;
    for (var start = 0; start < shapes.length; start += 4) {
      final group = shapes.sublist(start, math.min(start + 4, shapes.length));
      final neck = group.length > 1 && scene.style.neck
          ? scene.neckBetween(start, start + 1)
          : null;
      for (final shadow in light.shadows) {
        while (_shadowShaders.length <= slot) {
          _shadowShaders.add(GooeyShader.newShader());
        }
        GooeyShader.paintShadow(
          canvas,
          _shadowShaders[slot++],
          group,
          shadow,
          neck: neck,
        );
      }
    }
  }

  @override
  bool shouldRepaint(GooeyPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.pixelRatio != pixelRatio;
}
