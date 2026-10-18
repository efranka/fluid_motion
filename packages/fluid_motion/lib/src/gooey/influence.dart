import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Content (an icon, a text) that is "pulled" and dissolved when another
/// shape comes close to or over it – GRADED across the content: the part
/// closest to or deepest inside the other shape is pulled, blurred and faded
/// the most; the rest less or not at all.
///
/// Technique: the content is cut into [strips] thin strips across the pull
/// direction. Each strip moves towards the other shape by its own strength,
/// and because its leading edge moves more than its trailing edge the strip
/// stretches – piecewise linearly, so strips meet exactly and no seams
/// appear. Blur and fade are blended in with a gradient that follows the
/// strength, so each element is blurred only once regardless of the number
/// of strips. Works on any content (icons, text, images, cards) and in any
/// direction. The child is painted several times, so it must not itself be a
/// RepaintBoundary (the blur would then be lost).
///
/// [influenceAt] receives a point in global coordinates and returns
/// (strength 0..1, direction as a unit vector). Everything happens at paint
/// time: no rebuild and no relayout per frame, and the layers only exist
/// while the content is actually affected.
class GooeyInfluence extends SingleChildRenderObjectWidget {
  const GooeyInfluence({
    super.key,
    required this.animation,
    required this.influenceAt,
    super.child,
    this.enabled = true,
    this.maxPull = 10,
    this.maxBlur = 2.4,
    this.maxFade = 0.5,
    this.strips = 8,
  });

  final Listenable animation;
  final (double, Offset) Function(Offset globalPoint) influenceAt;
  final bool enabled;

  /// Max shift towards the other shape (px) for the most affected part. The
  /// difference between leading and trailing edge is what stretches it.
  final double maxPull;

  /// Max blur (sigma, px).
  final double maxBlur;

  /// How much the content fades out at most (0..1).
  final double maxFade;

  /// Number of strips. More = smoother transition, but more layers.
  final int strips;

  @override
  RenderGooeyInfluence createRenderObject(BuildContext context) =>
      RenderGooeyInfluence(
        animation: animation,
        influenceAt: influenceAt,
        enabled: enabled,
        maxPull: maxPull,
        maxBlur: maxBlur,
        maxFade: maxFade,
        strips: strips,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGooeyInfluence renderObject,
  ) {
    renderObject
      ..animation = animation
      ..influenceAt = influenceAt
      ..enabled = enabled
      ..maxPull = maxPull
      ..maxBlur = maxBlur
      ..maxFade = maxFade
      ..strips = strips;
  }
}

class RenderGooeyInfluence extends RenderProxyBox {
  RenderGooeyInfluence({
    required Listenable animation,
    required this.influenceAt,
    required bool enabled,
    required this.maxPull,
    required this.maxBlur,
    required this.maxFade,
    required int strips,
  })  : _animation = animation,
        _enabled = enabled,
        _strips = strips;

  (double, Offset) Function(Offset globalPoint) influenceAt;
  double maxPull, maxBlur, maxFade;

  Listenable _animation;
  set animation(Listenable value) {
    if (identical(value, _animation)) return;
    if (attached) {
      _animation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _animation = value;
    markNeedsPaint();
  }

  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  int _strips;
  set strips(int value) {
    if (value == _strips) return;
    _clearLayers();
    _strips = value;
    markNeedsPaint();
  }

  // Layers – reused between frames. The strips are painted twice (sharp and
  // blurred), and a layer can only have one parent, so each version has its
  // own.
  final _clipsSharp = <LayerHandle<ClipPathLayer>>[];
  final _transformsSharp = <LayerHandle<TransformLayer>>[];
  final _clipsBlur = <LayerHandle<ClipPathLayer>>[];
  final _transformsBlur = <LayerHandle<TransformLayer>>[];
  final _maskSharp = LayerHandle<ShaderMaskLayer>();
  final _maskBlur = LayerHandle<ShaderMaskLayer>();
  final _blur = LayerHandle<ImageFilterLayer>();

  void _ensureHandles(int count) {
    for (final list in [_clipsSharp, _clipsBlur]) {
      while (list.length < count) {
        list.add(LayerHandle<ClipPathLayer>());
      }
    }
    for (final list in [_transformsSharp, _transformsBlur]) {
      while (list.length < count) {
        list.add(LayerHandle<TransformLayer>());
      }
    }
  }

  void _clearLayers() {
    for (final h in [
      ..._clipsSharp,
      ..._transformsSharp,
      ..._clipsBlur,
      ..._transformsBlur,
      _maskSharp,
      _maskBlur,
      _blur,
    ]) {
      h.layer = null;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clearLayers();
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _enabled;

  /// Paints the content strip by strip, each with its own shift.
  void _paintStrips(
    PaintingContext context,
    Offset offset,
    List<(Path, Matrix4?)> segments,
    Rect bounds,
    List<LayerHandle<ClipPathLayer>> clips,
    List<LayerHandle<TransformLayer>> transforms,
  ) {
    final child = this.child!;
    for (var i = 0; i < segments.length; i++) {
      final (clip, transform) = segments[i];
      clips[i].layer = context.pushClipPath(
        needsCompositing,
        offset,
        bounds,
        clip,
        (context, offset) {
          if (transform == null) {
            transforms[i].layer = null;
            context.paintChild(child, offset);
          } else {
            transforms[i].layer = context.pushTransform(
              needsCompositing,
              offset,
              transform,
              (context, offset) => context.paintChild(child, offset),
              oldLayer: transforms[i].layer,
            );
          }
        },
        clipBehavior: Clip.hardEdge, // no anti-aliasing = no seams
        oldLayer: clips[i].layer,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_enabled) {
      context.paintChild(child, offset);
      return;
    }

    final c = size.center(Offset.zero);
    // The transform to global coordinates is computed ONCE per paint
    // (localToGlobal per point would walk the whole tree every time).
    final toGlobal = getTransformTo(null);
    Offset global(Offset p) => MatrixUtils.transformPoint(toGlobal, p);

    final (fCenter, rawDir) = influenceAt(global(c));
    // Without a usable direction (or size) there is nothing to pull along:
    // paint the content as it is.
    final dirLen = rawDir.distance;
    if (dirLen < 1e-6 || size.isEmpty || !dirLen.isFinite) {
      _clearLayers();
      context.paintChild(child, offset);
      return;
    }
    final dir = rawDir / dirLen;
    final cosA = dir.dx, sinA = dir.dy;

    // The content's extent along (L) and across (V) the direction.
    final halfL =
        (size.width / 2 * cosA).abs() + (size.height / 2 * sinA).abs();
    final halfV =
        (size.width / 2 * sinA).abs() + (size.height / 2 * cosA).abs();

    // Fast exit: if neither the middle nor the ends are affected, skip the
    // other measurements (true for the vast majority of frames).
    final n = _strips;
    final f = List<double>.filled(n + 1, 0);
    if (dir != Offset.zero) {
      f[0] = influenceAt(global(c - dir * halfL)).$1.clamp(0.0, 1.0);
      f[n] = influenceAt(global(c + dir * halfL)).$1.clamp(0.0, 1.0);
    }
    var fMax = math.max(fCenter.clamp(0.0, 1.0), math.max(f[0], f[n]));
    if (fMax > 0.001) {
      // The strength at the strips' inner edges, measured along the direction.
      for (var k = 1; k < n; k++) {
        final u = -halfL + 2 * halfL * k / n;
        f[k] = influenceAt(global(c + dir * u)).$1.clamp(0.0, 1.0);
        fMax = math.max(fMax, f[k]);
      }
    }
    if (fMax <= 0.001 || dir == Offset.zero) {
      _clearLayers();
      context.paintChild(child, offset);
      return;
    }

    final big = halfL + maxPull + 3 * maxBlur + 4;
    final v = halfV + 3 * maxBlur + 4;
    final bounds = (Offset.zero & size).inflate(big);
    final a = math.atan2(sinA, cosA);
    Offset toLocal(double x, double y) =>
        c + Offset(x * cosA - y * sinA, x * sinA + y * cosA);

    // The strips: source [u0, u1] is mapped exactly onto [d0, d1] along the
    // direction. Neighbours that are not affected at all are merged into one
    // piece without a transform, so unaffected parts cost almost nothing.
    final d = [
      for (var k = 0; k <= n; k++) -halfL + 2 * halfL * k / n + maxPull * f[k],
    ];
    // Never fold the content: each edge must lie after the previous one.
    final minStep = 0.25 * 2 * halfL / n;
    for (var k = 1; k <= n; k++) {
      if (d[k] < d[k - 1] + minStep) d[k] = d[k - 1] + minStep;
    }
    final segments = <(Path, Matrix4?)>[];
    var runStart = -big;
    var k = 0;
    while (k < n) {
      final u0 = -halfL + 2 * halfL * k / n;
      final u1 = -halfL + 2 * halfL * (k + 1) / n;
      final last = k == n - 1;
      final x0 = segments.isEmpty ? runStart : d[k];
      final x1 = last ? big : d[k + 1];
      Path strip(double from, double to) => Path()
        ..addPolygon([
          toLocal(from, -v),
          toLocal(to, -v),
          toLocal(to, v),
          toLocal(from, v),
        ], true);

      if (f[k] <= 0.001 && f[k + 1] <= 0.001) {
        // Unaffected: extend to the next affected strip.
        var end = k + 1;
        while (end < n && f[end] <= 0.001 && f[end + 1] <= 0.001) {
          end++;
        }
        final to = end >= n ? big : d[end];
        segments.add((strip(x0, to), null));
        k = end;
        continue;
      }
      final scale = (d[k + 1] - d[k]) / (u1 - u0);
      final transform = Matrix4.translationValues(c.dx, c.dy, 0)
        ..multiply(Matrix4.rotationZ(a))
        ..multiply(Matrix4.translationValues(d[k] - u0 * scale, 0, 0))
        ..multiply(Matrix4.diagonal3Values(scale, 1, 1))
        ..multiply(Matrix4.rotationZ(-a))
        ..multiply(Matrix4.translationValues(-c.dx, -c.dy, 0));
      segments.add((strip(x0, x1), transform));
      k++;
    }
    _ensureHandles(segments.length);

    // Blur and fade: instead of blurring each strip on its own (8 blurs),
    // the content is painted twice – sharp and blurred ONCE – and blended
    // with a gradient along the direction that follows the strength. The fade
    // lives in the same gradient. At most three extra surfaces per affected
    // element, regardless of the number of strips.
    final sigma = maxBlur * fMax;
    // A child that is itself a repaint boundary can only be painted once.
    final useBlur = sigma > 0.3 && !child.isRepaintBoundary;
    final from = toLocal(d[0], 0) - bounds.topLeft;
    final to = toLocal(d[n], 0) - bounds.topLeft;
    final stops = [
      for (var k = 0; k <= n; k++)
        d[n] == d[0] ? k / n : (d[k] - d[0]) / (d[n] - d[0]),
    ];
    Color white(double alpha) =>
        Color.fromARGB((255 * alpha.clamp(0.0, 1.0)).round(), 255, 255, 255);
    final sharpColors = [
      for (var k = 0; k <= n; k++)
        white((1 - maxFade * f[k]) * (useBlur ? 1 - f[k] / fMax : 1)),
    ];
    final maskRect = bounds.shift(offset);

    final sharp = _maskSharp.layer ??= ShaderMaskLayer();
    sharp
      ..shader = ui.Gradient.linear(from, to, sharpColors, stops)
      ..maskRect = maskRect
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      sharp,
      (context, offset) => _paintStrips(
        context,
        offset,
        segments,
        bounds,
        _clipsSharp,
        _transformsSharp,
      ),
      offset,
      childPaintBounds: bounds,
    );

    if (!useBlur) {
      _maskBlur.layer = null;
      _blur.layer = null;
      return;
    }
    final blurColors = [
      for (var k = 0; k <= n; k++) white((1 - maxFade * f[k]) * f[k] / fMax),
    ];
    final blurred = _maskBlur.layer ??= ShaderMaskLayer();
    blurred
      ..shader = ui.Gradient.linear(from, to, blurColors, stops)
      ..maskRect = maskRect
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      blurred,
      (context, offset) {
        // Most blur along the direction – like motion blur.
        final blur = _blur.layer ??= ImageFilterLayer();
        blur.imageFilter = ui.ImageFilter.blur(
          sigmaX: math.max(sigma * (0.35 + 0.65 * cosA.abs()), 0.01),
          sigmaY: math.max(sigma * (0.35 + 0.65 * sinA.abs()), 0.01),
          tileMode: TileMode.decal,
        );
        context.pushLayer(
          blur,
          (context, offset) => _paintStrips(
            context,
            offset,
            segments,
            bounds,
            _clipsBlur,
            _transformsBlur,
          ),
          offset,
          childPaintBounds: bounds,
        );
      },
      offset,
      childPaintBounds: bounds,
    );
  }
}
