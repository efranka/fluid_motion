import 'package:flutter/material.dart';
import 'package:fluid_motion/fluid_motion.dart';

/// Draws a [GooeyLight] on ONE shape the plain Flutter way – a decorated
/// box with a gradient and shadows, a painter for the glow and a stroked
/// outline for the edge. The reference the gooey version is compared with:
/// apart, the two should look the same.
///
/// Not drawn here: [GooeyLight.outlineGlow] (plain Flutter has no inner
/// glow along an outline).
class FlatLight extends StatelessWidget {
  const FlatLight({
    super.key,
    required this.light,
    required this.color,
    this.shape = const StadiumBorder(),
    this.child,
  });

  final GooeyLight light;
  final Color color;
  final ShapeBorder shape;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final start = Color.alphaBlend(light.fillStart, color);
    final end = Color.alphaBlend(light.fillEnd, color);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        gradient: LinearGradient(
          begin: light.begin,
          end: light.end,
          colors: [start, end],
        ),
        shadows: light.shadows,
      ),
      child: CustomPaint(
        painter: _Glow(light, shape),
        foregroundPainter: _Edge(light, shape),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

/// The glow from the start and the end of the axis, clipped to the shape.
class _Glow extends CustomPainter {
  const _Glow(this.light, this.shape);
  final GooeyLight light;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final a = light.begin.withinRect(r), b = light.end.withinRect(r);
    final len = (b - a).distance;
    if (len <= 0) return;
    final depth = light.glowDepth.clamp(0.0, len / 2) / len;
    canvas.save();
    canvas.clipPath(shape.getOuterPath(r));
    void glow(Color c, Offset from, Offset to) {
      if (c.a <= 0) return;
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(
              (from.dx / size.width) * 2 - 1,
              (from.dy / size.height) * 2 - 1,
            ),
            end: Alignment(
              (to.dx / size.width) * 2 - 1,
              (to.dy / size.height) * 2 - 1,
            ),
            colors: [c, c.withValues(alpha: 0)],
          ).createShader(r),
      );
    }

    glow(light.glowStart, a, Offset.lerp(a, b, depth)!);
    glow(light.glowEnd, b, Offset.lerp(b, a, depth)!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Glow old) => old.light != light || old.shape != shape;
}

/// The edge: a stroke half its width inside the outline.
class _Edge extends CustomPainter {
  const _Edge(this.light, this.shape);
  final GooeyLight light;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final w = light.edgeWidth;
    if (w <= 0) return;
    final r = Offset.zero & size;
    final colors = light.edgeColors;
    canvas.drawPath(
      shape.getOuterPath(r.deflate(w / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: light.begin,
          end: light.end,
          colors: colors.length == 1 ? [colors[0], colors[0]] : colors,
          stops: colors.length == 1 ? null : light.edgeStops,
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_Edge old) => old.light != light || old.shape != shape;
}
