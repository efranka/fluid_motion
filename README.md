# fluid_motion

Organic, physics-driven animation for Flutter, built on *The twelve basic
principles of animation*. Nothing is a hard-coded timeline: everything runs in
real time on springs, and every technique is a small reusable building block
that knows nothing about the element it is used on.

- **Springs with graded bounce:** move slowly and things glide into place.
  Move fast and they bounce, with everything in between.
- **"The finger drives, the spring takes over":** for bottom bars, sheets and
  swipe cards, driven by scroll or by drag.
- **Gooey shapes:** shapes flow together like liquid when they get close.
  Their colours blend, they blob when they catch and release each other, and
  content dissolves into the other shape. This works with any outline:
  rounded rects, circles, rings, polygons, stars, any `Path`, or your own.
- **Automatic quality:** expensive effects switch off when the device cannot
  keep up (old phone, low battery, Low Power Mode) and back on when there is
  headroom.

```
fluid_motion/
├─ packages/fluid_motion/   the package
│  ├─ lib/src/foundation/   EnergySpring, SpringMotion, rubberBand, Ramp, directionalStretch
│  ├─ lib/src/drag/         DragSpringController + MorphFollower
│  ├─ lib/src/widgets/      PressScale/PressSpring, MotionTransform, SegmentSpring
│  ├─ lib/src/gooey/        GooeyScene, geometries, stage/backdrop/surface/content,
│  │                        GooeyShader (GPU) + CPU fallback, field, contour, contact
│  ├─ lib/src/quality/      MotionQuality – automatic quality
│  ├─ lib/src/tokens.dart   MotionTokens + MotionScope
│  ├─ shaders/gooey.frag    the GPU shader (necks and surfaces)
│  └─ test/
└─ example/                 demo app: a morphing bottom bar and a shapes playground
```

## Getting started

You need Flutter 3.27 or newer.

```bash
cd example
flutter create . --platforms=web,ios,android   # generates the platform folders
flutter pub get
flutter run -d chrome --release

cd ../packages/fluid_motion
flutter test
```

`flutter create .` does not touch `lib/` or `test/`.

To use the package in your own app, add it as a git dependency:

```yaml
dependencies:
  fluid_motion:
    git:
      url: https://github.com/efranka/fluid_motion.git
      path: packages/fluid_motion
```

Then load the shader once at startup. If it fails, the CPU version is used
automatically.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GooeyShader.load();
  runApp(const MyApp());
}
```

## Building blocks

| Principle | Building block | Use |
|---|---|---|
| Slow in/out, follow through | `EnergySpring` | Bounce graded by speed |
| Direct manipulation | `DragSpringController` | Two-state elements driven by scroll or drag. The spring takes over with the finger's exact velocity |
| Overlapping/secondary action | `MorphFollower` | Elements that follow with their own spring and delay |
| Squash & stretch | `directionalStretch`, `SegmentSpring` | Stretch along the motion, a stretchy tab indicator |
| Anticipation/feedback | `PressScale`, `PressSpring` | Press feedback, also shared by several layers |
| Arcs, timing | `MotionTransform` | Transform at paint time, with no rebuild and no layout |
| Fluid material | `GooeyScene` and friends | Neck, colour blend, blobs and dissolving content |

### Gooey on any element

```dart
final scene = GooeyScene(
  vsync: this,
  motion: myAnimation,                 // anything that moves the shapes
  members: [
    GooeyMember(rect: () => rectA, color: cs.surfaceContainerHigh),
    GooeyMember(rect: () => rectB, color: cs.primaryContainer,
                geometry: const GooeyStar(points: 5, cornerRadius: 6)),
  ],
);

GooeyStage(scene: scene, children: [
  GooeyBackdrop(scene: scene),                        // the neck (under the shapes)
  Positioned.fromRect(rect: rectA, child: GooeySurface(scene: scene, index: 0)),
  Positioned.fromRect(rect: rectB, child: GooeySurface(scene: scene, index: 1)),
  // content that dissolves into the other shape:
  // GooeyContent(scene: scene, index: 0, child: Icon(...)),
]);
```

Each effect can be switched off on its own with
`GooeyStyle(neck:, colorBlend:, blob:, contentBlend:, useShader:)`.
`GooeyStyle.off` switches them all off, which the demos use for "Reduce
motion".

### Outlines

| Geometry | Shape |
|---|---|
| `GooeyRoundedRect({radius})` | Rounded rect, or a pill without a radius (default) |
| `GooeyCircle()` | Circle centred in the rect |
| `GooeyRing({thickness})` | Circle with a hole |
| `GooeyPolygon(points, {cornerRadius})`, `GooeyPolygon.regular(n)` | Any simple polygon |
| `GooeyStar({points, innerRatio, cornerRadius})` | Star |
| `GooeyPathGeometry((size) => path)` | Any `Path` |

Every geometry is a signed distance field, so you can add your own by
implementing `GooeyGeometry`. All built-in outlines are drawn on the GPU. A
custom geometry is drawn on the GPU if its `GooeySdf.gpu` returns one of the
`GooeyGpuShape` kinds, and on the CPU otherwise.

### Motion tokens

Put `MotionScope(tokens: MotionTokens(...))` at the top of the app to change
springs and timings for every component in one place, just like colour and
typography tokens.

## Automatic quality

`MotionQuality` continuously measures how long each frame takes while
something moves. If the device cannot keep up, it switches the expensive
effects off one at a time, and switches them back on when there is headroom.
This covers old phones, low battery, a hot phone, heavy background apps and
Low Power Mode (which locks Safari to 30 frames per second). Springs, bounce,
arcs and stretch are never affected, and changes only happen while nothing
moves.

```dart
final quality = MotionQuality();              // enabled: false switches it off
final scene = GooeyScene(vsync: this, motion: m, quality: quality);
```

`GooeyScene` follows the quality by itself. Other components can ask
`quality.allows(...)`, and you can add your own features:

```dart
const glow = MotionFeature('glow', label: 'Glow');
final quality = MotionQuality(
  dropOrder: [glow, ...MotionQuality.defaultDropOrder], // dropped first
);
if (quality.allows(glow)) { /* paint the glow */ }
```

`MotionQualityScope` passes the quality down the widget tree.

## No stutter the first time

The first time the GPU draws something new (the gooey shader, a blur of a
certain strength, a gradient mask), it compiles a small program for it in the
middle of the animation. That is why an animation can stutter the first
couple of times and then run smoothly. It is most noticeable on the web.

`MotionWarmUp` draws every technique once, faintly and hidden behind your
app, during the first frames, so the programs are ready before anyone
touches anything:

```dart
await GooeyShader.load();
runApp(MotionScope(child: MotionWarmUp(child: MaterialApp(...))));
```

## Performance notes

- Measure on a real phone in release mode. Debug builds are much slower,
  especially on the web.
- A phone with very low battery or in Low Power Mode is heavily throttled, so
  charge it before measuring.
- The bottom bar demo has a debug panel (top right) that shows build and
  raster time per frame. It lets you switch each effect off live and simulate
  a slow phone.

## GPU and CPU

When the shader is loaded (`GooeyShader.load()`), everything gooey is drawn on
the GPU in one shader for every built-in outline: the necks, and the shapes
themselves with colour blending and blobs. A path's distance field is
uploaded as a small texture the first time it is used.

The CPU version is only a fallback. It is used if the shader cannot load (or
in widget tests), for a polygon with more than 24 corners, and for custom
geometries without a GPU description. It draws the same thing.

The shader assumes that `FlutterFragCoord()` is in local logical coordinates.
If the shapes look offset or wrongly scaled with the GPU but right with the
CPU (switch with "Draw on GPU" in the demo's debug panel), that assumption
does not hold on that platform. Please open an issue.

## License

MIT, see [LICENSE](LICENSE).
