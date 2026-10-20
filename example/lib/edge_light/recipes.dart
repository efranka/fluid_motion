import 'package:flutter/material.dart';
import 'package:fluid_motion/fluid_motion.dart';

/// A few [GooeyLight] recipes, to show how different one building block can
/// look. Each is chosen from how light the fill is, since the colours are
/// laid over it.
enum EdgeLightRecipe {
  /// A soft rim lit from above and below: a 1 px edge lightest at the top
  /// and bottom, a faint inner glow there, a fill a little lighter at the
  /// top and a soft shadow.
  rimLight('Rim light'),

  /// Only a hairline edge.
  hairline('Hairline'),

  /// A strong glow all along the outline and a bright edge, no shadow.
  strongGlow('Strong glow'),

  /// Only a deep shadow.
  shadowOnly('Shadow only');

  const EdgeLightRecipe(this.label);
  final String label;

  /// The light for shapes filled with [fill]; [shadow] is the shadow colour
  /// (e.g. `ColorScheme.shadow`).
  GooeyLight forFill(Color fill, {Color shadow = Colors.black}) {
    final dark = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark;
    const white = Colors.white;
    switch (this) {
      case rimLight:
        return dark
            ? GooeyLight(
                edgeColors: [
                  white.withValues(alpha: 0.18),
                  white.withValues(alpha: 0.05),
                  white.withValues(alpha: 0.05),
                  white.withValues(alpha: 0.13),
                ],
                edgeStops: const [0, 0.3, 0.7, 1],
                fillStart: white.withValues(alpha: 0.04),
                glowStart: white.withValues(alpha: 0.12),
                glowEnd: white.withValues(alpha: 0.08),
                glowDepth: 12,
                shadows: [
                  BoxShadow(
                    color: shadow.withValues(alpha: 0.35),
                    offset: const Offset(0, 6),
                    blurRadius: 18,
                  ),
                ],
              )
            : GooeyLight(
                edgeColors: [
                  white,
                  shadow.withValues(alpha: 0.04),
                  shadow.withValues(alpha: 0.04),
                  shadow.withValues(alpha: 0.10),
                ],
                edgeStops: const [0, 0.3, 0.7, 1],
                fillStart: white.withValues(alpha: 0.6),
                glowStart: white.withValues(alpha: 0.9),
                glowEnd: shadow.withValues(alpha: 0.04),
                glowDepth: 12,
                shadows: [
                  BoxShadow(
                    color: shadow.withValues(alpha: 0.05),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                  BoxShadow(
                    color: shadow.withValues(alpha: 0.07),
                    offset: const Offset(0, 6),
                    blurRadius: 18,
                  ),
                ],
              );
      case hairline:
        return GooeyLight(
          edgeColors: [
            dark
                ? white.withValues(alpha: 0.25)
                : shadow.withValues(alpha: 0.15),
          ],
        );
      case strongGlow:
        return GooeyLight(
          edgeWidth: 1.5,
          edgeColors: [white.withValues(alpha: dark ? 0.5 : 0.9)],
          outlineGlow: white.withValues(alpha: dark ? 0.22 : 0.6),
          outlineGlowDepth: 14,
        );
      case shadowOnly:
        return GooeyLight(
          edgeWidth: 0,
          shadows: [
            BoxShadow(
              color: shadow.withValues(alpha: dark ? 0.5 : 0.18),
              offset: const Offset(0, 10),
              blurRadius: 28,
            ),
          ],
        );
    }
  }
}
