import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

void main() {
  testWidgets('a drag past halfway lands exactly on 1', (tester) async {
    final c = DragSpringController(vsync: const TestVSync(), distance: 120);
    addTearDown(c.dispose);

    c.dragStart();
    c.dragUpdate(80); // 2/3 of the way
    expect(c.value.value, closeTo(80 / 120, 1e-9));
    expect(c.isDragging, isTrue);

    c.dragEnd(0);
    expect(c.target, 1);
    await tester.pumpAndSettle();
    expect(c.value.value, 1); // set exactly when the spring comes to rest
  });

  testWidgets('a drag short of halfway returns to 0', (tester) async {
    final c = DragSpringController(vsync: const TestVSync());
    addTearDown(c.dispose);
    c.dragStart();
    c.dragUpdate(30);
    c.dragEnd(0);
    await tester.pumpAndSettle();
    expect(c.target, 0);
    expect(c.value.value, 0);
  });

  testWidgets('a fast animation overshoots and calls onOvershoot once',
      (tester) async {
    final c = DragSpringController(vsync: const TestVSync());
    addTearDown(c.dispose);
    var calls = 0;
    c.onOvershoot = (target, velocity) {
      calls++;
      expect(target, 1);
      expect(velocity, greaterThan(0));
    };
    c.animateTo(1, velocity: 8);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(c.value.value, 1);
  });

  testWidgets('a slow animation does not overshoot', (tester) async {
    final c = DragSpringController(vsync: const TestVSync());
    addTearDown(c.dispose);
    var calls = 0;
    c.onOvershoot = (_, __) => calls++;
    c.animateTo(1);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('"Reduce motion" removes the bounce', (tester) async {
    final c = DragSpringController(vsync: const TestVSync())
      ..reduceMotion = true;
    addTearDown(c.dispose);
    var calls = 0;
    c.onOvershoot = (_, __) => calls++;
    c.animateTo(1, velocity: 8);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(c.value.value, 1);
  });

  testWidgets('the follower waits and lands on the same target',
      (tester) async {
    final c = DragSpringController(vsync: const TestVSync());
    final nav = AnimationController.unbounded(vsync: const TestVSync());
    addTearDown(() {
      c.dispose();
      nav.dispose();
    });
    c.addFollower(MorphFollower(
      controller: nav,
      spring: MotionTokens.standard.follower,
      delay: const Duration(milliseconds: 60),
    ));
    c.animateTo(1);
    await tester.pump(const Duration(milliseconds: 30));
    expect(nav.value, 0); // still waiting
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(nav.value, 1);
  });
}
