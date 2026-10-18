import 'package:flutter/animation.dart';

/// A linear ramp from 0 to 1 between two t values, clamped.
/// (Curves/Interval require t in 0..1 – springs can overshoot.)
class Ramp extends Animatable<double> {
  const Ramp(this.from, this.to);
  final double from, to;

  @override
  double transform(double t) => ((t - from) / (to - from)).clamp(0.0, 1.0);
}
