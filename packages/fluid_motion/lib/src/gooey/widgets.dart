import 'package:flutter/widgets.dart';

import 'fill.dart';
import 'influence.dart';
import 'painter.dart';
import 'scene.dart';

/// The scene's coordinate system: a [Stack] whose top left corner is (0, 0)
/// for every rect in [GooeyScene.members]. Put the shapes, their content and
/// the [GooeyBackdrop] in here.
class GooeyStage extends StatelessWidget {
  const GooeyStage({
    super.key,
    required this.scene,
    required this.children,
    this.clipBehavior = Clip.hardEdge,
  });

  final GooeyScene scene;
  final List<Widget> children;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) => Stack(
        key: scene.stageKey,
        clipBehavior: clipBehavior,
        children: children,
      );
}

/// The necks between the shapes. Fills the whole [GooeyStage] and must lie
/// UNDER the shapes.
class GooeyBackdrop extends StatelessWidget {
  const GooeyBackdrop({super.key, required this.scene});

  final GooeyScene scene;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: GooeyPainter(
                scene,
                pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
              ),
            ),
          ),
        ),
      );
}

/// The background of shape [index]: blends colour, blobs, and follows the
/// shape's outline. Must have the same size as the shape's rect (e.g. in a
/// Positioned with the same measurements).
class GooeySurface extends StatelessWidget {
  const GooeySurface({
    super.key,
    required this.scene,
    required this.index,
    this.child,
  });

  final GooeyScene scene;
  final int index;

  /// Content on top of the background (optional). Lives in its own layer.
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: GooeyFillPainter(
          scene,
          index,
          pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        ),
        child: RepaintBoundary(child: child ?? const SizedBox.expand()),
      );
}

/// Content in shape [index] that is pulled, blurred and gradually dissolved
/// when another shape in the scene comes close to or over it.
class GooeyContent extends StatelessWidget {
  const GooeyContent({
    super.key,
    required this.scene,
    required this.index,
    required this.child,
    this.maxPull = 10,
    this.maxBlur = 2.4,
    this.maxFade = 0.5,
    this.strips = 8,
  });

  final GooeyScene scene;
  final int index;
  final Widget child;
  final double maxPull, maxBlur, maxFade;
  final int strips;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GooeyStyle>(
        // Rebuilt when e.g. automatic quality switches the effect on or off.
        valueListenable: scene.styleListenable,
        builder: (context, style, child) => GooeyInfluence(
          animation: scene.repaint,
          enabled: style.contentBlend,
          influenceAt: (global) => scene.influenceOn(index, global),
          maxPull: maxPull,
          maxBlur: maxBlur,
          maxFade: maxFade,
          strips: strips,
          child: child!,
        ),
        child: child,
      );
}
