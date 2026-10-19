import 'package:flutter/material.dart';

import '../bottom_bar/bottom_bar_motion.dart';
import 'frame_stats.dart';

/// A small panel in the top right corner: shows frame cost, fps and jank,
/// and toggles each effect and GPU/CPU live – so you can find out on the
/// device itself what costs what.
class MotionDebugPanel extends StatefulWidget {
  const MotionDebugPanel({
    super.key,
    required this.stats,
    required this.motion,
    required this.onMotionChanged,
    required this.useShader,
    required this.shaderReady,
    required this.onShaderChanged,
    this.diagnostics = const [],
    this.status,
  });

  final FrameStats stats;
  final BottomBarMotion motion;
  final ValueChanged<BottomBarMotion> onMotionChanged;
  final bool useShader, shaderReady;
  final ValueChanged<bool> onShaderChanged;

  /// Extra switches to isolate what costs (label, value, on change).
  final List<(String, bool, ValueChanged<bool>)> diagnostics;

  /// Optional status line at the top of the open panel.
  final Widget? status;

  @override
  State<MotionDebugPanel> createState() => _MotionDebugPanelState();
}

class _MotionDebugPanelState extends State<MotionDebugPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flags = widget.motion.toMap();

    final summary = ListenableBuilder(
      listenable: widget.stats,
      builder: (context, _) {
        final s = widget.stats;
        if (s.frames == 0 && !s.hasTimings) {
          return Text('Scroll to measure', style: theme.textTheme.labelMedium);
        }
        String ms(double v) => v.toStringAsFixed(1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.hasTimings
                  ? 'build ${ms(s.buildAvg)} + raster ${ms(s.rasterAvg)} ms · '
                      '90 %: ${ms(s.totalP90)} ms · '
                      '${(s.overBudgetShare * 100).toStringAsFixed(0)} % over 16'
                  : 'build/raster: not available',
              style: theme.textTheme.labelMedium,
            ),
            Text(
              '${s.fps.toStringAsFixed(0)} fps · '
              '${(s.slowShare * 100).toStringAsFixed(0)} % jank · '
              'worst gap ${s.worst.toStringAsFixed(0)} ms · '
              'heaviest frame ${s.heaviest.toStringAsFixed(0)} ms '
              '(build ${s.heaviestBuild.toStringAsFixed(0)} + '
              'raster ${s.heaviestRaster.toStringAsFixed(0)})',
              style: theme.textTheme.labelSmall,
            ),
          ],
        );
      },
    );

    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(child: summary),
                      Icon(_open ? Icons.expand_less : Icons.tune, size: 18),
                    ],
                  ),
                ),
              ),
              if (_open)
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      if (widget.status != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: widget.status,
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: OutlinedButton(
                          onPressed: widget.stats.reset,
                          child: const Text('Reset measurement'),
                        ),
                      ),
                      for (final (label, value, onChanged)
                          in widget.diagnostics)
                        SwitchListTile(
                          dense: true,
                          title: Text(label),
                          value: value,
                          onChanged: onChanged,
                        ),
                      SwitchListTile(
                        dense: true,
                        title: const Text('Draw on GPU'),
                        subtitle: widget.shaderReady
                            ? null
                            : const Text('The shader is not loaded'),
                        value: widget.useShader && widget.shaderReady,
                        onChanged:
                            widget.shaderReady ? widget.onShaderChanged : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () => widget.onMotionChanged(
                                BottomBarMotion.none,
                              ),
                              child: const Text('All off'),
                            ),
                            TextButton(
                              onPressed: () => widget.onMotionChanged(
                                kBottomBarMotion,
                              ),
                              child: const Text('Default'),
                            ),
                          ],
                        ),
                      ),
                      for (final MapEntry(key: name, value: on)
                          in flags.entries)
                        SwitchListTile(
                          dense: true,
                          title: Text(BottomBarMotion.labels[name] ?? name),
                          value: on,
                          onChanged: (v) => widget.onMotionChanged(
                            BottomBarMotion.fromMap({...flags, name: v}),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
