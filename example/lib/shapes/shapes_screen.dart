import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:fluid_motion/fluid_motion.dart';

/// A playground for free-form gooey shapes: drag any shape towards another
/// and they flow together, blend colours, blob on catch and release, and
/// pull each other's icons in. Let go and the shape springs home – with a
/// bounce graded by how fast you threw it.
///
/// The same [GooeyScene] as the bottom bar, just with other outlines – the
/// scene only knows rects, outlines and colours.
class ShapesScreen extends StatefulWidget {
  const ShapesScreen({super.key});

  @override
  State<ShapesScreen> createState() => _ShapesScreenState();
}

class _Item {
  _Item({
    required this.geometry,
    required this.size,
    required this.home,
    required this.color,
    this.icon,
  });

  final GooeyGeometry geometry;
  final Size size;

  /// Home position as a fraction of the screen (0..1 on both axes).
  final Offset home;
  final Color Function(ColorScheme) color;
  final IconData? icon;

  late final AnimationController x, y;
  late final Listenable motion;
  bool dragging = false;

  Rect get rect => Rect.fromCenter(
        center: Offset(x.value, y.value),
        width: size.width,
        height: size.height,
      );
}

/// A heart, as an example of an outline from any [Path].
Path _heart(Size s) {
  final w = s.width, h = s.height;
  return Path()
    ..moveTo(w / 2, h * 0.95)
    ..cubicTo(w * 0.1, h * 0.65, -w * 0.05, h * 0.3, w * 0.25, h * 0.08)
    ..cubicTo(w * 0.38, -h * 0.02, w * 0.48, h * 0.1, w / 2, h * 0.22)
    ..cubicTo(w * 0.52, h * 0.1, w * 0.62, -h * 0.02, w * 0.75, h * 0.08)
    ..cubicTo(w * 1.05, h * 0.3, w * 0.9, h * 0.65, w / 2, h * 0.95)
    ..close();
}

class _ShapesScreenState extends State<ShapesScreen>
    with TickerProviderStateMixin {
  final _quality = MotionQuality();

  late final List<_Item> _items = [
    _Item(
      geometry: const GooeyCircle(),
      size: const Size(104, 104),
      home: const Offset(0.28, 0.24),
      color: (cs) => cs.primaryContainer,
      icon: Icons.favorite_border,
    ),
    _Item(
      geometry: const GooeyStar(points: 5, innerRatio: 0.52, cornerRadius: 6),
      size: const Size(128, 128),
      home: const Offset(0.72, 0.3),
      color: (cs) => cs.tertiaryContainer,
      icon: Icons.star_border,
    ),
    _Item(
      geometry: const GooeyRing(thickness: 0.45),
      size: const Size(116, 116),
      home: const Offset(0.3, 0.52),
      color: (cs) => cs.secondaryContainer,
    ),
    _Item(
      geometry: GooeyPolygon.regular(6, cornerRadius: 10),
      size: const Size(110, 110),
      home: const Offset(0.72, 0.56),
      color: (cs) => cs.surfaceContainerHighest,
      icon: Icons.hexagon_outlined,
    ),
    _Item(
      geometry: const GooeyRoundedRect(),
      size: const Size(168, 64),
      home: const Offset(0.5, 0.76),
      color: (cs) => cs.primaryContainer,
      icon: Icons.drag_indicator,
    ),
    _Item(
      geometry: const GooeyPathGeometry(_heart),
      size: const Size(100, 92),
      home: const Offset(0.5, 0.9),
      color: (cs) => cs.errorContainer,
    ),
  ];

  late final GooeyScene _scene;
  Size? _area;
  bool _ready = false; // shapes placed at home
  MotionTokens _tokens = MotionTokens.standard;

  @override
  void initState() {
    super.initState();
    for (final item in _items) {
      item
        ..x = AnimationController.unbounded(vsync: this)
        ..y = AnimationController.unbounded(vsync: this);
      item.motion = Listenable.merge([item.x, item.y]);
    }
    _scene = GooeyScene(
      vsync: this,
      motion: Listenable.merge([for (final i in _items) i.motion]),
      quality: _quality,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tokens = MotionScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MotionScope.reduceMotionOf(context);
    _scene
      ..members = [
        for (final item in _items)
          GooeyMember(
            rect: () => _ready ? item.rect : null,
            color: item.color(cs),
            geometry: item.geometry,
          ),
      ]
      ..style = reduceMotion ? GooeyStyle.off : const GooeyStyle();
  }

  Offset _homeOf(_Item item) =>
      Offset(item.home.dx * _area!.width, item.home.dy * _area!.height);

  /// Place every shape at home when the area is first known or changes size
  /// (e.g. rotation) – except shapes being dragged. Runs after layout, since
  /// moving the shapes during layout would rebuild widgets mid-frame.
  void _layout(Size area) {
    if (_area == area) return;
    _area = area;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final item in _items) {
        if (item.dragging) continue;
        final home = _homeOf(item);
        item.x.value = home.dx;
        item.y.value = home.dy;
      }
      if (!_ready) setState(() => _ready = true);
    });
  }

  void _dragStart(_Item item) {
    item.dragging = true;
    item.x.stop();
    item.y.stop();
  }

  void _dragUpdate(_Item item, DragUpdateDetails d) {
    item.x.value += d.delta.dx;
    item.y.value += d.delta.dy;
  }

  /// The finger lets go: the shape springs home with exactly the finger's
  /// velocity – and the faster it was thrown, the more it bounces.
  void _dragEnd(_Item item, Velocity velocity) {
    item.dragging = false;
    final v = velocity.pixelsPerSecond;
    final spring = MotionScope.reduceMotionOf(context)
        ? _tokens.primary.calm
        : _tokens.primary.forSpeed(v.distance);
    final home = _homeOf(item);
    item.x.animateWith(SpringSimulation(spring, item.x.value, home.dx, v.dx));
    item.y.animateWith(SpringSimulation(spring, item.y.value, home.dy, v.dy));
  }

  @override
  void dispose() {
    _scene.dispose();
    _quality.dispose();
    for (final item in _items) {
      item.x.dispose();
      item.y.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = cs.onPrimaryContainer;

    Widget placed(_Item item, Widget child) => AnimatedBuilder(
          animation: item.motion,
          child: child,
          builder: (context, child) => Positioned.fromRect(
            rect: _ready ? item.rect : Rect.zero,
            child: child!,
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Shapes')),
      body: LayoutBuilder(
        builder: (context, box) {
          _layout(box.biggest);
          return GooeyStage(
            scene: _scene,
            children: [
              Positioned(
                left: 16,
                right: 16,
                top: 8,
                child: Text(
                  'Drag a shape towards another – and throw it.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              GooeyBackdrop(scene: _scene),
              // Backgrounds first, then content – so content in one shape
              // can be seen dissolving into another.
              for (final (i, item) in _items.indexed)
                placed(item, GooeySurface(scene: _scene, index: i)),
              for (final (i, item) in _items.indexed)
                placed(
                  item,
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => _dragStart(item),
                    onPanUpdate: (d) => _dragUpdate(item, d),
                    onPanEnd: (d) => _dragEnd(item, d.velocity),
                    onPanCancel: () => _dragEnd(item, Velocity.zero),
                    child: item.icon == null
                        ? const SizedBox.expand()
                        : Center(
                            child: GooeyContent(
                              scene: _scene,
                              index: i,
                              child: Icon(
                                item.icon,
                                color: iconColor,
                                size:
                                    math.min(item.size.shortestSide * 0.36, 32),
                              ),
                            ),
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
