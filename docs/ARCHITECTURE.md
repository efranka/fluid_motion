# Architecture

How fluid_motion is put together, for whoever changes it next. Public API
usage is in the README; this file is about the inside.

## Motion core

**`EnergySpring`** (`foundation/springs.dart`) – a spring whose damping ratio
depends on the speed it starts with: below `calmSpeed` (300 px/s) ratio 1.0
(no bounce), above `wildSpeed` (2500 px/s) ratio 0.35, eased in between. So a
slow gesture glides in and a fast one bounces. `MotionTokens` holds the
shared springs (`primary`, `secondary`, `follower`, press) and `MotionScope`
passes them down, together with `reduceMotionOf(context)`.

**`DragSpringController`** (`drag/drag_spring_controller.dart`) – two states,
0 and 1, on an unbounded `AnimationController` (`value`).

- While a finger drags, `value` follows it directly (`distance` px = 0→1).
- On release, or the moment the value hits 0 or 1 mid-drag, a spring takes
  over with the finger's exact velocity (`animateTo`, graded by
  `EnergySpring.forSpeed`).
- `VelocityTracker` reports 0 when touches arrive with 40 ms+ gaps (a dropped
  frame), so the velocity measured from the scrolled distance over real time
  is used when it is larger. Without that the bounce disappears at low fps.
- `onOvershoot` fires once per animation when the target is crossed – used
  for the "impact" on the navigation bar. At low fps the spring can turn
  within one frame, so the previous frame's velocity is used then.
- `MorphFollower`s get their own spring and an optional delay (overlapping
  action); they start immediately when already moving with the finger.
- Scroll: `handleScrollNotification(n, behavior:)`. `ScrollMorphBehavior`
  filters by depth (`nested`) and axis (`axes`), then maps the scroll delta:
  `anyMovement` turns every delta positive (towards 1); deltas towards 1 are
  dropped when `collapse` is `never`, deltas towards 0 unless `expand` is
  `backward`; `atStart` unfolds when a scroll back reaches the start. The
  velocity for scrolls is measured from the accumulated (mapped) delta, not
  from `metrics.pixels`, so two-axis scrolling does not mix positions.

**Reduce motion.** `MotionScope.reduceMotionOf` = the nearest
`MotionScope.reduceMotion`, else `MediaQuery.disableAnimations`. Widgets read
it themselves: `PressScale` sets `PressSpring.reduceMotion` in build (only a
flag – the scale changes on the next press, since other layers may share the
spring), and `GooeyStage` sets `GooeyScene.reduceMotion` in build, which
`_limited` applies on top of the requested style (safe during build because
everything listening to the style lives below the stage). Controllers have no
context; `DragSpringController.reduceMotion` makes every spring critically
damped, drops follower delays and `onOvershoot`.

**`SegmentTabs`** (`widgets/segment_tabs.dart`) owns its `SegmentSpring`
and moves it in `didUpdateWidget` when `selected` changes; springs from
`MotionTokens`, `stretchy` off with "Reduce motion". Each tab is
`FocusableActionDetector` (Enter, numpad Enter, Space → `ActivateIntent`)
around one `Semantics` node, so focus and button state merge. Its content
is laid out at least as wide as padding + icon (`_AtLeastWide`) and clipped,
so a tab squeezed by a folding bar neither overflows nor shrinks the text.

**`FlyingIcon`** (`widgets/flying_icon.dart`) – `RenderFlyingIcon` fills its
parent, lays the child out loosely and places it with a paint-time transform:
`lerp(from, to, t) + arc · sin(π t)`. `FlightPoint.anchor(key)` is resolved
at paint time with `localToGlobal`/`globalToLocal`, so paint-time transforms
above the anchor (a slide, a press) are followed; pass the animation that
moves them as `repaint`. `applyPaintTransform` makes `getCenter` and
`localToGlobal` on the child correct.

**`MotionTransform`** – applies a `Matrix4` at paint time from a `Listenable`
(and implements `applyPaintTransform`, so hit testing and `localToGlobal`
stay correct). No rebuild or layout per frame.

## The gooey system (`gooey/`)

```
GooeyScene ── members: GooeyMember(rect: () => Rect?, color, geometry)
   │  per frame (cached while building/laying out/painting):
   ├─ shapes: List<GooeyShape>   rect + colour + resolved outline + ripples (blobs)
   ├─ field:  GooeyColorField    contact strength per pair → blend widths
   └─ neckBetween(i, j)          GooeyNeckGeometry or null
Widgets, all inside one GooeyStage (the coordinate system):
   GooeyBackdrop  → GooeyPainter     necks between every connected pair (under the shapes)
   GooeySurface   → GooeyFillPainter one shape's background (colour blend + blobs)
   GooeyContent   → GooeyInfluence   content pulled into / dissolving in the other shape
```

**Shapes.** `GooeyShape` is an immutable per-frame snapshot. The outline comes
from `GooeyGeometry.resolve(rect)` → `GooeySdf` (signed distance: negative
inside). Rounded rects take an inlined fast path. Ripples (`GooeyRipple`,
from blob springs) subtract Gaussian bumps from the distance.

**Geometries** (`geometry.dart`): rounded rect, circle, ring, polygon / star
(rounded corners), path. `GooeyPathGeometry` samples the path into a distance
field (brute force, cached per size via `Expando`). A zero-size rect resolves
to `_PointSdf` (guards against NaN). Every SDF may describe itself for the
GPU as a `GooeyGpuShape`: type 0 rounded rect, 1 ring/circle, 2 polygon
(at most 24 vertices), 3 sampled field (uploaded as an 8-bit texture, ±32
field units, bilinear in the shader).

**Contact** (`contact.dart`). `GooeyContact.measure(a, b)` → (gap, focus).
Two rounded rects: exact box distance. Anything else: a 21×21 grid search for
the point minimising `max(da, db)` over the area both shapes can reach
(rects inflated by 16 px + bulge), then 7 refinement rounds; gap =
2·best (0 when inside both). Robust for holes (rings) and notches (stars).
Cached per pair per frame. `ContactTracker` adds hysteresis and catch/release
speed (drives the blobs).

**Colour field** (`field.dart`). `strength(i, j)` is a smoothstep of the gap
against `meetAt`; blend width = lerp(4, `GooeyStyle.blendWidth` = 60,
strength). The colour at a point: the nearest shape has weight 1, each of the
next nearest (up to `neighbours`) adds weight u/(1-u), where u is the
smoothstep blend between the two. With one neighbour this equals a plain
two-colour mix; with more, a shape between two others blends towards both
without an edge. The CPU path paints it as a vertex grid (`drawVertices`)
only inside `activeRect`; the GPU shader computes the same per pixel.

**Necks** (`neck.dart`). Smooth-min of the two distances with a bump at the
focus; only what the merge *adds* outside the shapes is drawn (plus a thin
rim under them so there is no seam). CPU fallback: marching squares on a grid
(`contour.dart`).

**Content** (`influence.dart`). `GooeyInfluence` cuts the child into strips
across the pull direction; each strip is shifted by its own strength and
stretched piecewise linearly (no seams). Blur and fade are applied once with
a gradient mask (sharp copy + blurred copy), not per strip. Layers are reused
between frames.

## The GPU shader (`shaders/gooey.frag` + `gooey/shader.dart`)

One program, three modes:

- `mode 0` – the neck between shape A and B.
- `mode 1` – shape A's own surface, blended towards up to three neighbours
  (B, C, D) at once. `GooeyShader.maxNeighbours` (3) is the number of slots;
  `GooeyStyle.blendNeighbours` (0–3) chooses how many are used, and
  `MotionQuality` lowers it to 1 first (`MotionFeature.multiBlend`).
- `mode 2` – a soft shadow under shapes A–D together (A and B merged with
  their neck), offset and blurred like a `BoxShadow`: the fall-off of a
  Gaussian blur across an edge, from the distance (logistic fit,
  `1 / (1 + exp(1.702 · d / sigma))`). Drawn by `GooeyBackdrop` before the
  necks.

**Edge light** (`GooeyStyle.light`, `gooey/light.dart`). Modes 0 and 1 lay a fill
gradient, an inner glow and a thin edge over the colour. The edge is a band
of the MERGED distance, not of the shape's own: the neck pass uses its own
smooth-min `sm`; the surface pass recomputes the same smooth-min towards
each neighbour it has a neck with (`uNeckB..D`, `uKs`), so both passes agree
pixel for pixel and the edge runs on through the neck and vanishes where the
shapes have merged. The outline glow is a band of the same distance. Where a
pixel lies on the gradient axis – fraction from begin to end, px from each
end, in the shape's own rect – is blended between shapes with the same
weights as the colour, so gradients, axis glows and edge colour have no seam
either. The
fill painter therefore also passes shapes it only has a neck with (blend
width 0 = merged outline only).

**The uniform order is a contract.** Flutter sets uniforms by index, in
declaration order. `_UniformWriter` in `shader.dart` must write exactly:

```
uParams   (mode, k, overlap, addsAtLeast)
uParams2  (neck blend width, origin x, origin y, pixel ratio)
uBump     (focus x, focus y, amplitude, 1/sigma²)
uColA, uColB, uColC, uColD            (rgba 0..1)
uWidths   (blend width to B, C, D, unused)        – surface mode
uNeckB, uNeckC, uNeckD  (focus x, focus y, amplitude, 1/sigma²) – surface
uKs       (k towards B, C, D; edge width px)
uEdge0..3 (edge colours, rgba) · uEdgeStops (4 stops)
uAxis     (gradient begin x, y, end x, y – Alignment units in each rect)
uFillStart, uFillEnd, uGlowStart, uGlowEnd, uEdgeGlow   (rgba)
uLight    (axis glow depth px, edge light on 0/1, outline glow depth px, unused)
uShadow   (rgba) · uShadowParams (sigma, spread, offset x, offset y)
shape A, B, C, D, each:
  rect (l, t, r, b) · shape (type, p1, p2, vertex count; type < 0 = none)
  · 3 ripples (cx, cy, amplitude, 1/r²)
uVertA..D (24 vertices each, two per vec4: x0, y0, x1, y1)
samplers uFieldA..D (an empty 1×1 image when unused)
```

**Keep the vertex arrays last.** On an iPhone 11 (A13) in Safari, with the
arrays in the middle and the light and shadow after them, the shapes were
drawn but the light and shadow came out as nothing (0.5.0; the Events app's
light probe measured 0, a newer iPhone SE 62–78). The likely cause: most GPUs
give every uniform, and every array element, a whole vec4 slot, so the 4 ×
24 `vec2` vertices took 96 slots and pushed the light and shadow to slot
124–137; that device read them as 0. Since 0.5.1 the vertices are packed two
per `vec4` and come last: everything a rounded rect, a circle or a ring
reads is in slots 0–45, and only polygons and fields read slots 46–93. A new
uniform goes BEFORE the vertex arrays.

`test/shader_uniforms_test.dart` loads the real shader and checks that every
paint call writes exactly as many floats as `gooey.frag` declares (376
today), that only vertex arrays come from slot 46 on, and – drawing on the
test renderer – that a lit surface shows its edge, a shadow shows, and
polygons and fields are drawn where the CPU outline is. A wrong order fails
those.

For a field shape the "vertices" carry the texture mapping instead
(scale/offset, padded rect, value scale, grid size). Adding a slot or a
uniform means changing both files in the same order. Each painter keeps its
own `FragmentShader` instance(s): uniforms belong to the instance.

**Members without a rect** are left out of `GooeyScene.shapes` (a toolbar a
page does not show); the others still merge and light. The indices of
`shapes`, `neckBetween` and `field` are indices into that list;
`GooeySurface`/`GooeyContent` take a member index and map it with
`shapeIndexOf`. While every member has a rect the two are the same.

`GooeyShader.canDraw(shape)` is false until a path's texture has uploaded
(`GooeyShader.updates` notifies scenes to repaint) and for custom geometries
without a GPU description; those draw on the CPU.

## Automatic quality (`quality/motion_quality.dart`)

Measures build + raster per frame (`addTimingsCallback`) while something
moves. Too many frames over budget → the next feature in `dropOrder` is
switched off (`contentBlend`, `multiBlend`, `colorBlend`, `blob`, `neck`);
lots of headroom for a while → back on. Changes are applied only when idle,
so nothing vanishes mid-animation. A frame interval of about 33 ms means Low
Power Mode (Safari's 30 Hz lock) and switches everything off. `GooeyScene`
applies it through `_limited(style)`.

## Startup warm-up (`warm_up.dart`)

The first draw of a new technique compiles a GPU program mid-animation.
`MotionWarmUp` draws each technique once, faintly, behind the app for the
first frames: the shader (neck + surface), blurs at every strength step and
direction, gradient masks, opacity layers, clips, vertex colours. It does not
catch everything on Safari – see STATUS.

## Example app

`example/lib/bottom_bar/` is the reference integration: a tab bar that morphs
into a bubble next to the navigation bar on scroll (`DragSpringController` +
followers + `GooeyScene` with `MotionQuality`). Its debug panel
(`example/lib/debug/`) is the measuring tool. `shapes/` is a playground with
every outline.
