import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'gooey/geometry.dart';
import 'gooey/neck.dart';
import 'gooey/shader.dart';
import 'gooey/shape.dart';

/// Removes the stutter the first few times an animation runs.
///
/// The first time the GPU draws something new – the gooey shader, a blur of
/// a given strength, a gradient mask – it compiles a small GPU program for
/// it, right in the middle of the animation. That is the hitch you see the
/// first couple of times; afterwards the programs are cached and it runs
/// smoothly. This is most noticeable on the web.
///
/// [MotionWarmUp] draws every technique fluid_motion uses once, faintly and
/// hidden behind [child], during the first few frames – so the programs are
/// ready before the user touches anything. Wrap your app with it (below
/// [MotionScope] is fine). Load the shader first with [GooeyShader.load].
///
/// It draws a small area in the top left corner for [frames] frames, behind
/// [child]. With an opaque app background it is invisible.
class MotionWarmUp extends StatefulWidget {
  const MotionWarmUp({
    super.key,
    required this.child,
    this.frames = 3,
    this.maxBlur = 2.4,
    this.strips = 8,
    this.enabled = true,
  });

  final Widget child;

  /// How many frames to draw the warm-up for.
  final int frames;

  /// The strongest blur to prepare (match [GooeyContent.maxBlur]).
  final double maxBlur;

  /// The strip count to prepare masks for (match [GooeyContent.strips]).
  final int strips;

  /// Switch it off (e.g. in tests).
  final bool enabled;

  @override
  State<MotionWarmUp> createState() => _MotionWarmUpState();
}

class _MotionWarmUpState extends State<MotionWarmUp> {
  late int _left = widget.enabled ? widget.frames : 0;

  @override
  void initState() {
    super.initState();
    if (_left > 0) SchedulerBinding.instance.addPostFrameCallback(_next);
  }

  void _next(Duration _) {
    if (!mounted) return;
    setState(() => _left--);
    if (_left > 0) SchedulerBinding.instance.addPostFrameCallback(_next);
  }

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.topLeft,
        textDirection: TextDirection.ltr,
        fit: StackFit.expand,
        children: [
          // Always two children in the same order, so [child] keeps its
          // state when the warm-up is done.
          if (_left > 0)
            Positioned(
              left: 0,
              top: 0,
              width: 96,
              height: 48,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WarmUpPainter(
                    frame: _left,
                    maxBlur: widget.maxBlur,
                    strips: widget.strips,
                  ),
                ),
              ),
            )
          else
            const Positioned(left: 0, top: 0, child: SizedBox.shrink()),
          widget.child,
        ],
      );
}

class _WarmUpPainter extends CustomPainter {
  _WarmUpPainter({
    required this.frame,
    required this.maxBlur,
    required this.strips,
  });

  final int frame;
  final double maxBlur;
  final int strips;

  // Almost transparent: GPU programs do not depend on the colour values.
  static const _faint = Color(0x05FFFFFF);
  static const _faint2 = Color(0x05FF00FF);

  @override
  void paint(Canvas canvas, Size size) {
    const area = Rect.fromLTWH(0, 0, 48, 48);
    final faint = Paint()..color = _faint;

    // The gooey shader: a neck and a surface with blend and a blob.
    if (GooeyShader.isReady) {
      final a = GooeyShape(
        const Rect.fromLTWH(0, 12, 40, 24),
        _faint,
        ripples: const [GooeyRipple(Offset(40, 24), 3, radius: 8)],
      );
      final b = GooeyShape(
        const Rect.fromLTWH(44, 12, 24, 24),
        _faint2,
        geometry: const GooeyStar(),
      );
      final g = GooeyNeckGeometry.between(a, b, const GooeyNeckStyle());
      if (g != null) {
        GooeyShader.paintNeck(canvas, GooeyShader.newShader(), a, b, g,
            blendWidth: 20);
      }
      canvas.save();
      canvas.translate(a.rect.left, a.rect.top);
      GooeyShader.paintSurface(canvas, GooeyShader.newShader(), a,
          others: [b], blendWidths: const [20]);
      canvas.restore();
    }

    // Blurs: one GPU program per kernel size and direction, so prepare every
    // strength up to [maxBlur], round and stretched both ways (content
    // blends blur most along the pull direction).
    for (var s = 0.3; s <= maxBlur + 0.3; s += 0.3) {
      for (final (sx, sy) in [(s, s), (s, s * 0.35), (s * 0.35, s)]) {
        canvas.saveLayer(
          area,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sx,
              sigmaY: sy,
              tileMode: TileMode.decal,
            ),
        );
        canvas.drawRect(const Rect.fromLTWH(8, 8, 16, 16), faint);
        canvas.restore();
      }
    }

    // Gradient masks (what a ShaderMask/ShaderMaskLayer draws), with as
    // many stops as the content blend uses.
    for (final n in {2, strips + 1}) {
      canvas.saveLayer(area, Paint());
      canvas.drawRect(area, faint);
      canvas.drawRect(
        area,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset.zero,
            const Offset(48, 0),
            [for (var k = 0; k < n; k++) _faint],
            [for (var k = 0; k < n; k++) k / (n - 1)],
          ),
      );
      canvas.restore();
    }

    // Opacity layers, clips, anti-aliased paths and vertex colours (the CPU
    // fallback's colour field).
    canvas.saveLayer(area, Paint()..color = const Color(0x80000000));
    canvas.clipRRect(RRect.fromRectAndRadius(area, const Radius.circular(12)));
    canvas.drawPath(Path()..addOval(area.deflate(4)), faint);
    canvas.restore();
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.fromList([0, 0, 48, 0, 0, 48]),
        colors: Int32List.fromList([0x05FFFFFF, 0x05FF00FF, 0x0500FFFF]),
      ),
      BlendMode.dst,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_WarmUpPainter old) => old.frame != frame;
}
