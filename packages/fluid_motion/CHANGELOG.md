## 0.5.1 – 2026-10-23

- Fix: the edge light and shadow came out as nothing on an iPhone 11 (A13)
  in Safari, while the shapes were drawn. The shader's uniforms are
  reordered: everything but the vertices comes first, and the vertices are
  packed two per `vec4` and come last, so a rounded rect, circle or ring
  reads only the first 46 vec4 slots (before: up to 138). The Dart side
  writes the same 376 floats in the new order.
- A `GooeyMember` whose `rect` returns null is left out; the other shapes
  still merge and light (before, the whole scene was "not ready" and drawn
  flat). `GooeyScene.shapes` holds the members that have a rect, and
  `GooeyScene.shapeIndexOf(member)` maps a member to its place in it –
  the same index while every member has a rect.
- Docs: the layer order in a `GooeyStage` (backdrop, every surface, then
  every shape's content) – content in `GooeySurface.child` is covered by a
  later surface.
- The edge light is never switched off by `MotionQuality` (tested).

## 0.5.0 – 2026-10-21

- `SegmentTabs`: tabs with a stretchy indicator (`SegmentSpring` +
  `SegmentIndicatorPainter`). Colours and shapes are parameters. Each tab is
  a button for screen readers, focusable with a visible focus ring and
  Enter/Space, at least 48 × 48; labels wrap or get an ellipsis instead of
  shrinking with large text. "Reduce motion": the indicator jumps.
- `FlyingIcon` + `FlightPoint`: a widget flies from an anchor (a keyed spot,
  e.g. `SegmentTabs.selectedIconKey`) to a target along an arc, at paint
  time. "Reduce motion": it jumps halfway instead of flying.
- `SegmentSpring` takes its `lead` and `trail` springs; `SegmentTabs` uses
  `MotionTokens.indicatorLeadStiffness`/`indicatorTrailStiffness`.
  `SegmentIndicatorPainter` takes a corner `radius`.
- Example: the bottom bar uses `SegmentTabs` and `FlyingIcon` (its own tab
  widget is gone).

## 0.4.0 – 2026-10-21

- Edge light: `GooeyStyle(light: GooeyLight(...))` draws an edge with a
  gradient, a fill gradient, inner glows (from the ends of an axis and along
  the outline) and shadows along the MERGED outline – the edge runs on along
  the neck and vanishes where the shapes have flowed together. Every measure
  and colour is a parameter, every part optional, any outline. GPU only.
- `GooeyShader.paintNeck` and `paintSurface` take `light`; `paintSurface`
  also `necks`. New `GooeyShader.paintShadow`. `GooeyBackdrop` draws the
  shadows, so use it whenever the light has shadows.
- The shader has a third mode (shadows) and 18 more uniforms;
  `test/shader_uniforms_test.dart` checks the writer against the shader.
- Example: an Edge light demo, compared with plain Flutter.

## 0.3.0 – 2026-10-20

- "Reduce motion" is respected by the components themselves.
  `PressScale` does not squeeze, and `GooeyStage` switches the scene's
  effects off (`GooeyScene.reduceMotion`), with no code in the app.
- `MotionScope(reduceMotion:)` forces "Reduce motion" on or off below it
  (an in-app setting, or a test); `reduceMotionOf` reads it before the
  system setting.
- `DragSpringController.reduceMotion` now also makes every spring critically
  damped (followers too, even with a loose spring), lets followers move
  without their delay, returns the rubber band without a bounce, and never
  calls `onOvershoot`.
- `PressSpring.reduceMotion`, set by `PressScale`.

## 0.2.0 – 2026-10-20

- Colour blending with several touching shapes: a shape between two others
  now blends towards both, with no hard edge where one takes over. Up to
  `GooeyShader.maxNeighbours` (3) neighbours at once, set with
  `GooeyStyle.blendNeighbours`. `MotionQuality` drops it to one neighbour
  first (`MotionFeature.multiBlend`).
- `GooeyShader.paintSurface` takes `others` and `blendWidths` lists instead
  of `other` and `blendWidth`.
- `ScrollMorphBehavior`: choose which scrolls fold and unfold a
  `DragSpringController` (`collapse`: forward, any movement or never;
  `expand`: backward, at the start or never; which axes; nested
  scrollables or not). `collapseOnly` folds on any scroll and only unfolds
  on a tap.
- `handleScrollNotification` ignores nested and horizontal scrollables by
  default, so a carousel in the list no longer folds the bar.
- `dragStart` resets the measured drag distance between drags.
- Contact between shapes with holes (a ring) is measured robustly.

## 0.1.0

First release.

- `EnergySpring` and `SpringMotion`: springs whose bounce is graded by speed.
- `DragSpringController` + `MorphFollower`: "the finger drives, the spring
  takes over" for bottom bars, sheets and cards, driven by scroll or drag.
  The bounce survives dropped frames.
- `PressScale`/`PressSpring`, `MotionTransform`, `SegmentSpring`,
  `directionalStretch`, `rubberBand`, `Ramp`.
- `MotionTokens`/`MotionScope`: shared motion tokens.
- Gooey: `GooeyScene` with neck, colour blending, blobs on catch and release,
  and content dissolving into another shape. Any number of shapes and any
  outline: rounded rect, circle, ring, polygon, star, any `Path`, or your own
  `GooeyGeometry`.
- `GooeyShader`: everything gooey on the GPU (necks and surfaces with colour
  blend and blobs) for every built-in outline, with an automatic CPU fallback.
- `MotionQuality`: automatic quality that switches expensive effects off when
  the device cannot keep up (including Low Power Mode) and back on later.
- `MotionWarmUp`: prepares the GPU at startup, so animations do not stutter
  the first time they run.
