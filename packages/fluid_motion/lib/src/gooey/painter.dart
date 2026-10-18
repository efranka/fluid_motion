import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'neck.dart';
import 'scene.dart';
import 'shader.dart';

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

  @override
  void paint(Canvas canvas, Size size) {
    final style = scene.style;
    if (!style.neck) return;
    final shapes = scene.shapes;
    if (shapes == null || shapes.length < 2) return;
    final field = scene.field;
    final gpu = style.useShader && GooeyShader.isReady;

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

  @override
  bool shouldRepaint(GooeyPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.pixelRatio != pixelRatio;
}
