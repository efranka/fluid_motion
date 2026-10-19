import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/springs.dart';
import '../quality/motion_quality.dart';
import 'contact.dart';
import 'field.dart';
import 'geometry.dart';
import 'neck.dart';
import 'shader.dart';
import 'shape.dart';

/// Which gooey effects a [GooeyScene] uses and how they behave. Each effect
/// can be switched on and off on its own.
@immutable
class GooeyStyle {
  const GooeyStyle({
    this.neck = true,
    this.colorBlend = true,
    this.blob = true,
    this.contentBlend = true,
    this.useShader = true,
    this.neckStyle = const GooeyNeckStyle(),
    this.blendWidth = 60,
    this.blobSize = 14,
    this.blobRadius = 22,
    this.releaseStretch = 0.25,
    this.catchKick = 6,
    this.releaseKick = 9,
    this.hysteresis = 0.75,
    this.contentReach = 14,
    this.contentDepth = 22,
    this.maxBlobsPerShape = 3,
    this.blendNeighbours = GooeyShader.maxNeighbours,
  }) : assert(
          blendNeighbours >= 0 && blendNeighbours <= GooeyShader.maxNeighbours,
          'blendNeighbours must be between 0 and GooeyShader.maxNeighbours',
        );

  /// No effects – e.g. for "Reduce motion".
  static const off = GooeyStyle(
    neck: false,
    colorBlend: false,
    blob: false,
    contentBlend: false,
  );

  /// A fluid neck between the shapes.
  final bool neck;

  /// The colours blend while the shapes are connected.
  final bool colorBlend;

  /// The shapes "blob" when they catch and release each other.
  final bool blob;

  /// Content is pulled into and dissolves in the other shape
  /// ([GooeyContent]).
  final bool contentBlend;

  /// Use the GPU shader for the neck when it is loaded (rounded rects only;
  /// other outlines always use the CPU version).
  final bool useShader;

  final GooeyNeckStyle neckStyle;

  /// The colour blend's width at full contact (px).
  final double blendWidth;

  /// Blob: max bulge (px per spring unit) and width (px).
  final double blobSize, blobRadius;

  /// How stretched the shapes are at the moment they let go.
  final double releaseStretch;

  /// How hard the blob kicks on catch and release.
  final double catchKick, releaseKick;

  /// Hysteresis (px) around the contact threshold.
  final double hysteresis;

  /// Content is affected from this far OUTSIDE the other shape (px) …
  final double contentReach;

  /// … and fully dissolved this deep INSIDE it (px).
  final double contentDepth;

  final int maxBlobsPerShape;

  /// How many neighbours each shape's colour blends towards at once (0 to
  /// [GooeyShader.maxNeighbours]). With 1, a shape touching two others only
  /// blends towards the most connected one, and you can see an edge towards
  /// the other; with 0 the shapes keep their own colours (the neck still
  /// blends). [MotionQuality] lowers it to 1 before it switches colour
  /// blending off entirely ([MotionFeature.multiBlend]).
  final int blendNeighbours;

  double get meetAt => neckStyle.meetAt;

  // Loose springs, so the blob wobbles a couple of times.
  SpringDescription get catchSpring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.28);
  SpringDescription get releaseSpring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.32);

  GooeyStyle copyWith({
    bool? neck,
    bool? colorBlend,
    bool? blob,
    bool? contentBlend,
    bool? useShader,
    GooeyNeckStyle? neckStyle,
    double? blendWidth,
    int? blendNeighbours,
  }) =>
      GooeyStyle(
        neck: neck ?? this.neck,
        colorBlend: colorBlend ?? this.colorBlend,
        blob: blob ?? this.blob,
        contentBlend: contentBlend ?? this.contentBlend,
        useShader: useShader ?? this.useShader,
        neckStyle: neckStyle ?? this.neckStyle,
        blendWidth: blendWidth ?? this.blendWidth,
        blobSize: blobSize,
        blobRadius: blobRadius,
        releaseStretch: releaseStretch,
        catchKick: catchKick,
        releaseKick: releaseKick,
        hysteresis: hysteresis,
        contentReach: contentReach,
        contentDepth: contentDepth,
        maxBlobsPerShape: maxBlobsPerShape,
        blendNeighbours: blendNeighbours ?? this.blendNeighbours,
      );
}

/// One shape in a [GooeyScene].
class GooeyMember {
  const GooeyMember({
    required this.rect,
    required this.color,
    this.radius,
    this.geometry,
  });

  /// The shape's bounding rect in scene coordinates in the current frame –
  /// or null if it is not ready yet (e.g. before the first layout).
  final Rect? Function() rect;

  final Color color;

  /// Corner radius for the default rounded rect (null = pill). Ignored when
  /// [geometry] is given.
  final double? radius;

  /// The outline: [GooeyCircle], [GooeyRing], [GooeyStar], [GooeyPolygon],
  /// [GooeyPathGeometry] or your own. Default: a rounded rect.
  final GooeyGeometry? geometry;
}

class _Blob {
  _Blob(this.member, this.corner, this.offset, this.controller);
  final int member;
  final Alignment corner;
  final Offset offset;
  final AnimationController controller;
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Everything that makes a set of shapes behave like fluid material: the
/// neck between them, colour blending, blobs on catch and release, and
/// content pulled into another shape.
///
/// The scene knows nothing about what the shapes are (a bottom bar, a card,
/// a button) – only their rects, outlines and colours ([GooeyMember]). Put
/// the widgets in a [GooeyStage] and paint with [GooeyBackdrop],
/// [GooeySurface] and [GooeyContent].
///
/// Everything is computed once per frame and shared by all painters.
class GooeyScene {
  GooeyScene({
    required TickerProvider vsync,
    required Listenable motion,
    List<GooeyMember> members = const [],
    GooeyStyle style = const GooeyStyle(),
    MotionQuality? quality,
  })  : _vsync = vsync,
        _motion = motion,
        _members = members,
        _base = style,
        _style = style,
        _quality = quality {
    repaint = Listenable.merge([motion, _ping]);
    motion.addListener(_onMotion);
    // Repaint when e.g. a path's distance field reaches the GPU.
    GooeyShader.updates.addListener(_ping.ping);
    quality?.addListener(_onQuality);
    _style = _limited(style);
    _styleNotifier = ValueNotifier(_style);
  }

  final TickerProvider _vsync;
  final Listenable _motion;
  final _ping = _Ping();

  /// Everything that changes how the scene looks – use it as the repaint
  /// listenable for painters.
  late final Listenable repaint;

  /// Used by [GooeyStage] to know the scene's coordinate system.
  final GlobalKey stageKey = GlobalKey();

  List<GooeyMember> _members;
  List<GooeyMember> get members => _members;
  set members(List<GooeyMember> value) {
    _members = value;
    _trackers.clear();
    _invalidate();
  }

  // The requested style and the one actually used (limited by [quality]).
  GooeyStyle _base;
  GooeyStyle _style;
  late final ValueNotifier<GooeyStyle> _styleNotifier;

  /// The style in use right now – the requested style minus the effects
  /// [quality] has switched off.
  GooeyStyle get style => _style;

  /// The requested style.
  GooeyStyle get baseStyle => _base;
  set style(GooeyStyle value) {
    _base = value;
    _applyStyle();
  }

  /// Changes when [style] does (e.g. when quality switches an effect off).
  ValueListenable<GooeyStyle> get styleListenable => _styleNotifier;

  MotionQuality? _quality;

  /// Automatic quality (optional). Effects it does not allow are switched
  /// off.
  MotionQuality? get quality => _quality;
  set quality(MotionQuality? value) {
    if (identical(value, _quality)) return;
    _quality?.removeListener(_onQuality);
    _quality = value;
    value?.addListener(_onQuality);
    _applyStyle();
  }

  void _onQuality() => _applyStyle();

  GooeyStyle _limited(GooeyStyle s) {
    final q = _quality;
    if (q == null) return s;
    return s.copyWith(
      neck: s.neck && q.allows(MotionFeature.neck),
      colorBlend: s.colorBlend && q.allows(MotionFeature.colorBlend),
      blob: s.blob && q.allows(MotionFeature.blob),
      contentBlend: s.contentBlend && q.allows(MotionFeature.contentBlend),
      blendNeighbours: q.allows(MotionFeature.multiBlend)
          ? s.blendNeighbours
          : (s.blendNeighbours < 1 ? s.blendNeighbours : 1),
    );
  }

  void _applyStyle() {
    _style = _limited(_base);
    if (!_style.blob) _clearBlobs();
    _styleNotifier.value = _style;
    _invalidate();
  }

  // -------------------------------------------------------------------------
  // Shapes and cache
  // -------------------------------------------------------------------------

  List<GooeyShape>? _shapes;
  GooeyColorField? _field;
  Duration? _cacheFrame;
  int _generation = 0, _cacheGeneration = -1;

  void _invalidate() {
    _generation++;
    _ping.ping();
  }

  // Only during build/layout/paint are the values stable for the whole
  // frame; during the ticker phase a later controller may still change.
  bool get _cacheable {
    final phase = SchedulerBinding.instance.schedulerPhase;
    return phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.postFrameCallbacks;
  }

  bool get _cacheValid =>
      _cacheGeneration == _generation &&
      _cacheFrame == SchedulerBinding.instance.currentSystemFrameTimeStamp;

  List<Rect>? _rects() {
    final rects = <Rect>[];
    for (final m in _members) {
      final r = m.rect();
      if (r == null || r.isEmpty) return null;
      rects.add(r);
    }
    return rects;
  }

  GooeyShape _shapeFor(int i, Rect rect,
          {List<GooeyRipple> ripples = const []}) =>
      GooeyShape(
        rect,
        _members[i].color,
        radius: _members[i].radius,
        geometry: _members[i].geometry,
        ripples: ripples,
      );

  List<GooeyShape>? _buildShapes() {
    final rects = _rects();
    if (rects == null) return null;
    return [
      for (var i = 0; i < rects.length; i++)
        _shapeFor(i, rects[i], ripples: _ripplesFor(i, rects[i])),
    ];
  }

  /// The shapes in the current frame (null if they are not ready).
  List<GooeyShape>? get shapes {
    if (_cacheable && _cacheValid) return _shapes;
    final shapes = _buildShapes();
    if (_cacheable) {
      _shapes = shapes;
      _field = null;
      _cacheFrame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      _cacheGeneration = _generation;
    }
    return shapes;
  }

  /// The shared colour field (null if colour blending is off).
  GooeyColorField? get field {
    if (!_style.colorBlend) return null;
    final s = shapes;
    if (s == null || s.length < 2) return null;
    if (_cacheable && _cacheValid && _field != null) return _field;
    final f = GooeyColorField(
      s,
      meetAt: _style.meetAt,
      maxWidth: _style.blendWidth,
      neighbours: math.max(1, _style.blendNeighbours),
    );
    if (_cacheable && _cacheValid) _field = f;
    return f;
  }

  // -------------------------------------------------------------------------
  // Contact and blobs
  // -------------------------------------------------------------------------

  final Map<int, ContactTracker> _trackers = {};
  final List<_Blob> _blobs = [];

  void _onMotion() {
    if (!_style.blob) return;
    final rects = _rects();
    if (rects == null) return;
    // Plain shapes (no ripples) – enough to measure the gaps.
    final plain = [
      for (var i = 0; i < rects.length; i++) _shapeFor(i, rects[i]),
    ];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final tracker = _trackers.putIfAbsent(
          i * 1000 + j,
          () => ContactTracker(
            meetAt: _style.meetAt,
            hysteresis: _style.hysteresis,
          ),
        );
        final (gap, p) = GooeyContact.measure(plain[i], plain[j]);
        final event = tracker.update(gap);
        if (event == ContactEvent.none) continue;
        final force = (tracker.speed / 300).clamp(0.35, 1.6);
        for (final m in [i, j]) {
          final c = _addBlob(m, rects[m], p);
          if (event == ContactEvent.caught) {
            // Catch: the shapes bulge towards each other and wobble to rest.
            c.kick(_style.catchKick * force, _style.catchSpring);
          } else {
            // Release: the string snaps – the shapes are still stretched a
            // little and spring back with a recoil that wobbles to rest.
            c.value = _style.releaseStretch;
            c.kick(-_style.releaseKick * force, _style.releaseSpring);
          }
        }
      }
    }
  }

  AnimationController _addBlob(int member, Rect rect, Offset p) {
    // Anchored to the shape's nearest corner, so the blob follows when the
    // shape moves and changes width.
    final corner = Alignment(
      p.dx > rect.center.dx ? 1 : -1,
      p.dy > rect.center.dy ? 1 : -1,
    );
    final controller = AnimationController.unbounded(vsync: _vsync);
    final blob = _Blob(member, corner, p - corner.withinRect(rect), controller);
    controller.addListener(_ping.ping);
    controller.addStatusListener((status) {
      // Removed after the notification (not in the middle of it).
      if (status == AnimationStatus.completed) {
        scheduleMicrotask(() => _removeBlob(blob));
      }
    });
    final mine = _blobs.where((b) => b.member == member).toList();
    if (mine.length >= _style.maxBlobsPerShape) _removeBlob(mine.first);
    _blobs.add(blob);
    return controller;
  }

  void _removeBlob(_Blob blob) {
    if (!_blobs.remove(blob)) return;
    blob.controller.dispose();
    _invalidate();
  }

  void _clearBlobs() {
    for (final b in _blobs) {
      b.controller.dispose();
    }
    _blobs.clear();
  }

  List<GooeyRipple> _ripplesFor(int member, Rect rect) {
    if (!_style.blob) return const [];
    final result = <GooeyRipple>[];
    for (final b in _blobs) {
      if (b.member != member) continue;
      final amp = b.controller.value * _style.blobSize;
      if (amp.abs() < 0.05) continue;
      result.add(GooeyRipple(
        b.corner.withinRect(rect) + b.offset,
        amp,
        radius: _style.blobRadius,
      ));
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Content affected by other shapes
  // -------------------------------------------------------------------------

  Matrix4? _toStage;
  Duration? _toStageFrame;

  Offset? _globalToStage(Offset global) {
    final box = stageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (_toStage == null || _toStageFrame != frame) {
      _toStage = box.getTransformTo(null)..invert();
      _toStageFrame = frame;
    }
    return MatrixUtils.transformPoint(_toStage!, global);
  }

  /// How strongly content in shape [member] centred at [global] is affected
  /// by the nearest OTHER shape: 0 far from it, up to 1 deep inside it – only
  /// while the shapes are connected. The direction points towards the other
  /// shape.
  (double, Offset) influenceOn(int member, Offset global) {
    if (!_style.contentBlend) return (0, Offset.zero);
    final s = shapes;
    if (s == null || s.length < 2 || member >= s.length) {
      return (0, Offset.zero);
    }
    final p = _globalToStage(global);
    if (p == null) return (0, Offset.zero);

    final own = s[member];
    GooeyShape? other;
    var best = double.infinity;
    for (var j = 0; j < s.length; j++) {
      if (j == member) continue;
      final d = s[j].distance(p.dx, p.dy);
      if (d < best) {
        best = d;
        other = s[j];
      }
    }
    if (other == null) return (0, Offset.zero);
    final strength =
        GooeyContact.betweenShapes(own, other, meetAt: _style.meetAt).strength;
    if (strength <= 0) return (0, Offset.zero);

    var t = ((_style.contentReach - best) /
            (_style.contentReach + _style.contentDepth))
        .clamp(0.0, 1.0);
    t = t * t * (3 - 2 * t) * strength;
    // Pull towards the other shape. If both are centred on the same point,
    // pull from the content towards the other shape's nearest edge instead.
    var axis = other.rect.center - own.rect.center;
    if (axis.distance < 1) axis = other.closestOnEdge(p) - p;
    final len = axis.distance;
    return (t, len > 1e-6 ? axis / len : Offset.zero);
  }

  /// The neck between shape [i] and [j] in the current frame (or null).
  GooeyNeckGeometry? neckBetween(int i, int j) {
    final s = shapes;
    if (s == null || i >= s.length || j >= s.length) return null;
    return GooeyNeckGeometry.between(
      s[i],
      s[j],
      _style.neckStyle,
      margin: math.max(_style.neckStyle.cell, 2),
    );
  }

  void dispose() {
    GooeyShader.updates.removeListener(_ping.ping);
    _quality?.removeListener(_onQuality);
    _styleNotifier.dispose();
    _motion.removeListener(_onMotion);
    _clearBlobs();
    _ping.dispose();
  }
}
