import 'package:flutter/material.dart';

/// Icon size and gap in the tab bar.
const kTabIconSize = 24.0;
const kTabIconGap = 8.0;

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
