import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

MotionQuality _quality() => MotionQuality(measure: false);

void _frames(MotionQuality q, double ms, int count) {
  for (var i = 0; i < count; i++) {
    q.recordWork(ms);
  }
}

void main() {
  test('everything is allowed at first', () {
    final q = _quality();
    expect(q.dropped, 0);
    for (final f in MotionQuality.defaultDropOrder) {
      expect(q.allows(f), isTrue);
    }
  });

  test('heavy frames switch off the most expensive effect – only when idle',
      () {
    final q = _quality();
    _frames(q, 22, 90); // one measuring window over budget
    expect(q.dropped, 0); // waits until idle
    q.applyPending();
    expect(q.dropped, greaterThanOrEqualTo(1));
    expect(q.allows(MotionFeature.contentBlend), isFalse);
    expect(q.allows(MotionFeature.neck), isTrue);
  });

  test('slightly over budget drops one step, far over drops two', () {
    final light = _quality();
    // 30 % over budget.
    _frames(light, 10, 63);
    _frames(light, 20, 27);
    light.applyPending();
    expect(light.dropped, 1);

    final heavy = _quality();
    _frames(heavy, 30, 90);
    heavy.applyPending();
    expect(heavy.dropped, 2);
  });

  test('light frames over a longer time switch effects back on', () {
    final q = _quality();
    _frames(q, 30, 90);
    q.applyPending();
    expect(q.dropped, 2);
    _frames(q, 4, 360); // about 6 s with plenty of headroom
    q.applyPending();
    expect(q.dropped, 1);
  });

  test('normal frames change nothing', () {
    final q = _quality();
    _frames(q, 6, 400);
    q.applyPending();
    expect(q.dropped, 0);
  });

  test('Low Power Mode (30 Hz) switches all effects off', () {
    final q = _quality();
    for (var i = 0; i < 60; i++) {
      q.recordInterval(33.3);
    }
    q.applyPending();
    expect(q.lowPower, isTrue);
    expect(q.dropped, MotionQuality.defaultDropOrder.length);

    for (var i = 0; i < 60; i++) {
      q.recordInterval(16.7);
    }
    q.applyPending();
    expect(q.lowPower, isFalse);
    expect(q.dropped, 0);
  });

  test('disabled = everything allowed, and custom features can be added', () {
    const glow = MotionFeature('glow', label: 'Glow');
    final q = MotionQuality(
      measure: false,
      dropOrder: const [glow, ...MotionQuality.defaultDropOrder],
    );
    _frames(q, 30, 90);
    q.applyPending();
    expect(q.allows(glow), isFalse);
    expect(q.allows(const MotionFeature('unknown')), isTrue);

    q.enabled = false;
    expect(q.allows(glow), isTrue);
    expect(q.dropped, 0);
  });

  testWidgets('GooeyScene follows the quality', (tester) async {
    final q = _quality();
    final motion = AnimationController(vsync: const TestVSync());
    final scene =
        GooeyScene(vsync: const TestVSync(), motion: motion, quality: q);
    addTearDown(() {
      scene.dispose();
      motion.dispose();
      q.dispose();
    });

    expect(scene.style.contentBlend, isTrue);
    var notified = 0;
    scene.styleListenable.addListener(() => notified++);

    _frames(q, 30, 90); // two steps: content + colour blend
    q.applyPending();
    expect(scene.style.contentBlend, isFalse);
    expect(scene.style.colorBlend, isFalse);
    expect(scene.style.neck, isTrue);
    expect(scene.baseStyle.contentBlend, isTrue);
    expect(notified, 1);

    q.enabled = false;
    expect(scene.style.contentBlend, isTrue);
  });

  test('impossible settings fail clearly during development', () {
    expect(
        () => MotionQuality(measure: false, budgetMs: 0), throwsAssertionError);
    expect(
      () => MotionQuality(measure: false, overBudgetShare: 1.5),
      throwsAssertionError,
    );
    final q = _quality();
    expect(() => q.budgetMs = -1, throwsAssertionError);
    q.budgetMs = 3; // a valid change still works
    expect(q.budgetMs, 3);
  });
}
