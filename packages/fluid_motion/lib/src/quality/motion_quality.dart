import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// An effect that [MotionQuality] can switch off when the device cannot keep
/// up. Features compare by [name], so you can define your own:
///
/// ```dart
/// const glow = MotionFeature('glow', label: 'Glow');
/// final quality = MotionQuality(dropOrder: [glow, ...MotionQuality.defaultDropOrder]);
/// if (quality.allows(glow)) { ... }
/// ```
@immutable
class MotionFeature {
  const MotionFeature(this.name, {this.label});

  final String name;

  /// A readable name (e.g. for a settings panel).
  final String? label;

  /// Content that blurs and dissolves into another shape ([GooeyContent]).
  static const contentBlend =
      MotionFeature('contentBlend', label: 'Content blend');

  /// Colours blending between shapes.
  static const colorBlend = MotionFeature('colorBlend', label: 'Colour blend');

  /// Shapes that "blob" when they catch and release each other.
  static const blob = MotionFeature('blob', label: 'Blob');

  /// The fluid neck between shapes.
  static const neck = MotionFeature('neck', label: 'Gooey neck');

  @override
  bool operator ==(Object other) =>
      other is MotionFeature && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => label ?? name;
}

/// Automatic quality: continuously measures how long each frame takes while
/// something moves, and switches the most expensive effects off one at a
/// time if the device cannot keep up – and back on when there is headroom.
///
/// Catches every cause at once: an old phone, low battery, a hot phone,
/// heavy background apps and Low Power Mode (which locks Safari to 30 frames
/// per second).
///
///  • Springs, bounce, arcs and stretch cost almost nothing and are never
///    affected.
///  • Changes only happen while nothing moves, so an effect never vanishes
///    in the middle of an animation.
///  • Switch it all off with [enabled] = false; then everything is allowed.
///
/// Ask [allows] whether an effect may be used. [GooeyScene] does it by
/// itself when given a [MotionQuality].
class MotionQuality extends ChangeNotifier {
  MotionQuality({
    bool enabled = true,
    this.dropOrder = defaultDropOrder,
    this.budgetMs = 16,
    this.overBudgetShare = 0.25,
    this.upgradeHeadroom = 0.5,
    this.downgradeAfter = const Duration(milliseconds: 1500),
    this.upgradeAfter = const Duration(seconds: 6),
    this.idleDelay = const Duration(milliseconds: 300),
    this.respectLowPower = true,
    bool measure = true,
  })  : _enabled = enabled,
        _measure = measure {
    if (measure) {
      SchedulerBinding.instance
        ..addTimingsCallback(_onTimings)
        ..addPersistentFrameCallback(_onFrame);
    }
  }

  /// The order effects are switched off in: the most expensive and least
  /// important first.
  static const defaultDropOrder = [
    MotionFeature.contentBlend,
    MotionFeature.colorBlend,
    MotionFeature.blob,
    MotionFeature.neck,
  ];

  /// The effects that can be switched off, in order.
  final List<MotionFeature> dropOrder;

  /// How many ms a frame may take (build + raster). 16 ms = 60 Hz.
  double budgetMs;

  /// Switch an effect off when more than this share of frames is over
  /// budget.
  double overBudgetShare;

  /// Switch an effect back on when 9 out of 10 frames use less than this
  /// share of the budget (hysteresis, so quality does not flicker).
  double upgradeHeadroom;

  /// How long to measure (while moving) before switching something off …
  final Duration downgradeAfter;

  /// … and how long there must be headroom before switching it back on.
  final Duration upgradeAfter;

  /// How long nothing must have moved before a change takes effect.
  final Duration idleDelay;

  /// Switch all effects off in Low Power Mode (saves battery, and at 30
  /// frames per second the effects look choppy anyway).
  bool respectLowPower;

  final bool _measure;
  bool _active = true;

  bool _enabled;

  /// Automatic quality on/off. Off = every effect is always allowed.
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _reset();
    notifyListeners();
  }

  int _dropped = 0;
  bool _lowPower = false;

  /// Whether the device seems to be in Low Power Mode.
  bool get lowPower => _lowPower;

  /// How many effects are switched off right now.
  int get dropped {
    if (!_enabled) return 0;
    if (respectLowPower && _lowPower) return dropOrder.length;
    return _dropped;
  }

  /// The effects switched off right now.
  List<MotionFeature> get droppedFeatures => dropOrder.sublist(0, dropped);

  /// Whether [feature] may be used right now. Features not in [dropOrder]
  /// are always allowed.
  bool allows(MotionFeature feature) {
    final i = dropOrder.indexOf(feature);
    return i < 0 || i >= dropped;
  }

  // -------------------------------------------------------------------------
  // Measuring
  // -------------------------------------------------------------------------

  final List<double> _work = [];
  final List<double> _intervals = [];
  int _comfortFrames = 0;
  int? _pendingDropped;
  bool? _pendingLowPower;
  Timer? _idle;
  Duration? _lastFrame;

  static const _frameMs = 1000 / 60;
  int get _windowFrames => (downgradeAfter.inMilliseconds / _frameMs).round();
  int get _upgradeFrames => (upgradeAfter.inMilliseconds / _frameMs).round();

  void _onTimings(List<FrameTiming> timings) {
    if (!_active) return;
    for (final t in timings) {
      recordWork((t.buildDuration + t.rasterDuration).inMicroseconds / 1000);
    }
  }

  void _onFrame(Duration timeStamp) {
    if (!_active) return;
    final last = _lastFrame;
    _lastFrame = timeStamp;
    if (last != null) {
      recordInterval((timeStamp - last).inMicroseconds / 1000);
    }
  }

  /// Record how many ms a frame took to build and raster. Called
  /// automatically; public so it can be tested and fed from other sources.
  void recordWork(double ms) {
    if (!_enabled) return;
    _work.add(ms);
    if (_work.length >= _windowFrames) _evaluateWork();
    _armIdle();
  }

  /// Record the time between two frames (ms). Used to recognise Low Power
  /// Mode. Pauses (> 100 ms) are ignored.
  void recordInterval(double ms) {
    if (!_enabled || ms <= 0 || ms > 100) return;
    _intervals.add(ms);
    if (_intervals.length < 60) return;
    final sorted = [..._intervals]..sort();
    _intervals.clear();
    final median = sorted[sorted.length ~/ 2];
    // Locked to 30 Hz: frames arrive steadily about 33 ms apart.
    _pendingLowPower = median > 26 && median < 45;
    _armIdle();
  }

  void _evaluateWork() {
    final over = _work.where((w) => w > budgetMs).length / _work.length;
    final sorted = [..._work]..sort();
    final p90 = sorted[((sorted.length - 1) * 0.9).round()];
    _work.clear();

    final current = _pendingDropped ?? _dropped;
    if (over > overBudgetShare && current < dropOrder.length) {
      // Far over budget: take two steps at once.
      final steps = over > 0.6 ? 2 : 1;
      _pendingDropped = (current + steps).clamp(0, dropOrder.length);
      _comfortFrames = 0;
    } else if (p90 < budgetMs * upgradeHeadroom && current > 0) {
      _comfortFrames += _windowFrames;
      if (_comfortFrames >= _upgradeFrames) {
        _pendingDropped = current - 1;
        _comfortFrames = 0;
      }
    } else {
      _comfortFrames = 0;
    }
  }

  void _armIdle() {
    if (!_measure) return;
    _idle?.cancel();
    _idle = Timer(idleDelay, applyPending);
  }

  /// Apply pending changes. Called automatically when nothing has moved for
  /// [idleDelay].
  void applyPending() {
    if (!_active) return;
    var changed = false;
    final d = _pendingDropped;
    _pendingDropped = null;
    if (d != null && d != _dropped) {
      _dropped = d;
      changed = true;
    }
    final lp = _pendingLowPower;
    _pendingLowPower = null;
    if (lp != null && lp != _lowPower) {
      _lowPower = lp;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _reset() {
    _dropped = 0;
    _lowPower = false;
    _pendingDropped = null;
    _pendingLowPower = null;
    _comfortFrames = 0;
    _work.clear();
    _intervals.clear();
    _idle?.cancel();
  }

  @override
  void dispose() {
    // Persistent frame callbacks cannot be removed – they are muted instead.
    _active = false;
    _idle?.cancel();
    if (_measure) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}

/// Passes a [MotionQuality] down to everything below it, so components can
/// ask whether an effect may be used. Rebuilds dependent widgets when the
/// quality changes.
class MotionQualityScope extends InheritedNotifier<MotionQuality> {
  const MotionQualityScope({
    super.key,
    required MotionQuality quality,
    required super.child,
  }) : super(notifier: quality);

  static MotionQuality? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MotionQualityScope>()
      ?.notifier;
}
