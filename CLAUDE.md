# fluid_motion – notes for Claude

Organic, physics-based animation for Flutter (springs, "the finger drives, the
spring takes over", gooey shapes). It grew out of the bottom bar in Erik's
mobile event web app and is meant to be reused across element types and
projects. Public repo: https://github.com/efranka/fluid_motion (MIT).

Read `docs/ARCHITECTURE.md` before changing the gooey system or the shader,
and `docs/STATUS.md` for what is open and what has already been tried.

## Working with Erik

- Erik is a UX designer (Denmark). He writes in **Danish**: answer in Danish.
  Code, comments, docs, commit messages and the README are in **English**.
- He runs everything himself on his Mac (Apple Silicon, Flutter 3.47.x) and
  tests on an **iPhone 11** – both native iOS and the web build in Safari.
  The web build on an iPhone 11 is the main performance target.
- Give commands as separate copy-paste blocks. Never put a `#` comment line
  in a block he pastes into zsh (it is run, not ignored), and keep `git push`
  in its own block so it is a deliberate step.
- Before saying something is done: `flutter analyze` must report no issues
  and `flutter test` must pass. Run `dart format .` before committing.

## Layout

```
packages/fluid_motion/   the package (version in pubspec.yaml, CHANGELOG.md)
  lib/src/foundation/    EnergySpring, SpringMotion, rubberBand, Ramp, stretch
  lib/src/drag/          DragSpringController, MorphFollower, ScrollMorphBehavior
  lib/src/widgets/       PressScale/PressSpring, MotionTransform, SegmentSpring
  lib/src/gooey/         GooeyScene and everything gooey (see ARCHITECTURE)
  lib/src/quality/       MotionQuality (automatic quality)
  lib/src/tokens.dart    MotionTokens + MotionScope
  lib/src/warm_up.dart   MotionWarmUp (prepares GPU programs at startup)
  shaders/gooey.frag     the one GPU shader (necks + surfaces)
  test/                  unit and widget tests
example/                 demo app: morphing bottom bar + shapes playground
  lib/debug/             frame stats + debug panel used for all measurements
docs/                    ARCHITECTURE.md, STATUS.md
```

## Commands

```bash
cd packages/fluid_motion && flutter analyze && flutter test

cd example && flutter run -d chrome --release          # desktop browser
cd example && flutter run --release                    # native, phone on USB
cd example && flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --release
# then open http://<Mac IP>:8080 in Safari on the phone (ipconfig getifaddr en0)
```

## Conventions

- Every effect is a small building block that knows nothing about the
  element it is used on. No hard-coded timelines: springs, in real time.
- Work happens at paint time where possible (no rebuild/relayout per frame).
- New behaviour gets a test. Public API gets a dartdoc comment and, if users
  need it, a README section and a CHANGELOG line.
- Flutter 3.47's analyzer flags imports already provided by
  `package:flutter/widgets.dart` (`unnecessary_import`). But `widgets.dart`
  does **not** export everything from `foundation.dart` (e.g. `setEquals`).
- The GPU shader and its Dart uniform writer (`gooey/shader.dart`) must stay
  in exactly the same order – see ARCHITECTURE. Validate the shader syntax
  with `glslangValidator` if available; Flutter itself only compiles it on
  build.
- Use `MotionScope.reduceMotionOf(context)` and `GooeyStyle.off` for
  "Reduce motion" (components do not yet do this by themselves – STATUS A1).

## Measuring performance

Use the bottom bar demo's debug panel (top right), never impressions alone:

1. Phone charged and cool (a warm iPhone throttles; Automatic quality then
   switches effects off and every number is off).
2. Turn **Automatic quality off** so the effects do not change while you
   measure. Release mode only.
3. Press **Reset**, then do the thing being measured.
4. `build + raster` and `90 %` are the cost per frame. `worst gap` only
   counts gaps while something animates. `heaviest frame (build + raster)`
   catches one-off hitches and says whether they are Dart (build) or GPU
   (raster).
5. Isolate with the panel's toggles: hide the bar (list only), hide icons and
   text, do not fold, draw on GPU, and one toggle per effect further down.

## Environment gotchas (Erik's Mac)

- After `flutter upgrade`, `iproxy` was once an Intel-only binary and
  `flutter run` on the phone asked for Rosetta. Fix:
  `rm -rf /opt/homebrew/share/flutter/bin/cache/artifacts/libusbmuxd && flutter precache --ios`.
- "Too many open files" when installing on the phone: `ulimit -n 10240`.
- "Dart VM Service was not discovered": the app still runs; unlock the phone
  or allow Local Network for the app. Not needed for testing visuals.
- Skwasm/wasm does not work in Safari for this app: stay on CanvasKit.
