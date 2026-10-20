# Status

Where things stand (version 0.3.0, October 2026). Update this file when
something here changes.

## Ready

- Used from an app as a git dependency pinned to a tag (see README).
- Analyzer clean, 65 tests.
- "Reduce motion": `PressScale` and `GooeyStage` follow it by themselves;
  `DragSpringController` and `SegmentSpring` take it as a property (no
  context). See the README section.
- Measured on an iPhone 11: native iOS about 4.4 ms per frame with the GPU;
  web in Safari runs smoothly after the first fold (see the known issue).

## Open

| Item | What | Notes |
|---|---|---|
| P1 | One shared frame-time measurer instead of one callback per `MotionQuality` | Persistent frame callbacks cannot be removed, only muted |
| R1 | Test native Android on a real phone, GPU and CPU | Only iOS and web tested |
| Docs | GIF or video at the top of the README | |

## Known issues

**Safari, first fold hitch.** On an iPhone 11 in Safari, the first time the
bottom bar folds after the page loads, one frame takes about 200 ms (build
about 15 ms, raster about 180 ms). Afterwards it is smooth. Measured with the
debug panel's "heaviest frame". What was ruled out, with measurements:

| Tried | Result |
|---|---|
| Hide icons and text | Still about 180 ms raster – not the content |
| Hide the bar (list only) | 35 ms, raster 5 – it is the bar |
| Draw on GPU off | Raster 2 ms – it is the GPU path… |
| …but `MotionWarmUp` already draws the shader, and a tiny real gooey scene in the warm-up did not help | Not the shader program itself |
| Priming the neck's own shader instance while apart | No change |

Not tried yet: the effect toggles one at a time (Gooey neck / Blob / Colour
blend in the panel) with the GPU on. Worth doing only if the hitch shows up
in the real app.

**CPU fallback, first fold.** With "Draw on GPU" off, the first fold costs
about 2 s of build (Dart). The CPU path only runs when the shader cannot
load, but this should be found and fixed before relying on it.

## Decisions and things that did not work

- Content (`GooeyInfluence`) without its own layers while unaffected: correct
  and tested, but no measurable gain on the iPhone, so it was dropped to keep
  the code simple.
- An early "worst" number in the debug panel counted idle pauses as hitches;
  fixed (`worst gap` only counts gaps while animating). Older measurements
  of fps and jank in notes are not reliable.
- Flutter 3.41 and 3.47 measured the same; today's frame cost is not a
  regression from the upgrade.
- wasm/skwasm: white screen in Safari; the web build stays on CanvasKit.
- "Reduce motion" (A1, 0.3.0): the drag controller still glides (critically
  damped) instead of jumping, because the fold follows the user's own scroll
  or drag. Controllers without a context are not made automatic (no hidden
  global state); the owning widget sets `reduceMotion`.
