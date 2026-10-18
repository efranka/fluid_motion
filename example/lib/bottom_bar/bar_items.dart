import 'package:flutter/material.dart';

/// Icon size and gap in the tab bar (also used to place the flying icon
/// exactly).
const kTabIconSize = 24.0;
const kTabIconGap = 8.0;

/// A tab in the tab bar. The selected tab's icon is drawn by the flying icon
/// layer – here it leaves an empty space of the same size.
class ToggleLabel extends StatelessWidget {
  const ToggleLabel({
    super.key,
    required this.icon,
    required this.label,
    required this.style,
    required this.selected,
    required this.slide,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final TextStyle style;
  final bool selected;
  final Animation<Offset> slide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SlideTransition(
              position: slide,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        const SizedBox.square(dimension: kTabIconSize)
                      else
                        Icon(icon, size: kTabIconSize, color: style.color),
                      const SizedBox(width: kTabIconGap),
                      Text(label, style: style, maxLines: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// An item in the navigation bar.
class NavItem extends StatelessWidget {
  const NavItem(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
