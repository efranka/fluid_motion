import 'package:flutter/rendering.dart';

import 'neck.dart';
import 'scene.dart';
import 'shader.dart';

/// Paints the necks between the shapes in a [GooeyScene] – with the GPU
/// shader when it is loaded and both shapes are rounded rects, otherwise
/// with the CPU version (which handles any outline). Put it UNDER the
/// shapes; the shapes paint themselves on top ([GooeySurface]).
class GooeyPainter extends CustomPainter {
  GooeyPainter(this.scene) : super(repaint: scene.repaint);

  final GooeyScene scene;

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
        if (gpu && a.isRoundedRect && b.isRoundedRect) {
          GooeyShader.paint(
            canvas,
            slot++,
            a,
            b,
            g,
            blendWidth: GooeyShader.blendWidthFor(field, i, j),
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
  bool shouldRepaint(GooeyPainter oldDelegate) => oldDelegate.scene != scene;
}
