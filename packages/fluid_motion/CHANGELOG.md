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
