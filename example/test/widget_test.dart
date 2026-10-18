import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';
import 'package:fluid_motion_example/bottom_bar/program_screen.dart';
import 'package:fluid_motion_example/main.dart';
import 'package:fluid_motion_example/shapes/shapes_screen.dart';

Widget _app(Widget home) => MotionScope(
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFCBC3F5),
            brightness: Brightness.dark,
          ),
        ),
        home: home,
      ),
    );

void main() {
  testWidgets('the home screen lists both demos', (tester) async {
    await tester.pumpWidget(_app(const DemoHome()));
    expect(find.text('Bottom bar'), findsOneWidget);
    expect(find.text('Shapes'), findsOneWidget);
  });

  testWidgets('the bottom bar shows and folds on scroll', (tester) async {
    await tester.pumpWidget(_app(const ProgramScreen()));
    await tester.pump();

    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Program'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Back to the top unfolds it again.
    await tester.fling(find.byType(ListView), const Offset(0, 2000), 3000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs moves the pill without errors', (tester) async {
    await tester.pumpWidget(_app(const ProgramScreen()));
    await tester.pump();
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shapes can be dragged into each other and spring home',
      (tester) async {
    await tester.pumpWidget(_app(const ShapesScreen()));
    await tester.pump(); // places the shapes after the first layout
    await tester.pump();
    final star = find.byIcon(Icons.star_border);
    final heart = find.byIcon(Icons.favorite_border);
    expect(star, findsOneWidget);
    final start = tester.getCenter(star);
    await tester.timedDrag(
      star,
      tester.getCenter(heart) - start,
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Home again.
    expect((tester.getCenter(star) - start).distance, lessThan(1));
  });
}
