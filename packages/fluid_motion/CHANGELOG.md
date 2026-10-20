## Unreleased

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
