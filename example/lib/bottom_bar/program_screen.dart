import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:fluid_motion/fluid_motion.dart';

import '../debug/frame_stats.dart';
import '../debug/motion_debug_panel.dart';
import '../edge_light/recipes.dart';
import 'bar_items.dart';
import 'bottom_bar_motion.dart';

/// An event programme screen with a tab bar (Timeline/List) and a navigation
/// bar. Scrolling down folds the tab bar into a bubble next to the
/// navigation bar; scrolling up unfolds it.
///
/// The screen only describes GEOMETRY (where the shapes are at a given value)
/// and which effects are on. All physics, gooey, colour blending, blobs and
/// dissolving content come from the `fluid_motion` package.
class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen>
    with TickerProviderStateMixin {
  // --- Geometry ---
  static const _pad = 16.0, _gap = 12.0, _barHeight = 64.0, _fab = 64.0;
  static const _arc = 0.6; // 0 = straight line, 1 = strong arc
  static const _morphDistance = 120.0; // px of scroll for the whole morph
  static const _navItemLag = 0.006; // s per icon
  static const _navItemMaxOffset = 6.0; // px
  static const _impactStrength = 20.0; // px/s impact per morph unit/s
  static const _labelSlide = 0.3; // share of the tab's width
  static const _iconHop = 6.0; // px
  static final _impactSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 0.35);

  // --- Tab-bar ---
  static const _views = [
    (Icons.view_timeline_outlined, 'Timeline'),
    (Icons.view_list_outlined, 'List'),
  ];
  // Which way each tab's content slides (towards the bubble's centre).
  static const _slideSigns = [1.0, -1.0];
  int _selectedView = 1;

  // --- Motion ---
  // 0 = unfolded (tab bar above navigation bar), 1 = folded (bubble).
  late final DragSpringController _morph = DragSpringController(
    vsync: this,
    distance: _morphDistance,
  );
  AnimationController get _toggle => _morph.value;

  // The navigation bar lags behind (overlapping action).
  late final AnimationController _nav =
      AnimationController.unbounded(vsync: this);
  late final MorphFollower _navFollower = MorphFollower(
    controller: _nav,
    spring: MotionTokens.standard.follower,
  );

  // The flying icon: 0 = on its tab, 1 = in the bubble's centre (secondary
  // action).
  late final AnimationController _icon =
      AnimationController.unbounded(vsync: this);
  late final MorphFollower _iconFollower = MorphFollower(
    controller: _icon,
    spring: MotionTokens.standard.secondary,
    idleVelocityScale: 0,
  );

  // Impact on the navigation bar (px it is squeezed), oscillating around 0.
  late final AnimationController _impact =
      AnimationController.unbounded(vsync: this);

  // A shared press for the bubble's background and content (separate
  // layers).
  late final PressSpring _bubblePress = PressSpring(vsync: this);

  late final SegmentSpring _pill =
      SegmentSpring(vsync: this, index: _selectedView);

  // Created once (not in build), so listeners are not swapped on rebuild.
  late final Listenable _navLayerMotion =
      Listenable.merge([_nav, _impact, _morph.lean]);
  late final Listenable _bubbleLayerMotion =
      Listenable.merge([_toggle, _morph.lean]);
  late final Listenable _iconMotion = Listenable.merge([_icon, _toggle]);

  // Automatic quality: switches expensive effects off if the device cannot
  // keep up (old phone, low battery, Low Power Mode), and back on.
  final MotionQuality _quality = MotionQuality();
  static const _slowPhoneBudget = 3.0; // ms – for "Simulate slow phone"

  // Gooey: the navigation bar (0) and the tab bar/bubble (1).
  late final GooeyScene _scene = GooeyScene(
    vsync: this,
    motion: Listenable.merge([_toggle, _nav, _impact, _morph.lean]),
    quality: _quality,
  );

  // Fades and slides derived straight from the controller – no rebuilds.
  late final Animation<double> _labelsOpacity =
      _toggle.drive(const Ramp(0.5, 0.0));
  late final Animation<Offset> _labelSlideLeft = _toggle
      .drive(const Ramp(0.0, 0.5))
      .drive(Tween(begin: Offset.zero, end: const Offset(_labelSlide, 0)));
  late final Animation<Offset> _labelSlideRight = _toggle
      .drive(const Ramp(0.0, 0.5))
      .drive(Tween(begin: Offset.zero, end: const Offset(-_labelSlide, 0)));
  static const _noSlide = AlwaysStoppedAnimation(Offset.zero);

  // --- State ---
  BottomBarMotion _f = kBottomBarMotion;
  // The chosen set of effects (the debug panel can change it live).
  BottomBarMotion _chosen = kBottomBarMotion;
  bool _reduceMotion = false;
  bool _useShader = true;
  bool _hideBar = false;
  bool _freezeMorph = false;
  bool _collapseOnly = false;
  bool _hideContent = false;
  // Edge light and shadow along the merged outline (debug panel).
  bool _edgeLight = false;
  bool _shadow = false;
  bool get _lit => _edgeLight || _shadow;
  MotionTokens _tokens = MotionTokens.standard;
  ColorScheme? _cs;
  final _stats = FrameStats();

  // The latest layout: (stack height, fullWidth, maxWidth, bottomInset).
  // Stored in build and read by the scene, which paints outside build.
  (double, double, double, double)? _layout;

  bool get _collapsed => _morph.target == 1;

  @override
  void initState() {
    super.initState();
    _morph
      ..addFollower(_navFollower)
      ..addFollower(_iconFollower)
      ..onOvershoot = _onOvershoot;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tokens = MotionScope.of(context);
    _reduceMotion = MotionScope.reduceMotionOf(context);
    _cs = Theme.of(context).colorScheme;
    _apply();
  }

  /// Applies the chosen effects and tokens to the controllers and scene.
  void _apply() {
    final tokens = _tokens;
    final reduceMotion = _reduceMotion;
    _f = reduceMotion ? BottomBarMotion.none : _chosen;

    _morph
      ..spring = tokens.primary
      ..velocityBounce = _f.velocityBounce
      ..rubberBand = _f.rubberBand
      ..reduceMotion = reduceMotion;
    _navFollower
      ..spring = tokens.follower
      ..delay = tokens.followerDelay
      ..ratioOffset = tokens.followerRatioOffset;
    // The icon: its own, looser spring – or the bubble's, if switched off.
    _iconFollower
      ..spring = _f.iconSpring ? tokens.secondary : tokens.primary
      ..idleVelocityScale = _f.iconSpring ? 0 : 1;
    _pill.stretchy = _f.stretchyPill;

    final cs = _cs!;
    _scene
      ..members = [
        GooeyMember(
            rect: () => _shapeRects()?.$1, color: cs.surfaceContainerHigh),
        GooeyMember(rect: () => _shapeRects()?.$2, color: cs.primaryContainer),
      ]
      ..style = _gooeyStyle;
  }

  GooeyStyle get _gooeyStyle => GooeyStyle(
        neck: _f.gooey,
        colorBlend: _f.colorBlend,
        blob: _f.blobImpact,
        contentBlend: _f.contentBlend,
        useShader: _useShader,
        neckStyle: const GooeyNeckStyle(reach: _gap),
        light: !_lit ? null : _light,
      );

  /// The bar's light: the example's rim light recipe, with or without
  /// its edge and its shadow.
  GooeyLight get _light {
    final cs = _cs!;
    final rim = EdgeLightRecipe.rimLight
        .forFill(cs.surfaceContainerHigh, shadow: cs.shadow);
    if (!_edgeLight) return rim.shadowsOnly;
    return _shadow ? rim : rim.copyWith(shadows: const []);
  }

  void _setLight({bool? edge, bool? shadow}) {
    setState(() {
      _edgeLight = edge ?? _edgeLight;
      _shadow = shadow ?? _shadow;
    });
    _scene.style = _gooeyStyle;
  }

  void _setShader(bool on) {
    setState(() => _useShader = on);
    _scene.style = _gooeyStyle;
  }

  void _setMotion(BottomBarMotion motion) {
    setState(() {
      _chosen = motion;
      _apply();
    });
  }

  /// Impact: when the bubble lands next to the navigation bar and overshoots,
  /// part of its energy is passed on to the bar as an impact.
  void _onOvershoot(double target, double velocity) {
    if (!_f.impact || target != 1) return;
    final energy = _morph.spring.energy(velocity * _morphDistance);
    _impact.kick(velocity * _impactStrength * energy, _impactSpring);
  }

  void _selectView(int i) {
    if (_collapsed) {
      _morph.animateTo(0);
      return;
    }
    if (i == _selectedView) return;
    setState(() => _selectedView = i);
    _pill.moveTo(i);
  }

  // -------------------------------------------------------------------------
  // Geometry
  // -------------------------------------------------------------------------

  double get _arcAmount => _f.arcs ? _arc : 0.0;

  /// Arc curve for the vertical movement. Linear outside 0..1, so the
  /// spring's overshoot does not get a kink.
  double _arcCurve(double t) {
    final a = _arcAmount;
    if (t < 0) return t * (1 - a);
    if (t > 1) return 1 + (t - 1) * (1 + a);
    return t + a * (t * t - t);
  }

  double _arcSlope(double t) => 1 + _arcAmount * (2 * t.clamp(0.0, 1.0) - 1);

  double _toggleWidth(double fullWidth, double maxWidth) =>
      lerpDouble(fullWidth, _fab, _toggle.value)!.clamp(_fab * 0.8, maxWidth);

  double _toggleBottom(double bottomInset) =>
      bottomInset + (_barHeight + _gap) * (1 - _arcCurve(_toggle.value));

  double _navWidth(double fullWidth) =>
      lerpDouble(fullWidth, fullWidth - _fab - _gap, _nav.value)! -
      (_f.impact ? _impact.value : 0);

  /// The navigation bar's and tab bar's/bubble's rects in stack coordinates
  /// in the current frame (null before the first layout).
  (Rect, Rect)? _shapeRects() {
    final layout = _layout;
    if (layout == null) return null;
    final (stackHeight, fullWidth, maxWidth, bottomInset) = layout;
    final lean = _morph.lean.value;
    final nav = Rect.fromLTWH(
      _pad,
      stackHeight - bottomInset - _barHeight + lean,
      _navWidth(fullWidth),
      _barHeight,
    );
    final w = _toggleWidth(fullWidth, maxWidth);
    final bubble = Rect.fromLTWH(
      maxWidth - _pad - w,
      stackHeight - _toggleBottom(bottomInset) - _barHeight + lean,
      w,
      _barHeight,
    );
    return (nav, bubble);
  }

  /// Where the selected tab's icon sits on its own tab (x in the bubble and
  /// FittedBox scale). The icon stays put when switching tabs – only the
  /// pill behind it moves – and only travels when the bar folds.
  (double, double) _tabIconOnTab(double bubbleWidth, List<double> rowWidths) {
    final tab = bubbleWidth / _views.length;
    final i = _selectedView;
    final rowWidth = rowWidths[i];
    final fit = math.min(1.0, tab / rowWidth);
    final slide = _f.labelSlide
        ? _labelSlide *
            tab *
            const Ramp(0.0, 0.5).transform(_toggle.value) *
            _slideSigns[i]
        : 0.0;
    final x =
        tab * (i + 0.5) + slide + fit * (-rowWidth / 2 + kTabIconSize / 2);
    return (x, fit);
  }

  Widget _laggingNavItem(int index, Widget item) {
    if (!_f.navItemLag) return item;
    const shrink = _fab + _gap;
    final travel = shrink * (index + 1) / 5;
    final lag = _navItemLag * (index + 1);
    // Computed at paint time – no rebuild of the icon per frame.
    return MotionTransform(
      animation: _nav,
      transform: (_) => Matrix4.translationValues(
        (_nav.velocity * travel * lag)
            .clamp(-_navItemMaxOffset, _navItemMaxOffset),
        0,
        0,
      ),
      child: item,
    );
  }

  @override
  void dispose() {
    _stats.dispose();
    _scene.dispose();
    _quality.dispose();
    _morph.dispose();
    _nav.dispose();
    _icon.dispose();
    _impact.dispose();
    _bubblePress.dispose();
    _pill.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Build – only runs on first show, tab switch and e.g. theme change.
  // All per-frame work happens in AnimatedBuilder/CustomPaint/MotionTransform.
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom + 12;
    final onToggle = cs.onPrimaryContainer;
    final labelStyle =
        Theme.of(context).textTheme.labelLarge!.copyWith(color: onToggle);

    // Each tab's content width (icon + gap + text), measured once.
    final textScaler = MediaQuery.textScalerOf(context);
    final rowWidths = <double>[
      for (final (_, label) in _views)
        () {
          final painter = TextPainter(
            text: TextSpan(text: label, style: labelStyle),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          final width = kTabIconSize + kTabIconGap + painter.width;
          painter.dispose();
          return width;
        }(),
    ];

    // The shape's background: a plain DecoratedBox, or a GooeySurface that
    // can blend colour and "blob".
    Widget surface(int index, Color color) {
      if (!_f.colorBlend && !_f.blobImpact && !_lit) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_barHeight / 2),
          ),
          child: const SizedBox.expand(),
        );
      }
      return GooeySurface(scene: _scene, index: index);
    }

    final navContent = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (i, item) in const [
          NavItem(Icons.star_border, 'For you'),
          NavItem(Icons.list_alt, 'Program'),
          NavItem(Icons.search, 'Explore'),
          NavItem(Icons.more_horiz, 'More'),
        ].indexed)
          _laggingNavItem(
            i,
            GooeyContent(
              scene: _scene,
              index: 0,
              child: PressScale(enabled: _f.pressFeedback, child: item),
            ),
          ),
      ],
    );

    Widget toggleContent(double fullWidth, double maxWidth) => Semantics(
          container: true,
          label: 'View',
          child: Stack(
            children: [
              // Pill + tabs, fading out as the bubble folds.
              Positioned.fill(
                child: FadeTransition(
                  opacity: _labelsOpacity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: SegmentIndicatorPainter(
                            segments: _pill,
                            count: _views.length,
                            color: onToggle.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Row(
                          children: [
                            for (final (i, (icon, label)) in _views.indexed)
                              ToggleLabel(
                                icon: icon,
                                label: label,
                                style: labelStyle,
                                selected: i == _selectedView,
                                slide: !_f.labelSlide
                                    ? _noSlide
                                    : (i == 0
                                        ? _labelSlideLeft
                                        : _labelSlideRight),
                                onTap: () => _selectView(i),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // The flying icon: the selected tab's icon, drawn in one place
              // all the way from its tab to the bubble's centre. Moved and
              // scaled at paint time: no rebuild and no new layout per frame.
              Positioned.fill(
                child: IgnorePointer(
                  child: MotionTransform(
                    animation: _iconMotion,
                    alignment: Alignment.topLeft,
                    transform: (_) {
                      final p = _icon.value;
                      final pc = p.clamp(0.0, 1.0);
                      final w = _toggleWidth(fullWidth, maxWidth);
                      final (fromX, fit) = _tabIconOnTab(w, rowWidths);
                      final x = lerpDouble(fromX, w / 2, p)!;
                      final size =
                          lerpDouble(kTabIconSize * fit, kTabIconSize, pc)!;
                      final hop =
                          _f.iconHop ? _iconHop * math.sin(math.pi * pc) : 0.0;
                      return Matrix4.translationValues(
                        x - size / 2,
                        _barHeight / 2 - size / 2 - hop,
                        0,
                      )..multiply(Matrix4.diagonal3Values(
                          size / kTabIconSize,
                          size / kTabIconSize,
                          1,
                        ));
                    },
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox.square(
                        dimension: kTabIconSize,
                        child: GooeyContent(
                          scene: _scene,
                          index: 1,
                          child: Icon(
                            _views[_selectedView].$1,
                            size: kTabIconSize,
                            color: onToggle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      backgroundColor: const Color(0xFF141218),
      body: LayoutBuilder(
        builder: (context, box) {
          final fullWidth = box.maxWidth - _pad * 2;
          _layout = (box.maxHeight, fullWidth, box.maxWidth, bottomInset);

          // The navigation bar's and bubble's placement – used by both the
          // background and the content layer, so they always line up.
          Widget navLayer(Widget child) => AnimatedBuilder(
                animation: _navLayerMotion,
                // Own layer: not repainted when only the other layers change.
                child: RepaintBoundary(child: child),
                builder: (context, child) => Positioned(
                  left: _pad,
                  bottom: bottomInset - _morph.lean.value,
                  height: _barHeight,
                  width: _navWidth(fullWidth),
                  child: child!,
                ),
              );

          Widget bubbleLayer(Widget child) => AnimatedBuilder(
                animation: _bubbleLayerMotion,
                child: RepaintBoundary(child: child),
                builder: (context, child) {
                  final t = _toggle.value;
                  final tv = _toggle.velocity;
                  const rise = _barHeight + _gap;

                  // The centre's velocity (px/s) -> stretch along the motion.
                  final stretch = _f.directionalSquash
                      ? directionalStretch(Offset(
                          tv * (fullWidth - _fab) / 2,
                          tv * rise * _arcSlope(t),
                        ))
                      : Matrix4.identity();

                  return Positioned(
                    right: _pad,
                    height: _barHeight,
                    bottom: _toggleBottom(bottomInset) - _morph.lean.value,
                    width: _toggleWidth(fullWidth, box.maxWidth),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: stretch,
                      child: child,
                    ),
                  );
                },
              );

          return GooeyStage(
            scene: _scene,
            children: [
              RepaintBoundary(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) =>
                      !_freezeMorph &&
                      _morph.handleScrollNotification(
                        n,
                        behavior: _collapseOnly
                            ? ScrollMorphBehavior.collapseOnly
                            : ScrollMorphBehavior.standard,
                      ),
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    itemExtent: 76,
                    padding: const EdgeInsets.fromLTRB(8, 60, 8, 200),
                    itemCount: 40,
                    itemBuilder: (_, i) => ListTile(
                      leading: Container(
                        width: 56,
                        height: 56,
                        color: cs.surfaceContainerHighest,
                      ),
                      title: Text('Event ${i + 1}'),
                      subtitle: const Text('10:00 – 18:00 · Hall C'),
                      trailing: const Icon(Icons.favorite_border),
                    ),
                  ),
                ),
              ),

              if (Navigator.of(context).canPop())
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 4,
                  left: 4,
                  child: const BackButton(),
                ),

              // Measurements and effect toggles – for debugging on the phone.
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: _pad,
                child: MotionDebugPanel(
                  stats: _stats,
                  motion: _chosen,
                  onMotionChanged: _setMotion,
                  useShader: _useShader,
                  shaderReady: GooeyShader.isReady,
                  onShaderChanged: _setShader,
                  status: ListenableBuilder(
                    listenable: _quality,
                    builder: (context, _) {
                      final off = _quality.droppedFeatures;
                      final text = !_quality.enabled
                          ? 'Automatic quality: off'
                          : off.isEmpty
                              ? 'Quality: full'
                              : 'Switched off automatically: ${off.join(', ')}'
                                  '${_quality.lowPower ? ' (Low Power Mode)' : ''}';
                      return Text(
                        text,
                        style: Theme.of(context).textTheme.labelMedium,
                      );
                    },
                  ),
                  diagnostics: [
                    (
                      'Automatic quality',
                      _quality.enabled,
                      (v) => setState(() => _quality.enabled = v),
                    ),
                    (
                      'Simulate slow phone',
                      _quality.budgetMs == _slowPhoneBudget,
                      (v) => setState(
                            () => _quality.budgetMs = v ? _slowPhoneBudget : 16,
                          ),
                    ),
                    (
                      'Hide the bottom bar (list only)',
                      _hideBar,
                      (v) => setState(() => _hideBar = v),
                    ),
                    (
                      'Do not fold (bar stays still)',
                      _freezeMorph,
                      (v) {
                        setState(() => _freezeMorph = v);
                        if (v) _morph.animateTo(0);
                      },
                    ),
                    (
                      'Fold on any scroll, unfold on tap',
                      _collapseOnly,
                      (v) => setState(() => _collapseOnly = v),
                    ),
                    (
                      'Hide icons and text in the bars',
                      _hideContent,
                      (v) => setState(() => _hideContent = v),
                    ),
                    (
                      'Edge light along the merged shape',
                      _edgeLight,
                      (v) => _setLight(edge: v),
                    ),
                    (
                      'Shadow under the merged shape',
                      _shadow,
                      (v) => _setLight(shadow: v),
                    ),
                  ],
                ),
              ),

              // The neck between the shapes. Lies UNDER both shapes.
              if (!_hideBar) ...[
                if (_f.gooey || _lit) GooeyBackdrop(scene: _scene),

                // The layers, bottom up: backgrounds first, then content – so
                // the lower shape's icons can be seen through the upper shape.
                navLayer(surface(0, cs.surfaceContainerHigh)),
                bubbleLayer(
                  PressScale(
                    spring: _bubblePress,
                    listen: false,
                    child: surface(1, cs.primaryContainer),
                  ),
                ),
                if (!_hideContent) navLayer(navContent),
                if (!_hideContent)
                  bubbleLayer(
                    PressScale(
                      spring: _bubblePress,
                      enabled: _f.pressFeedback,
                      child: toggleContent(fullWidth, box.maxWidth),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
