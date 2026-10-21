import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../tokens.dart';

/// Where a [FlyingIcon] starts or lands, in the flying icon's own box.
sealed class FlightPoint {
  const FlightPoint();

  /// The centre of the widget with [key] – wherever it is drawn right now,
  /// including paint-time transforms (a slide, a press). Mark the spot with
  /// an empty box of the icon's size (e.g. `SegmentTabs.selectedIconKey`).
  const factory FlightPoint.anchor(GlobalKey key) = _AnchorPoint;

  /// A point computed from the flying icon's own size, every frame – e.g.
  /// `(size) => size.center(Offset.zero)`.
  const factory FlightPoint.at(Offset Function(Size box) point) = _AtPoint;

  /// The point in [box]'s coordinates – or null if it is not ready (not
  /// laid out yet).
  Offset? resolve(RenderBox box);
}

class _AnchorPoint extends FlightPoint {
  const _AnchorPoint(this.key);
  final GlobalKey key;

  @override
  Offset? resolve(RenderBox box) {
    final target = key.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.attached || !target.hasSize) {
      return null;
    }
    if (!box.attached) return null;
    final global = target.localToGlobal(target.size.center(Offset.zero));
    return box.globalToLocal(global);
  }
}

class _AtPoint extends FlightPoint {
  const _AtPoint(this.point);
  final Offset Function(Size box) point;

  @override
  Offset? resolve(RenderBox box) => box.hasSize ? point(box.size) : null;
}

/// Flies [child] from [from] to [to] as [progress] goes from 0 to 1 – e.g.
/// the selected tab's icon flying into a button when a bar folds up
/// (secondary action). Fills its parent: put it in a `Positioned.fill` over
/// both points.
///
/// Everything happens at paint time (no rebuild, no layout per frame).
/// [progress] may overshoot (a spring): the position follows it, the
/// [arc] and [scale] do not. The child is decoration: it gets no touches
/// and no semantics (label the tab or the button instead).
///
/// With "Reduce motion" ([MotionScope.reduceMotionOf]) it does not fly: it
/// is at [from] until halfway and at [to] after.
class FlyingIcon extends StatelessWidget {
  const FlyingIcon({
    super.key,
    required this.progress,
    required this.from,
    required this.to,
    required this.child,
    this.arc = const Offset(0, -6),
    this.fromScale = 1,
    this.toScale = 1,
    this.repaint,
  });

  /// 0 = at [from], 1 = at [to].
  final Animation<double> progress;

  final FlightPoint from, to;

  /// How far the path bows out at mid-flight (px). Zero = a straight line.
  final Offset arc;

  /// The child's scale at each end.
  final double fromScale, toScale;

  /// Something else that moves the points (e.g. the animation that slides
  /// the tab), so the icon follows it while [progress] stands still.
  final Listenable? repaint;

  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: _Flight(
            progress: progress,
            from: from,
            to: to,
            arc: arc,
            fromScale: fromScale,
            toScale: toScale,
            repaint: repaint,
            jump: MotionScope.reduceMotionOf(context),
            child: child,
          ),
        ),
      );
}

class _Flight extends SingleChildRenderObjectWidget {
  const _Flight({
    required this.progress,
    required this.from,
    required this.to,
    required this.arc,
    required this.fromScale,
    required this.toScale,
    required this.repaint,
    required this.jump,
    required super.child,
  });

  final Animation<double> progress;
  final FlightPoint from, to;
  final Offset arc;
  final double fromScale, toScale;
  final Listenable? repaint;
  final bool jump;

  @override
  RenderFlyingIcon createRenderObject(BuildContext context) => RenderFlyingIcon(
        progress: progress,
        from: from,
        to: to,
        arc: arc,
        fromScale: fromScale,
        toScale: toScale,
        repaint: repaint,
        jump: jump,
      );

  @override
  void updateRenderObject(BuildContext context, RenderFlyingIcon r) {
    r
      ..progress = progress
      ..repaint = repaint
      ..from = from
      ..to = to
      ..arc = arc
      ..fromScale = fromScale
      ..toScale = toScale
      ..jump = jump;
  }
}

/// The render object behind [FlyingIcon]: takes all the space it gets, lays
/// its child out loosely and places it with a paint-time transform.
class RenderFlyingIcon extends RenderProxyBox {
  RenderFlyingIcon({
    required Animation<double> progress,
    required this.from,
    required this.to,
    required this.arc,
    required this.fromScale,
    required this.toScale,
    required bool jump,
    Listenable? repaint,
  })  : _progress = progress,
        _repaint = repaint,
        _jump = jump;

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) {
      _progress.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _progress = value;
    markNeedsPaint();
  }

  Listenable? _repaint;
  set repaint(Listenable? value) {
    if (identical(value, _repaint)) return;
    if (attached) {
      _repaint?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    _repaint = value;
    markNeedsPaint();
  }

  // Plain fields: a new value just repaints on the next frame.
  FlightPoint from, to;
  Offset arc;
  double fromScale, toScale;

  bool _jump;
  set jump(bool value) {
    if (value == _jump) return;
    _jump = value;
    markNeedsPaint();
  }

  final _layer = LayerHandle<TransformLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    child?.layout(constraints.loosen(), parentUsesSize: true);
  }

  /// The child's transform right now, or null if a point is not ready.
  Matrix4? _transform() {
    final c = child;
    if (c == null || !c.hasSize) return null;
    final a = from.resolve(this), b = to.resolve(this);
    if (a == null || b == null) return null;
    var t = _progress.value;
    if (_jump) t = t < 0.5 ? 0 : 1;
    final tc = t.clamp(0.0, 1.0);
    final centre = Offset.lerp(a, b, t)! + arc * math.sin(math.pi * tc);
    final scale = lerpDouble(fromScale, toScale, tc)!;
    final half = c.size.center(Offset.zero) * scale;
    return Matrix4.translationValues(
      centre.dx - half.dx,
      centre.dy - half.dy,
      0,
    )..multiply(Matrix4.diagonal3Values(scale, scale, 1));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final m = _transform();
    if (m == null) {
      _layer.layer = null;
      return;
    }
    _layer.layer = context.pushTransform(
      needsCompositing,
      offset,
      m,
      super.paint,
      oldLayer: _layer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final m = _transform();
    if (m != null) transform.multiply(m);
  }
}
