import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../foundation/springs.dart';

/// An element that follows a [DragSpringController] with its own spring
/// (overlapping and secondary action): e.g. a navigation bar lagging a
/// little behind, or an icon landing slightly later.
class MorphFollower {
  MorphFollower({
    required this.controller,
    required this.spring,
    this.delay = Duration.zero,
    this.idleVelocityScale = 0.6,
    this.ratioOffset = 0,
  });

  /// The follower's value (same scale as the morph, typically 0..1).
  final AnimationController controller;

  /// The follower's spring. Typically softer than the primary one.
  EnergySpring spring;

  /// How long the follower waits before starting from rest. If it is
  /// already moving with the finger it starts at once (otherwise it would
  /// freeze mid-movement).
  Duration delay;

  /// How much of the velocity the follower gets when starting from rest.
  double idleVelocityScale;

  /// Extra damping relative to the primary movement (0.15 = a bit calmer).
  double ratioOffset;

  Timer? _timer;
}

/// What scrolling folds the element (towards 1) – see [ScrollMorphBehavior].
enum ScrollCollapse {
  /// Scrolling forward (content moves up, or left).
  forward,

  /// Any scrolling, in any direction – e.g. a timeline you scroll both ways,
  /// where the element should get out of the way as soon as you move.
  anyMovement,

  /// Scrolling never folds it (only [DragSpringController.animateTo]).
  never,
}

/// What scrolling unfolds the element (towards 0) – see
/// [ScrollMorphBehavior].
enum ScrollExpand {
  /// Scrolling back (towards the start).
  backward,

  /// Only reaching the very start of the content.
  atStart,

  /// Scrolling never unfolds it – only a tap or another action that calls
  /// [DragSpringController.animateTo] with 0.
  never,
}

/// Which scrolls drive a [DragSpringController], and how: pass it to
/// [DragSpringController.handleScrollNotification].
///
/// ```dart
/// // A page of timelines scrolled both ways: any scroll folds the bar, and
/// // only a tap on it unfolds it again.
/// controller.handleScrollNotification(n, behavior: ScrollMorphBehavior.collapseOnly);
/// ```
@immutable
class ScrollMorphBehavior {
  const ScrollMorphBehavior({
    this.collapse = ScrollCollapse.forward,
    this.expand = ScrollExpand.backward,
    this.axes = const {Axis.vertical},
    this.nested = false,
  });

  /// Scroll down folds, scroll up unfolds – the main vertical list only, so
  /// a horizontal carousel inside it does not move the element.
  static const standard = ScrollMorphBehavior();

  /// Any scroll, in any direction and in nested scrollables, folds; scrolling
  /// never unfolds. Unfold with a tap ([DragSpringController.animateTo]).
  static const collapseOnly = ScrollMorphBehavior(
    collapse: ScrollCollapse.anyMovement,
    expand: ScrollExpand.never,
    axes: {Axis.vertical, Axis.horizontal},
    nested: true,
  );

  /// What folds the element.
  final ScrollCollapse collapse;

  /// What unfolds it. With [ScrollCollapse.anyMovement] every scroll folds,
  /// so only [ScrollExpand.atStart] or [ScrollExpand.never] make sense.
  final ScrollExpand expand;

  /// The scroll directions that count.
  final Set<Axis> axes;

  /// Whether scrollables inside the listened one (a carousel in a list)
  /// count too. Off: only the outermost one below the listener.
  final bool nested;

  /// Whether [n] should drive the element at all.
  bool accepts(ScrollNotification n) =>
      (nested || n.depth == 0) && axes.contains(n.metrics.axis);

  @override
  bool operator ==(Object other) =>
      other is ScrollMorphBehavior &&
      other.collapse == collapse &&
      other.expand == expand &&
      other.nested == nested &&
      other.axes.length == axes.length &&
      other.axes.containsAll(axes);

  @override
  int get hashCode =>
      Object.hash(collapse, expand, nested, Object.hashAllUnordered(axes));
}

/// "The finger drives, the spring takes over" – the reusable core behind
/// elements that switch between two states with a drag or a scroll: a
/// bottom bar that folds up, a bottom sheet, a swipe card.
///
/// [value] goes from 0 to 1 (and a little past when the spring overshoots).
///
///  • While the finger drags, the value follows the finger directly.
///  • When the finger lets go – or when the value reaches its final shape
///    mid-drag – a spring takes over with EXACTLY the finger's velocity.
///  • Bounce is graded by speed ([EnergySpring]): slow = soft landing,
///    fast = clear bounce.
///  • An animation in the same direction is allowed to finish; if the
///    finger reverses, it takes over at once.
///  • Optional rubber band: if the finger keeps going after landing, [lean]
///    follows a few pixels (use it for elements you drag directly).
///  • When a spring has come to rest, the value is set exactly on target.
///
/// Drive it with [handleScrollNotification] (scroll-driven elements) or
/// [dragStart]/[dragUpdate]/[dragEnd] (direct drags).
class DragSpringController {
  DragSpringController({
    required TickerProvider vsync,
    this.distance = 120,
    this.spring = const EnergySpring(stiffness: 420),
    this.velocityBounce = true,
    this.rubberBand = false,
    this.leanMax = 7,
    this.wheelThreshold = 150,
    this.reduceMotion = false,
    double initial = 0,
  })  : value = AnimationController.unbounded(vsync: vsync, value: initial),
        lean = AnimationController.unbounded(vsync: vsync),
        _target = initial,
        _prev = initial {
    value.addListener(_onTick);
    value.addStatusListener(_snapWhenSettled(value));
  }

  /// The main value: 0 = first state, 1 = second state.
  final AnimationController value;

  /// Rubber band: how far the element leans with the finger (px).
  final AnimationController lean;

  /// Pixels of drag/scroll that make up the whole transition.
  double distance;

  /// The primary movement's spring.
  EnergySpring spring;

  /// Bounce graded by speed (false = always a soft landing).
  bool velocityBounce;

  /// Elastic lean after landing. Off for scroll-driven elements.
  bool rubberBand;

  /// Max lean (px).
  double leanMax;

  /// Scroll speed (px/s) without a finger (mouse/trackpad) that triggers a
  /// switch.
  double wheelThreshold;

  /// "Reduce motion": no velocity is carried over, so nothing bounces.
  bool reduceMotion;

  /// Called once when the value overshoots its target during an animation
  /// (follow through) – with the target and the velocity (units/s). Use it to
  /// transfer energy to another element (e.g. an impact).
  void Function(double target, double velocity)? onOvershoot;

  final List<MorphFollower> _followers = [];

  /// Add a follower (see [MorphFollower]).
  void addFollower(MorphFollower follower) {
    _followers.add(follower);
    follower.controller.addStatusListener(
      _snapWhenSettled(follower.controller),
    );
  }

  double _target;

  /// The target the value is heading for (0 or 1).
  double get target => _target;

  bool get isDragging => _dragging;

  /// Whether the main value or a follower is still moving.
  bool get isAnimating =>
      value.isAnimating || _followers.any((f) => f.controller.isAnimating);

  // --- State ---
  bool _dragging = false;
  bool _landed = false;
  bool _rubbering = false;
  bool _driven = false;
  bool _kicked = false;
  bool _disposed = false;
  double _rubberPx = 0;
  double _dragStart = 0;
  double _prev;
  double _prevVelocity = 0;

  VelocityTracker? _tracker;
  final _clock = Stopwatch()..start();
  int _lastMs = 0;
  double _lastPixels = 0;
  double _scrollVelocity = 0;

  static final _leanSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 0.55);

  AnimationStatusListener _snapWhenSettled(AnimationController c) => (status) {
        if (status != AnimationStatus.completed) return;
        if (_dragging || _rubbering) return;
        if ((c.value - _target).abs() < 0.02) c.value = _target;
      };

  // -------------------------------------------------------------------------
  // Velocity
  // -------------------------------------------------------------------------

  void _trackPosition(double pixels) {
    final now = _clock.elapsedMilliseconds;
    final dt = (now - _lastMs).clamp(1, 100) / 1000;
    final v = (pixels - _lastPixels) / dt;
    _scrollVelocity = _scrollVelocity * 0.6 + v * 0.4;
    _lastMs = now;
    _lastPixels = pixels;
  }

  void _trackFinger(Duration? time, Offset position) {
    if (time == null) return;
    _tracker?.addPosition(time, position);
  }

  /// The axis of the scroll being followed, and whether every direction
  /// counts as "towards 1" ([ScrollCollapse.anyMovement]).
  Axis _axis = Axis.vertical;
  bool _anyDirection = false;

  /// The finger's velocity in the scroll direction (px/s, positive = to 1).
  double _fingerVelocity() {
    final estimate = _tracker?.getVelocityEstimate();
    if (estimate == null) return _scrollVelocity;
    final px = estimate.pixelsPerSecond;
    var finger = _axis == Axis.vertical ? -px.dy : -px.dx;
    if (_anyDirection) finger = finger.abs();
    // VelocityTracker assumes the finger has stopped if more than 40 ms pass
    // between two touches. When a frame drops, touches arrive exactly with
    // such gaps and the velocity is measured as 0 – and the bounce is lost.
    // So the scroll velocity (measured over real time) is used when it is
    // larger.
    return finger.abs() >= _scrollVelocity.abs() ? finger : _scrollVelocity;
  }

  // -------------------------------------------------------------------------
  // Scroll
  // -------------------------------------------------------------------------

  /// Drive the transition from a scroll: put it in a
  /// `NotificationListener<ScrollNotification>`. By default scrolling the
  /// main vertical list forward (content moves up) goes towards 1, and back
  /// towards 0; [behavior] decides which scrolls count and what they do (see
  /// [ScrollMorphBehavior]). Always returns false, so the notification keeps
  /// bubbling up the tree.
  bool handleScrollNotification(
    ScrollNotification n, {
    ScrollMorphBehavior behavior = ScrollMorphBehavior.standard,
  }) {
    if (!behavior.accepts(n)) return false;
    final any = behavior.collapse == ScrollCollapse.anyMovement;
    final atStart = n.metrics.pixels <= n.metrics.minScrollExtent;

    if (n is ScrollStartNotification && n.dragDetails != null) {
      _landed = false;
      _rubberPx = 0;
      _axis = n.metrics.axis;
      _anyDirection = any;
      _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
      _trackFinger(
          n.dragDetails!.sourceTimeStamp, n.dragDetails!.globalPosition);
    }

    if (n is ScrollUpdateNotification) {
      // Towards 1 is positive. With "any movement" every scroll is.
      final raw = n.scrollDelta ?? 0;
      final towards = any ? raw.abs() : raw;
      // Velocity from the scrolled distance (not the position, which differs
      // between the axes of a two-way scroll).
      _scrollPosition += towards;
      _trackPosition(_scrollPosition);
      // What this behaviour lets through.
      var delta = towards;
      if (delta > 0 && behavior.collapse == ScrollCollapse.never) delta = 0;
      if (delta < 0 && behavior.expand != ScrollExpand.backward) delta = 0;
      final drag = n.dragDetails;

      if (behavior.expand == ScrollExpand.atStart && atStart && raw < 0) {
        // Back at the very start: unfold.
        _dragging = false;
        animateTo(0, velocity: -_scrollVelocity.abs() / distance);
      } else if (drag != null) {
        _trackFinger(drag.sourceTimeStamp, drag.globalPosition);
        _dragDelta(delta);
      } else if (_rubbering) {
        _releaseRubber();
      } else if (_dragging) {
        _dragging = false;
        _release(_fingerVelocity());
      } else if (atStart) {
        if (behavior.expand != ScrollExpand.never) animateTo(0);
      } else if (_target != 1 &&
          behavior.collapse != ScrollCollapse.never &&
          _scrollVelocity > wheelThreshold &&
          n.metrics.pixels - n.metrics.minScrollExtent > 40) {
        // Mouse/trackpad, where there is no finger drag.
        animateTo(1, velocity: _scrollVelocity / distance);
      } else if (_target == 1 &&
          behavior.expand == ScrollExpand.backward &&
          _scrollVelocity < -wheelThreshold) {
        animateTo(0, velocity: _scrollVelocity / distance);
      }
    } else if (n is ScrollEndNotification) {
      if (_rubbering) {
        _releaseRubber();
      } else if (_dragging) {
        _dragging = false;
        var v = -(n.dragDetails?.primaryVelocity ?? 0);
        if (any) v = v.abs();
        _release(v);
      }
    }
    return false;
  }

  /// The scrolled distance towards 1, for measuring the scroll velocity.
  double _scrollPosition = 0;

  // -------------------------------------------------------------------------
  // Direct drags (sheets, cards)
  // -------------------------------------------------------------------------

  /// A new drag begins.
  void dragStart() {
    _landed = false;
    _rubberPx = 0;
    _tracker = null;
    _axis = Axis.vertical;
    _anyDirection = false;
    _scrollVelocity = 0;
    _lastMs = _clock.elapsedMilliseconds;
    _lastPixels = 0;
    _dragPixels = 0;
  }

  double _dragPixels = 0;

  /// The finger moved [delta] px (positive = towards 1).
  void dragUpdate(double delta) {
    _dragPixels += delta;
    _trackPosition(_dragPixels);
    _dragDelta(delta);
  }

  /// The finger lets go with [velocity] px/s (positive = towards 1).
  void dragEnd(double velocity) {
    if (_rubbering) {
      _releaseRubber();
    } else if (_dragging) {
      _dragging = false;
      _release(velocity);
    }
  }

  // -------------------------------------------------------------------------
  // Core
  // -------------------------------------------------------------------------

  void _dragDelta(double delta) {
    if (_landed) {
      final dir = _target == 1 ? 1.0 : -1.0;

      // Rubber band: if the finger keeps going the same way after landing,
      // the element leans with it – with increasing resistance. The shape is
      // kept; only the position gives way.
      if (rubberBand && (_rubbering || !isAnimating)) {
        _rubberPx += delta * dir;
        if (_rubberPx > 0) {
          _rubbering = true;
          lean.stop();
          lean.value = -dir * _rubberBandOffset(_rubberPx, leanMax);
          return;
        }
        _rubberPx = 0;
        if (_rubbering) {
          _rubbering = false;
          lean.value = 0;
        }
      }

      final reversing = (dir > 0 && delta < 0) || (dir < 0 && delta > 0);
      if (!reversing) return;
      _landed = false;
      _dragging = false;
    }

    if (!_dragging) {
      if (delta == 0) return;

      // An animation in the same direction is allowed to finish.
      final sameDirection =
          (_target == 1 && delta > 0) || (_target == 0 && delta < 0);
      if (isAnimating && sameDirection) {
        _landed = true;
        return;
      }

      _dragging = true;
      _dragStart = value.value;
      value.stop();
      for (final f in _followers) {
        f._timer?.cancel();
        f.controller.stop();
      }
    }

    final raw = value.value + delta / distance;
    final t = raw.clamp(0.0, 1.0);
    value.value = t;
    for (final f in _followers) {
      f.controller.value = t;
    }
    _driven = true;

    // When the value reaches its final shape, the spring takes over at once
    // with the finger's velocity -> landing bounce.
    final hitEdge = raw != t && (t - _dragStart).abs() > 0.001;
    if (hitEdge) {
      _dragging = false;
      _landed = true;
      animateTo(t, velocity: _fingerVelocity() / distance, force: true);
    }
  }

  void _release(double velocityPx) {
    final v = velocityPx / distance;
    final projected = value.value + v * 0.12;
    animateTo(projected > 0.5 ? 1 : 0, velocity: v);
  }

  void _releaseRubber() {
    _rubbering = false;
    _rubberPx = 0;
    lean.springTo(0, _leanSpring, velocity: lean.velocity);
  }

  /// Animate towards [target] (0 or 1) with start velocity [velocity]
  /// (units/s).
  void animateTo(double target, {double velocity = 0, bool force = false}) {
    if (_disposed) return;
    if (!force && target == _target && value.isAnimating) return;
    _target = target;

    final atRest = !isAnimating;
    if (!force &&
        atRest &&
        (value.value - target).abs() < 0.001 &&
        _followers.every((f) => (f.controller.value - target).abs() < 0.001)) {
      return;
    }
    _kicked = false;

    // Velocity pointing away from the target must not give a push.
    var raw = velocity;
    if ((target - value.value) * raw < 0) raw = 0;
    if (reduceMotion) raw = 0;

    final speed = velocityBounce ? raw.abs() * distance : 0.0;
    final v = raw.clamp(-8.0, 8.0);

    value.springTo(target, spring.forSpeed(speed), velocity: v);
    _prevVelocity = v;

    for (final f in _followers) {
      f._timer?.cancel();
      final s = f.spring.forSpeed(speed, ratioOffset: f.ratioOffset);
      if (_driven || f.delay == Duration.zero) {
        // Moving with the finger: continue at the same speed (no hitch).
        f.controller.springTo(
          target,
          s,
          velocity: _driven ? v : v * f.idleVelocityScale,
        );
      } else {
        f._timer = Timer(f.delay, () {
          if (_disposed) return;
          f.controller.springTo(target, s, velocity: v * f.idleVelocityScale);
        });
      }
    }
    _driven = false;
  }

  void _onTick() {
    final v = value.value;
    final callback = onOvershoot;
    if (callback != null && !_kicked && !_rubbering && value.isAnimating) {
      final crossedUp = _prev <= _target && v > _target;
      final crossedDown = _prev >= _target && v < _target;
      if (crossedUp || crossedDown) {
        _kicked = true;
        // At a low frame rate the spring can turn around within one frame, so
        // the current velocity points back. Then use the previous frame's
        // velocity, which still points in the overshoot direction.
        final now = value.velocity;
        callback(
          _target,
          crossedUp
              ? math.max(now, _prevVelocity)
              : math.min(now, _prevVelocity),
        );
      }
    }
    _prev = v;
    _prevVelocity = value.isAnimating ? value.velocity : 0;
  }

  void dispose() {
    _disposed = true;
    for (final f in _followers) {
      f._timer?.cancel();
    }
    value.removeListener(_onTick);
    value.dispose();
    lean.dispose();
  }
}

// Same as [rubberBand] – with a name not shadowed by the field
// [DragSpringController.rubberBand] inside the class.
double _rubberBandOffset(double overshoot, double dimension) =>
    rubberBand(overshoot, dimension);
