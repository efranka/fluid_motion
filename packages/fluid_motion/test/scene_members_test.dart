import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

void main() {
  // Three shapes in a row, 8 px apart; the middle one may have no rect
  // (e.g. a toolbar a page does not show).
  Rect? middle;
  final members = [
    GooeyMember(
      rect: () => const Rect.fromLTWH(0, 0, 100, 56),
      color: const Color(0xFF333333),
    ),
    GooeyMember(rect: () => middle, color: const Color(0xFF6655AA)),
    GooeyMember(
      rect: () => const Rect.fromLTWH(104, 0, 56, 56),
      color: const Color(0xFF6655AA),
    ),
  ];

  GooeyScene scene() {
    final s = GooeyScene(
      vsync: const TestVSync(),
      motion: ValueNotifier(0.0),
      members: members,
      style: const GooeyStyle(neckStyle: GooeyNeckStyle(reach: 12)),
    );
    addTearDown(s.dispose);
    return s;
  }

  test('a member without a rect is left out; the others are still there', () {
    middle = null;
    final s = scene();
    expect(s.shapes, hasLength(2));
    expect(s.shapeIndexOf(0), 0);
    expect(s.shapeIndexOf(1), isNull);
    expect(s.shapeIndexOf(2), 1);
    expect(s.shapes![1].rect.left, 104);
    // The first and the last now merge with a neck (4 px apart).
    expect(s.neckBetween(0, 1), isNotNull);
  });

  test('with every rect, shape i is member i', () {
    middle = const Rect.fromLTWH(200, 0, 56, 56);
    final s = scene();
    expect(s.shapes, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(s.shapeIndexOf(i), i);
    }
  });

  test('no rect at all: not ready', () {
    final s = GooeyScene(
      vsync: const TestVSync(),
      motion: ValueNotifier(0.0),
      members: [GooeyMember(rect: () => null, color: const Color(0xFF000000))],
    );
    addTearDown(s.dispose);
    expect(s.shapes, isNull);
    expect(s.shapeIndexOf(0), isNull);
  });

  testWidgets('the surfaces of the members that are there are drawn',
      (tester) async {
    middle = null;
    final s = scene();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: GooeyStage(
        scene: s,
        children: [
          GooeyBackdrop(scene: s),
          Positioned(
            left: 0,
            top: 0,
            width: 100,
            height: 56,
            child: GooeySurface(scene: s, index: 0),
          ),
          Positioned(
            left: 104,
            top: 0,
            width: 56,
            height: 56,
            child: GooeySurface(scene: s, index: 2),
          ),
        ],
      ),
    ));
    expect(tester.takeException(), isNull);
    // The last member is painted as a shape of the scene (a rounded rect
    // without the shader), not as the "not ready" fallback (a path).
    expect(
      find
          .descendant(
            of: find.byType(GooeySurface).last,
            matching: find.byType(CustomPaint),
          )
          .first,
      paints..rrect(color: const Color(0xFF6655AA)),
    );
  });
}
