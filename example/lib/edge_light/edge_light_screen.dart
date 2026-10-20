import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluid_motion/fluid_motion.dart';

import 'flat_light.dart';
import 'recipes.dart';

/// The size of each comparison panel.
const kEdgeLightPanel = Size(360, 150);

/// Edge light, side by side: the same [GooeyLight] drawn the plain Flutter
/// way, one shape at a time ([FlatLight]), and by a [GooeyScene] along the
/// merged shape. Slide the shapes together to see where they differ.
class EdgeLightScreen extends StatefulWidget {
  const EdgeLightScreen({super.key, this.initialGap = 24});

  final double initialGap;

  @override
  State<EdgeLightScreen> createState() => _EdgeLightScreenState();
}

class _EdgeLightScreenState extends State<EdgeLightScreen>
    with TickerProviderStateMixin {
  late final _gap = ValueNotifier(widget.initialGap);
  late final _scene = GooeyScene(vsync: this, motion: _gap);
  var _recipe = EdgeLightRecipe.rimLight;
  Brightness? _brightness;

  /// The bar and the button, in panel coordinates.
  static Rect barRect() => const Rect.fromLTWH(16, 43, 240, 64);
  Rect buttonRect() => Rect.fromLTWH(16 + 240 + _gap.value, 43, 64, 64);

  @override
  void dispose() {
    _scene.dispose();
    _gap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context);
    final brightness = _brightness ?? outer.brightness;
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: outer.colorScheme.primary,
        brightness: brightness,
      ),
    );
    final cs = theme.colorScheme;
    final light = _recipe.forFill(cs.surfaceContainer, shadow: cs.shadow);
    // Paint-only changes: members and style just repaint the scene.
    _scene
      ..members = [
        GooeyMember(rect: barRect, color: cs.surfaceContainer),
        GooeyMember(rect: buttonRect, color: cs.primaryContainer),
      ]
      ..style = GooeyStyle(
        blob: false,
        contentBlend: false,
        neckStyle: const GooeyNeckStyle(reach: 12),
        light: light,
      );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edge light')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Plain Flutter – each shape on its own',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            EdgeLightFlatPanel(
              gap: _gap,
              light: light,
              barColor: cs.surfaceContainer,
              buttonColor: cs.primaryContainer,
              background: cs.surface,
            ),
            const SizedBox(height: 16),
            Text('fluid_motion – along the merged shape',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            EdgeLightGooeyPanel(
              scene: _scene,
              gap: _gap,
              background: cs.surface,
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: _gap,
              builder: (context, gap, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gap: ${gap.toStringAsFixed(0)} px'),
                  Slider(
                    min: -40,
                    max: 40,
                    value: gap,
                    onChanged: (v) => _gap.value = v,
                  ),
                ],
              ),
            ),
            SegmentedButton<EdgeLightRecipe>(
              segments: [
                for (final r in EdgeLightRecipe.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_recipe},
              onSelectionChanged: (s) => setState(() => _recipe = s.first),
            ),
            SwitchListTile(
              title: const Text('Dark'),
              value: brightness == Brightness.dark,
              onChanged: (v) => setState(
                () => _brightness = v ? Brightness.dark : Brightness.light,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reference: each shape drawn on its own with [FlatLight].
class EdgeLightFlatPanel extends StatelessWidget {
  const EdgeLightFlatPanel({
    super.key,
    required this.gap,
    required this.light,
    required this.barColor,
    required this.buttonColor,
    required this.background,
  });

  final ValueListenable<double> gap;
  final GooeyLight light;
  final Color barColor, buttonColor, background;

  @override
  Widget build(BuildContext context) => _Panel(
        background: background,
        child: ValueListenableBuilder<double>(
          valueListenable: gap,
          builder: (context, g, _) => Stack(
            children: [
              Positioned.fromRect(
                rect: _EdgeLightScreenState.barRect(),
                child: FlatLight(light: light, color: barColor),
              ),
              Positioned.fromRect(
                rect: Rect.fromLTWH(16 + 240 + g, 43, 64, 64),
                child: FlatLight(light: light, color: buttonColor),
              ),
            ],
          ),
        ),
      );
}

/// The same two shapes as one [GooeyScene].
class EdgeLightGooeyPanel extends StatelessWidget {
  const EdgeLightGooeyPanel({
    super.key,
    required this.scene,
    required this.gap,
    required this.background,
  });

  final GooeyScene scene;
  final ValueListenable<double> gap;
  final Color background;

  @override
  Widget build(BuildContext context) => _Panel(
        background: background,
        child: ValueListenableBuilder<double>(
          valueListenable: gap,
          builder: (context, _, __) {
            final members = scene.members;
            return GooeyStage(
              scene: scene,
              children: [
                GooeyBackdrop(scene: scene),
                for (final (i, m) in members.indexed)
                  if (m.rect() case final rect?)
                    Positioned.fromRect(
                      rect: rect,
                      child: GooeySurface(scene: scene, index: i),
                    ),
              ],
            );
          },
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.background, required this.child});
  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox.fromSize(
          size: kEdgeLightPanel,
          child: ColoredBox(color: background, child: child),
        ),
      );
}
