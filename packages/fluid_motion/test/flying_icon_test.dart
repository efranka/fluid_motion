import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

void main() {
  final anchor = GlobalKey();
  final icon = GlobalKey();

  /// An anchor at (40, 40) and a target at the box's centre (150, 100), in
  /// a 300 × 200 box.
  Widget scene(Animation<double> progress, {bool reduce = false}) =>
      MotionScope(
        reduceMotion: reduce,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 200,
              child: Stack(
                children: [
                  Positioned(
                    left: 30,
                    top: 30,
                    child: SizedBox.square(key: anchor, dimension: 20),
                  ),
                  Positioned.fill(
                    child: FlyingIcon(
                      progress: progress,
                      from: FlightPoint.anchor(anchor),
                      to: FlightPoint.at((size) => size.center(Offset.zero)),
                      arc: const Offset(0, -10),
                      child: SizedBox.square(key: icon, dimension: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('starts on the anchor, lands on the target, arcs between',
      (tester) async {
    final p =
        AnimationController.unbounded(vsync: const TestVSync(), value: 0.0);
    addTearDown(p.dispose);
    await tester.pumpWidget(scene(p));
    expect(tester.getCenter(find.byKey(icon)), const Offset(40, 40));

    p.value = 1;
    await tester.pump();
    expect(tester.getCenter(find.byKey(icon)), const Offset(150, 100));

    p.value = 0.5;
    await tester.pump();
    final mid = tester.getCenter(find.byKey(icon));
    expect(mid.dx, closeTo(95, 0.01));
    expect(mid.dy, closeTo(70 - 10, 0.01)); // the arc at its height
  });

  testWidgets('follows an overshooting spring, without the arc',
      (tester) async {
    final p =
        AnimationController.unbounded(vsync: const TestVSync(), value: 1.1);
    addTearDown(p.dispose);
    await tester.pumpWidget(scene(p));
    final c = tester.getCenter(find.byKey(icon));
    expect(c.dx, closeTo(40 + 110 * 1.1, 0.01));
    expect(c.dy, closeTo(40 + 60 * 1.1, 0.01));
  });

  testWidgets('"Reduce motion": no flight – at the start, then at the end',
      (tester) async {
    final p =
        AnimationController.unbounded(vsync: const TestVSync(), value: 0.4);
    addTearDown(p.dispose);
    await tester.pumpWidget(scene(p, reduce: true));
    expect(tester.getCenter(find.byKey(icon)), const Offset(40, 40));
    p.value = 0.6;
    await tester.pump();
    expect(tester.getCenter(find.byKey(icon)), const Offset(150, 100));
  });

  testWidgets('gets no touches and no semantics', (tester) async {
    final p =
        AnimationController.unbounded(vsync: const TestVSync(), value: 0.0);
    addTearDown(p.dispose);
    await tester.pumpWidget(scene(p));
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(
      find.ancestor(
          of: find.byKey(icon), matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
  });
}
