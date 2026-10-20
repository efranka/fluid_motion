/// fluid_motion – organic, physics-driven animation for Flutter, built on
/// "The twelve basic principles of animation".
///
/// Everything here is generic and knows nothing about the elements it is
/// used on.
///
/// Foundations
///  • [EnergySpring], [SpringMotion] – speed → spring (graded bounce)
///  • [rubberBand], [Ramp], [directionalStretch]
///  • [MotionTokens], [MotionScope] – a shared "material" for the whole app
///  • [MotionQuality], [MotionFeature] – automatic quality: expensive
///    effects switch off when the device cannot keep up, and back on later
///  • [MotionWarmUp] – prepares the GPU at startup, so animations do not
///    stutter the first time they run
///
/// Widgets
///  • [PressScale] / [PressSpring] – press feedback (also shared by layers)
///  • [MotionTransform] – transform at paint time (no rebuild)
///  • [SegmentSpring] + [SegmentIndicatorPainter] – stretchy tab indicator
///
/// Movement
///  • [DragSpringController] + [MorphFollower] – "the finger drives, the
///    spring takes over" for bottom bars, sheets and cards
///
/// Gooey (shapes as fluid material)
///  • [GooeyScene] + [GooeyStage], [GooeyBackdrop], [GooeySurface],
///    [GooeyContent] – neck, colour blending, blobs and dissolving content
///  • Outlines: [GooeyRoundedRect], [GooeyCircle], [GooeyRing],
///    [GooeyPolygon], [GooeyStar], [GooeyPathGeometry] – or your own
///    [GooeyGeometry]
///  • [GooeyShader] – the GPU version (the CPU version is the fallback)
///  • Building blocks: [GooeyShape], [GooeyContact], [ContactTracker],
///    [GooeyColorField], [GooeyNeckGeometry], [GooeyInfluence],
///    [traceContour], [smoothMin]
library;

export 'src/drag/drag_spring_controller.dart';
export 'src/foundation/ramp.dart';
export 'src/foundation/springs.dart';
export 'src/foundation/stretch.dart';
export 'src/gooey/contact.dart';
export 'src/gooey/contour.dart';
export 'src/gooey/field.dart';
export 'src/gooey/fill.dart';
export 'src/gooey/geometry.dart';
export 'src/gooey/influence.dart';
export 'src/gooey/light.dart';
export 'src/gooey/neck.dart';
export 'src/gooey/painter.dart';
export 'src/gooey/scene.dart';
export 'src/gooey/shader.dart';
export 'src/gooey/shape.dart';
export 'src/gooey/widgets.dart';
export 'src/quality/motion_quality.dart';
export 'src/tokens.dart';
export 'src/warm_up.dart';
export 'src/widgets/motion_transform.dart';
export 'src/widgets/press.dart';
export 'src/widgets/segment.dart';
