import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../tokens.dart';
import 'segment.dart';

/// One tab in [SegmentTabs].
@immutable
class SegmentTab {
  const SegmentTab({required this.label, this.icon});

  /// The tab's text – also what a screen reader says.
  final String label;

  /// An icon before the label (optional), e.g. an `Icon`.
  final Widget? icon;
}

/// A row of tabs with a stretchy indicator behind the selected one: the
/// leading edge is stiff, the trailing edge soft, so the indicator stretches
/// like a droplet when the selection moves and contracts again
/// ([SegmentSpring], [SegmentIndicatorPainter]).
///
/// Every colour and shape is a parameter. Fills the space it is given; each
/// tab gets an equal share and at least [minTapSize] in both directions.
///
/// Accessible: each tab is a button with its label and selected state, can
/// be focused with the keyboard (a visible focus ring) and activated with
/// Enter or Space. The label never shrinks with large text – it is cut off
/// with an ellipsis after [labelMaxLines] lines instead. With "Reduce
/// motion" ([MotionScope.reduceMotionOf]) the indicator jumps without
/// stretching.
///
/// To let the selected icon fly somewhere else (e.g. into a button when the
/// bar folds), give [selectedIconKey]: the selected tab then leaves an
/// empty space of [iconSize] with that key, and a [FlyingIcon] with
/// `FlightPoint.anchor(selectedIconKey)` draws the icon.
class SegmentTabs extends StatefulWidget {
  const SegmentTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.labelStyle,
    required this.indicatorColor,
    this.selectedLabelStyle,
    this.focusColor,
    this.indicatorInset = 4,
    this.indicatorRadius,
    this.iconSize = 24,
    this.iconGap = 8,
    this.labelMaxLines = 1,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
    this.minTapSize = 48,
    this.stretchy = true,
    this.slides,
    this.selectedIconKey,
  });

  final List<SegmentTab> tabs;

  /// The selected tab's index.
  final int selected;

  /// Called with a tab's index when it is tapped or activated.
  final ValueChanged<int> onSelected;

  /// The labels' style (and the icons' colour, through `IconTheme`).
  final TextStyle labelStyle;

  /// The selected tab's label style; [labelStyle] if null.
  final TextStyle? selectedLabelStyle;

  /// The indicator behind the selected tab.
  final Color indicatorColor;

  /// The focus ring; the label colour if null.
  final Color? focusColor;

  /// Space around the indicator and the focus ring inside each tab (px).
  final double indicatorInset;

  /// The indicator's and focus ring's corner radius; null = a pill.
  final double? indicatorRadius;

  final double iconSize, iconGap;

  /// How many lines a label may wrap to before it is cut off with an
  /// ellipsis.
  final int labelMaxLines;

  /// Space between a tab's edge and its content.
  final EdgeInsetsGeometry padding;

  /// The smallest tap target (dp), in both directions.
  final double minTapSize;

  /// false = the indicator jumps instead of stretching.
  final bool stretchy;

  /// A paint-time offset for each tab's content (fractions of its size, like
  /// `SlideTransition`), e.g. to glide the labels towards the centre while a
  /// bar folds. One per tab, or null.
  final List<Animation<Offset>>? slides;

  /// When set, the selected tab leaves an empty, keyed space for its icon,
  /// drawn by a [FlyingIcon] instead.
  final GlobalKey? selectedIconKey;

  @override
  State<SegmentTabs> createState() => _SegmentTabsState();
}

class _SegmentTabsState extends State<SegmentTabs>
    with TickerProviderStateMixin {
  late final SegmentSpring _segments =
      SegmentSpring(vsync: this, index: widget.selected);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = MotionScope.of(context);
    _segments
      ..lead = SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: tokens.indicatorLeadStiffness,
        ratio: 0.7,
      )
      ..trail = SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: tokens.indicatorTrailStiffness,
        ratio: 0.8,
      );
  }

  @override
  void didUpdateWidget(SegmentTabs old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) _segments.moveTo(widget.selected);
  }

  @override
  void dispose() {
    _segments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _segments.stretchy =
        widget.stretchy && !MotionScope.reduceMotionOf(context);
    final tabs = widget.tabs;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: SegmentIndicatorPainter(
              segments: _segments,
              count: tabs.length,
              color: widget.indicatorColor,
              inset: widget.indicatorInset,
              radius: widget.indicatorRadius,
            ),
          ),
        ),
        Positioned.fill(
          child: Row(
            children: [
              for (final (i, tab) in tabs.indexed)
                Expanded(
                  child: _TabItem(
                    tab: tab,
                    selected: i == widget.selected,
                    onTap: () => widget.onSelected(i),
                    owner: widget,
                    slide: widget.slides?[i],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One tab: a focusable button with a focus ring.
class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.owner,
    required this.slide,
  });

  final SegmentTab tab;
  final bool selected;
  final VoidCallback onTap;
  final SegmentTabs owner;
  final Animation<Offset>? slide;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _focused = false;

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onTap();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final o = widget.owner;
    final style =
        widget.selected ? (o.selectedLabelStyle ?? o.labelStyle) : o.labelStyle;
    final icon = widget.tab.icon;
    final Widget? leading = icon == null
        ? null
        : (widget.selected && o.selectedIconKey != null)
            ? SizedBox.square(key: o.selectedIconKey, dimension: o.iconSize)
            : SizedBox.square(
                dimension: o.iconSize,
                child: IconTheme.merge(
                  data: IconThemeData(size: o.iconSize, color: style.color),
                  child: icon,
                ),
              );

    // Never narrower than the padding and the icon: a tab squeezed below
    // that (e.g. while a bar folds into a button) is clipped, not shrunk.
    final padding = o.padding.resolve(Directionality.maybeOf(context));
    final minWidth =
        padding.horizontal + (leading == null ? 0 : o.iconSize + o.iconGap);
    Widget content = Padding(
      padding: o.padding,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading, SizedBox(width: o.iconGap)],
            Flexible(
              child: Text(
                widget.tab.label,
                style: style,
                maxLines: o.labelMaxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
    content = ClipRect(
      child: CustomSingleChildLayout(
        delegate: _AtLeastWide(minWidth),
        child: content,
      ),
    );
    final slide = widget.slide;
    if (slide != null) {
      content = SlideTransition(position: slide, child: content);
    }

    final ring = o.focusColor ?? style.color ?? const Color(0xFF000000);
    // The focus node's semantics (focusable, focused) merge with the
    // button's below it into one node.
    return FocusableActionDetector(
      shortcuts: _shortcuts,
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: Semantics(
        button: true,
        enabled: true,
        selected: widget.selected,
        inMutuallyExclusiveGroup: true,
        label: widget.tab.label,
        excludeSemantics: true,
        onTap: widget.onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: o.minTapSize,
              minHeight: o.minTapSize,
            ),
            child: CustomPaint(
              foregroundPainter: _focused
                  ? _FocusRing(ring, o.indicatorInset, o.indicatorRadius)
                  : null,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays the child out at least [minWidth] wide, centred – wider than the
/// space if need be (the caller clips it).
class _AtLeastWide extends SingleChildLayoutDelegate {
  const _AtLeastWide(this.minWidth);
  final double minWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    if (!constraints.hasBoundedWidth) return constraints.loosen();
    final max =
        constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth;
    return BoxConstraints(
      minWidth: max,
      maxWidth: max,
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset((size.width - childSize.width) / 2, 0);

  @override
  bool shouldRelayout(_AtLeastWide old) => old.minWidth != minWidth;
}

/// The focus ring: 2 px, the indicator's shape.
class _FocusRing extends CustomPainter {
  const _FocusRing(this.color, this.inset, this.radius);
  final Color color;
  final double inset;
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(inset + 1);
    if (r.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(radius ?? r.height / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FocusRing old) =>
      old.color != color || old.inset != inset || old.radius != radius;
}
