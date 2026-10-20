import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

/// A vertical list with a horizontal carousel at the top, driving [c].
Widget _page(DragSpringController c, ScrollMorphBehavior behavior) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) =>
            c.handleScrollNotification(n, behavior: behavior),
        child: ListView(
          key: const Key('list'),
          children: [
            SizedBox(
              height: 200,
              child: ListView(
                key: const Key('carousel'),
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 20; i++) const SizedBox(width: 100),
                ],
              ),
            ),
            for (var i = 0; i < 60; i++) const SizedBox(height: 100),
          ],
        ),
      ),
    );

Future<void> _drag(WidgetTester tester, String key, Offset by) async {
  await tester.drag(find.byKey(Key(key)), by);
  await tester.pumpAndSettle();
}

void main() {
  late DragSpringController c;
  setUp(() => c = DragSpringController(vsync: const TestVSync()));
  tearDown(() => c.dispose());

  testWidgets('standard: down folds, up unfolds', (tester) async {
    await tester.pumpWidget(_page(c, ScrollMorphBehavior.standard));
    await _drag(tester, 'list', const Offset(0, -400));
    expect(c.value.value, 1);
    await _drag(tester, 'list', const Offset(0, 300));
    expect(c.value.value, 0);
  });

  testWidgets('standard: a carousel inside the list does not fold',
      (tester) async {
    await tester.pumpWidget(_page(c, ScrollMorphBehavior.standard));
    await tester.drag(
      find.byKey(const Key('carousel')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(c.value.value, 0);
  });

  testWidgets('collapseOnly: any scroll folds, only a tap unfolds',
      (tester) async {
    await tester.pumpWidget(_page(c, ScrollMorphBehavior.collapseOnly));
    await tester.drag(
      find.byKey(const Key('carousel')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(c.value.value, 1);

    // Scrolling back does not unfold …
    await _drag(tester, 'list', const Offset(0, -400));
    await _drag(tester, 'list', const Offset(0, 300));
    expect(c.value.value, 1);

    // … a tap does.
    c.animateTo(0);
    await tester.pumpAndSettle();
    expect(c.value.value, 0);
  });

  testWidgets('atStart: unfolds only back at the very top', (tester) async {
    await tester.pumpWidget(_page(
      c,
      const ScrollMorphBehavior(expand: ScrollExpand.atStart),
    ));
    await _drag(tester, 'list', const Offset(0, -1200));
    expect(c.value.value, 1);
    await _drag(tester, 'list', const Offset(0, 300)); // not at the top yet
    expect(c.value.value, 1);
    await _drag(tester, 'list', const Offset(0, 3000)); // all the way up
    expect(c.value.value, 0);
  });

  test('behaviours compare by value', () {
    expect(
      const ScrollMorphBehavior(),
      ScrollMorphBehavior.standard,
    );
    expect(
      ScrollMorphBehavior.collapseOnly == ScrollMorphBehavior.standard,
      isFalse,
    );
  });
}
