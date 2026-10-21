import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

void main() {
  group('MotionScope.reduceMotionOf', () {
    Future<bool> read(WidgetTester tester, Widget Function(Widget) wrap) async {
      late bool result;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        result = MotionScope.reduceMotionOf(context);
        return const SizedBox();
      })));
      return result;
    }

    testWidgets('follows the system setting', (tester) async {
      expect(await read(tester, (c) => c), isFalse);
      expect(
        await read(
          tester,
          (c) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: c,
          ),
        ),
        isTrue,
      );
    });

    testWidgets('MotionScope.reduceMotion overrides it both ways',
        (tester) async {
      expect(
        await read(tester, (c) => MotionScope(reduceMotion: true, child: c)),
        isTrue,
      );
      expect(
        await read(
          tester,
          (c) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MotionScope(reduceMotion: false, child: c),
          ),
        ),
        isFalse,
      );
    });
  });

  group('PressScale', () {
    /// The scale while a finger holds the [PressScale] down.
    Future<double> pressedScale(
      WidgetTester tester, {
      required bool reduce,
    }) async {
      await tester.pumpWidget(MotionScope(
        reduceMotion: reduce,
        child: const Center(
          child: PressScale(
            // A coloured box, so the touch hits something.
            child: ColoredBox(
              color: Color(0xFF000000),
              child: SizedBox(width: 50, height: 50),
            ),
          ),
        ),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(PressScale)));
      await tester.pumpAndSettle();
      final scale = tester
          .widget<ScaleTransition>(find.byType(ScaleTransition))
          .scale
          .value;
      await gesture.up();
      await tester.pumpAndSettle();
      return scale;
    }

    testWidgets('squeezes on touch', (tester) async {
      expect(await pressedScale(tester, reduce: false), lessThan(1));
    });

    testWidgets('does not squeeze with "Reduce motion"', (tester) async {
      expect(await pressedScale(tester, reduce: true), 1);
    });
  });

  group('GooeyStage', () {
    testWidgets('switches every effect off with "Reduce motion", and back',
        (tester) async {
      final motion = ValueNotifier(0.0);
      final scene = GooeyScene(
        vsync: const TestVSync(),
        motion: motion,
        style: const GooeyStyle(light: GooeyLight()),
      );
      addTearDown(() {
        scene.dispose();
        motion.dispose();
      });

      Widget stage(bool reduce) => Directionality(
            textDirection: TextDirection.ltr,
            child: MotionScope(
              reduceMotion: reduce,
              child: GooeyStage(scene: scene, children: const []),
            ),
          );

      await tester.pumpWidget(stage(true));
      expect(scene.reduceMotion, isTrue);
      expect(scene.style.neck, isFalse);
      expect(scene.style.colorBlend, isFalse);
      expect(scene.style.blob, isFalse);
      expect(scene.style.contentBlend, isFalse);
      // What the app asked for is kept.
      expect(scene.baseStyle.neck, isTrue);
      // Edge light is not motion: it stays.
      expect(scene.style.light, isNotNull);

      await tester.pumpWidget(stage(false));
      expect(scene.reduceMotion, isFalse);
      expect(scene.style.neck, isTrue);
      expect(scene.style.blob, isTrue);
    });
  });

  group('SegmentTabs', () {
    testWidgets('the indicator jumps, without stretching', (tester) async {
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(MotionScope(
        reduceMotion: true,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(builder: (context, set) {
            update = set;
            return SegmentTabs(
              tabs: const [SegmentTab(label: 'A'), SegmentTab(label: 'B')],
              selected: selected,
              onSelected: (_) {},
              labelStyle: const TextStyle(fontSize: 14),
              indicatorColor: const Color(0x22000000),
            );
          }),
        ),
      ));
      update(() => selected = 1);
      await tester.pump();
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<SegmentIndicatorPainter>()
          .first;
      expect(painter.segments.left, 1);
      expect(painter.segments.right, 2);
    });
  });

  group('DragSpringController with "Reduce motion"', () {
    testWidgets('followers move at once, and nothing overshoots',
        (tester) async {
      final c = DragSpringController(vsync: const TestVSync())
        ..reduceMotion = true;
      final icon = AnimationController.unbounded(vsync: const TestVSync());
      addTearDown(() {
        c.dispose();
        icon.dispose();
      });
      // A loose spring that would bounce even when calm.
      c.addFollower(MorphFollower(
        controller: icon,
        spring: const EnergySpring(stiffness: 300, calmRatio: 0.4),
        delay: const Duration(milliseconds: 60),
      ));
      var overshoots = 0;
      c.onOvershoot = (_, __) => overshoots++;

      c.animateTo(1, velocity: 8);
      await tester.pump(); // the first frame starts the tickers
      await tester.pump(const Duration(milliseconds: 30));
      expect(icon.value, greaterThan(0)); // no waiting for the delay

      var highest = 0.0;
      while (c.isAnimating) {
        await tester.pump(const Duration(milliseconds: 16));
        highest = [highest, c.value.value, icon.value]
            .reduce((a, b) => a > b ? a : b);
      }
      expect(highest, lessThanOrEqualTo(1));
      expect(overshoots, 0);
      expect(icon.value, 1);
    });
  });
}
