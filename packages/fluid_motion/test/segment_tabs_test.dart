import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

/// Two tabs in a 300 × 64 box; [selected] is read on every build.
class _Harness extends StatefulWidget {
  const _Harness({this.textScale = 1, this.selectedIconKey});
  final double textScale;
  final GlobalKey? selectedIconKey;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int selected = 0;

  // An app's shortcuts (Tab moves the focus) and a focused scope, as a
  // Navigator gives a real app.
  @override
  Widget build(BuildContext context) => WidgetsApp(
        color: const Color(0xFFFFFFFF),
        debugShowCheckedModeBanner: false,
        builder: (context, _) => FocusScope(
          autofocus: true,
          child: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(widget.textScale),
            ),
            child: Center(
              child: SizedBox(
                width: 300,
                height: 64,
                child: SegmentTabs(
                  tabs: const [
                    SegmentTab(label: 'First', icon: SizedBox.expand()),
                    SegmentTab(label: 'Second', icon: SizedBox.expand()),
                  ],
                  selected: selected,
                  onSelected: (i) => setState(() => selected = i),
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF222222),
                  ),
                  indicatorColor: const Color(0x22000000),
                  focusColor: const Color(0xFF0000FF),
                  selectedIconKey: widget.selectedIconKey,
                ),
              ),
            ),
          ),
        ),
      );
}

_HarnessState _state(WidgetTester tester) =>
    tester.state<_HarnessState>(find.byType(_Harness));

SegmentSpring _segments(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find
      .descendant(
        of: find.byType(SegmentTabs),
        matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is SegmentIndicatorPainter),
      )
      .first);
  return (paint.painter! as SegmentIndicatorPainter).segments;
}

void main() {
  testWidgets('a tap selects the tab, and the indicator stretches over',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.tap(find.text('Second'));
    expect(_state(tester).selected, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final s = _segments(tester);
    // Moving right: the right edge leads, the left lags – it is stretched.
    expect(s.right - s.left, greaterThan(1.05));
    await tester.pumpAndSettle();
    expect(s.left, closeTo(1, 0.02));
    expect(s.right, closeTo(2, 0.02));
  });

  testWidgets('keyboard: Tab focuses with a ring, Enter and Space activate',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // A focus ring is painted on the focused tab only.
    expect(
      find.descendant(
        of: find.byType(SegmentTabs),
        matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.foregroundPainter != null),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(_state(tester).selected, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(_state(tester).selected, 0);
  });

  testWidgets('screen reader: each tab is a button with its label and state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Harness());
    expect(
      tester.getSemantics(find.bySemanticsLabel('First')),
      matchesSemantics(
        label: 'First',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Second')),
      matchesSemantics(
        label: 'Second',
        isButton: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('200 % text: the label is not shrunk, only cut off',
      (tester) async {
    await tester.pumpWidget(const _Harness(textScale: 2));
    final text = tester.renderObject<RenderParagraph>(find.text('Second'));
    expect(text.textScaler, const TextScaler.linear(2));
    expect(find.byType(FittedBox), findsNothing);
    // Full-size glyphs: the line is about twice the 1x height.
    expect(text.size.height, greaterThan(14 * 2 * 0.9));
  });

  testWidgets('squeezed narrower than its icon, a tab clips – no overflow',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 64,
          height: 64,
          child: SegmentTabs(
            tabs: [
              SegmentTab(label: 'First', icon: SizedBox.expand()),
              SegmentTab(label: 'Second', icon: SizedBox.expand()),
            ],
            selected: 0,
            onSelected: _ignore,
            labelStyle: TextStyle(fontSize: 14),
            indicatorColor: Color(0x22000000),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('each tab is at least 48 × 48', (tester) async {
    await tester.pumpWidget(const _Harness());
    final size = tester.getSize(find
        .ancestor(of: find.text('First'), matching: find.byType(Semantics))
        .first);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('selectedIconKey leaves a keyed space on the selected tab',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(_Harness(selectedIconKey: key));
    expect(find.byKey(key), findsOneWidget);
    final first = tester.getRect(find.text('First'));
    expect(tester.getRect(find.byKey(key)).right, lessThan(first.left));
    await tester.tap(find.text('Second'));
    await tester.pump();
    final second = tester.getRect(find.text('Second'));
    expect(tester.getRect(find.byKey(key)).right, lessThan(second.left));
  });
}

void _ignore(int _) {}
