import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Measures how smoothly the app runs while something moves.
///
/// Two kinds of numbers:
///  • fps and jank: the time between frames (what the eye sees). Affected by
///    how you scroll, so the numbers vary. Only counted while something
///    animates: the pause before a frame that follows an idle moment is not
///    a stutter, just nothing to draw.
///  • build and raster: how many ms each frame actually costs to build
///    (Dart: layout and painting) and to rasterise (renderer). Independent of
///    scrolling style, so these are the ones to compare. At 60 Hz build +
///    raster should stay below about 16 ms.
///
/// Does not schedule frames itself, so measuring does not affect the app
/// while nothing moves.
class FrameStats extends ChangeNotifier {
  FrameStats() {
    SchedulerBinding.instance
      ..addPersistentFrameCallback(_onFrame)
      ..addTimingsCallback(_onTimings);
  }

  bool _active = true;
  Duration? _last;

  /// Whether the previous frame asked for the next one (something animates).
  /// Only then is the time between the two a stutter if it is long.
  bool _continuous = false;
  Timer? _notify;

  // Time between frames.
  int frames = 0;
  int slow = 0;
  double worst = 0;
  double _sum = 0;

  /// The single most expensive frame (build + raster, ms) – catches a
  /// one-off hitch, e.g. the first time something is drawn.
  double heaviest = 0;

  /// How [heaviest] splits: build (Dart – e.g. code running for the first
  /// time) and raster (renderer – e.g. a GPU program being prepared).
  double heaviestBuild = 0, heaviestRaster = 0;

  // Work per frame (ms).
  final List<double> _build = [];
  final List<double> _raster = [];
  static const _keep = 600;

  double get fps => frames == 0 ? 0 : 1000 / (_sum / frames);
  double get slowShare => frames == 0 ? 0 : slow / frames;

  bool get hasTimings => _build.isNotEmpty;
  double get buildAvg => _avg(_build);
  double get rasterAvg => _avg(_raster);

  /// The 90th percentile of build + raster: 9 out of 10 frames are faster.
  double get totalP90 {
    if (_build.isEmpty) return 0;
    final totals = [
      for (var i = 0; i < _build.length; i++) _build[i] + _raster[i],
    ]..sort();
    return totals[((totals.length - 1) * 0.9).round()];
  }

  /// The share of frames where build + raster takes over 16 ms.
  double get overBudgetShare {
    if (_build.isEmpty) return 0;
    var n = 0;
    for (var i = 0; i < _build.length; i++) {
      if (_build[i] + _raster[i] > 16) n++;
    }
    return n / _build.length;
  }

  static double _avg(List<double> l) =>
      l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;

  void _onFrame(Duration timeStamp) {
    if (!_active) return;
    final last = _last;
    final continuous = _continuous;
    _last = timeStamp;
    _continuous = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _continuous = SchedulerBinding.instance.hasScheduledFrame;
    });
    if (last == null || !continuous) return;
    final ms = (timeStamp - last).inMicroseconds / 1000;
    if (ms <= 0 || ms > 1000) return;
    frames++;
    _sum += ms;
    if (ms > 20) slow++;
    if (ms > worst) worst = ms;
    _scheduleNotify();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_active) return;
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000;
      final raster = t.rasterDuration.inMicroseconds / 1000;
      _build.add(build);
      _raster.add(raster);
      if (build + raster > heaviest) {
        heaviest = build + raster;
        heaviestBuild = build;
        heaviestRaster = raster;
      }
    }
    if (_build.length > _keep) {
      _build.removeRange(0, _build.length - _keep);
      _raster.removeRange(0, _raster.length - _keep);
    }
    _scheduleNotify();
  }

  // At most two display updates per second.
  void _scheduleNotify() {
    _notify ??= Timer(const Duration(milliseconds: 500), () {
      _notify = null;
      if (_active) notifyListeners();
    });
  }

  void reset() {
    frames = 0;
    slow = 0;
    worst = 0;
    heaviest = 0;
    heaviestBuild = 0;
    heaviestRaster = 0;
    _sum = 0;
    _last = null;
    _continuous = false;
    _build.clear();
    _raster.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    // Persistent frame callbacks cannot be removed – they are muted instead.
    _active = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _notify?.cancel();
    super.dispose();
  }
}
