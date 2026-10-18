import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'scene.dart';
import 'shader.dart';
import 'shape.dart';

/// The background of shape [index] in a [GooeyScene]: the shape's own
/// colour, blended with other shapes' colours near a contact, and deformed
/// when it blobs. Use it instead of the shape's own background, UNDER the
/// shape's content. Repaints without rebuilding.
///
/// Drawn on the GPU when the shader is loaded; otherwise on the CPU.
///
/// The painter's size must match the shape's rect in the scene.
class GooeyFillPainter extends CustomPainter {
  GooeyFillPainter(
    this.scene,
    this.index, {
    this.fallbackColor,
    this.cell = 4,
    this.pixelRatio = 1,
  }) : super(repaint: scene.repaint);

  final GooeyScene scene;
  final int index;

  /// The colour used before the scene is ready (first frame).
  final Color? fallbackColor;

  /// The colour grid's resolution in px (CPU fallback only).
  final double cell;

  /// Device pixels per logical pixel, for crisp anti-aliasing on the GPU.
  final double pixelRatio;

  ui.FragmentShader? _shader;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shapes = scene.shapes;
    if (shapes == null || index >= shapes.length) {
      final c = fallbackColor ??
          (index < scene.members.length ? scene.members[index].color : null);
      if (c == null) return;
      final m = index < scene.members.length ? scene.members[index] : null;
      final path = m == null
          ? (Path()..addRRect(_pill(size)))
          : GooeyShape(Offset.zero & size, c,
                  radius: m.radius, geometry: m.geometry)
              .basePath;
      canvas.drawPath(path, Paint()..color = c);
      return;
    }
    final s = shapes[index];
    final o = s.rect.topLeft;
    final f = scene.field;

    if (scene.style.useShader && GooeyShader.canDraw(s)) {
      // The other shape this one is most connected to, if any.
      GooeyShape? other;
      var width = 0.0;
      if (f != null && f.mixing) {
        var best = 0.0;
        for (var j = 0; j < shapes.length; j++) {
          final st = f.strengthOf(index, j);
          if (st > best) {
            best = st;
            other = shapes[j];
            width = f.widthOf(index, j);
          }
        }
      }
      if (other == null || GooeyShader.canDraw(other)) {
        GooeyShader.paintSurface(
          canvas,
          _shader ??= GooeyShader.newShader(),
          s,
          other: other,
          blendWidth: width,
          pixelRatio: pixelRatio,
        );
        return;
      }
    }

    // CPU fallback.

    // The outline in local coordinates: the deformed one while blobbing,
    // otherwise the plain one (a rounded rect is drawn directly – cheapest).
    final Path? path = s.rippling
        ? s.outline().shift(-o)
        : (s.isRoundedRect ? null : s.basePath.shift(-o));
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s.cornerRadius),
    );
    void fill(Paint paint) => path == null
        ? canvas.drawRRect(rrect, paint)
        : canvas.drawPath(path, paint);
    void clipShape() =>
        path == null ? canvas.clipRRect(rrect) : canvas.clipPath(path);

    var active =
        f != null && f.mixing ? f.activeRect(index).shift(-o) : Rect.zero;
    if (path != null && active.width > 0 && active.height > 0) {
      active = active.intersect(path.getBounds().inflate(1));
    }
    if (active.width <= 0 || active.height <= 0) {
      fill(Paint()..color = s.color);
      return;
    }
    // Most of the shape is just its own colour – only the active part is
    // painted from the field. The two parts do not overlap (hard clips), so
    // there is no seam between them.
    canvas.save();
    canvas.clipRect(active, clipOp: ui.ClipOp.difference, doAntiAlias: false);
    fill(Paint()..color = s.color);
    canvas.restore();
    canvas.save();
    canvas.clipRect(active, doAntiAlias: false);
    clipShape();
    f!.paint(canvas, active.shift(o), origin: o, cell: cell);
    canvas.restore();
  }

  static RRect _pill(Size size) => RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.shortestSide / 2),
      );

  @override
  bool shouldRepaint(GooeyFillPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.index != index ||
      oldDelegate.cell != cell ||
      oldDelegate.pixelRatio != pixelRatio;
}
