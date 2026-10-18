import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Moves, scales or rotates [child] from a value computed every frame –
/// without rebuild and without new layout. The cheapest way to animate
/// something that should not change size in the layout (an icon gliding, an
/// element lagging behind, a press).
///
/// [transform] is called on every paint with the child's size and returns a
/// transform around the [alignment] point. Hit testing follows the
/// transform.
class MotionTransform extends SingleChildRenderObjectWidget {
  const MotionTransform({
    super.key,
    required this.animation,
    required this.transform,
    this.alignment = Alignment.center,
    super.child,
  });

  final Listenable animation;
  final Matrix4 Function(Size size) transform;
  final Alignment alignment;

  @override
  RenderMotionTransform createRenderObject(BuildContext context) =>
      RenderMotionTransform(
        animation: animation,
        transform: transform,
        alignment: alignment,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMotionTransform renderObject,
  ) {
    renderObject
      ..animation = animation
      ..transform = transform
      ..alignment = alignment;
  }
}

class RenderMotionTransform extends RenderProxyBox {
  RenderMotionTransform({
    required Listenable animation,
    required Matrix4 Function(Size size) transform,
    required Alignment alignment,
  })  : _animation = animation,
        _transform = transform,
        _alignment = alignment;

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

  Matrix4 Function(Size size) _transform;
  set transform(Matrix4 Function(Size size) value) {
    _transform = value;
    markNeedsPaint();
  }

  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsPaint();
  }

  final _layer = LayerHandle<TransformLayer>();

  Matrix4 get _effective {
    final o = _alignment.alongSize(size);
    return Matrix4.translationValues(o.dx, o.dy, 0)
      ..multiply(_transform(size))
      ..multiply(Matrix4.translationValues(-o.dx, -o.dy, 0));
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
    _layer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final m = _effective;
    if (m.isIdentity()) {
      _layer.layer = null;
      super.paint(context, offset);
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
      result.addWithPaintTransform(
        transform: _effective,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_effective);
  }
}
