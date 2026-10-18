import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('taps $taps'),
      );
}

void main() {
  testWidgets('warms up for a few frames and keeps the child state',
      (tester) async {
    await tester.pumpWidget(
      const MotionWarmUp(
        child: MaterialApp(home: Scaffold(body: Center(child: _Counter()))),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);

    // Let the warm-up finish; the child must keep its state.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(find.text('taps 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
