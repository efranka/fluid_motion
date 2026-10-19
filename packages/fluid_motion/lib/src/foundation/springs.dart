import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// A spring whose damping depends on speed (px/s).
///
/// Slow movement → critically damped (glides into place without wobbling).
/// Fast movement → loose spring (bounce). In between: a smooth transition.
///
/// Use the same description across elements, so the whole interface feels
/// made of the same "material".
class EnergySpring {
  const EnergySpring({
    required this.stiffness,
    this.mass = 1,
    this.calmSpeed = 300,
    this.wildSpeed = 2500,
    this.calmRatio = 1.0,
    this.wildRatio = 0.35,
  })  : assert(stiffness > 0, 'stiffness must be positive'),
        assert(mass > 0, 'mass must be positive'),
        assert(calmSpeed >= 0, 'calmSpeed cannot be negative'),
        assert(wildSpeed > calmSpeed, 'wildSpeed must be above calmSpeed'),
        assert(
            calmRatio > 0 && wildRatio > 0, 'damping ratios must be positive');

  final double stiffness, mass;

  /// Below [calmSpeed] px/s: no bounce. Above [wildSpeed]: full bounce.
  final double calmSpeed, wildSpeed;

  /// Damping ratio at each end (1.0 = no oscillation).
  final double calmRatio, wildRatio;

  /// 0..1 – how much "energy" a given speed has.
  double energy(double speed) => Curves.easeIn.transform(
        ((speed.abs() - calmSpeed) / (wildSpeed - calmSpeed)).clamp(0.0, 1.0),
      );

  SpringDescription forSpeed(double speed, {double ratioOffset = 0}) {
    final ratio = lerpDouble(calmRatio, wildRatio, energy(speed))!;
    return SpringDescription.withDampingRatio(
      mass: mass,
      stiffness: stiffness,
      ratio: (ratio + ratioOffset).clamp(0.05, 1.0),
    );
  }

  SpringDescription get calm => forSpeed(0);
}

extension SpringMotion on AnimationController {
  /// Spring from the current value towards [target] with start velocity
  /// [velocity].
  TickerFuture springTo(
    double target,
    SpringDescription spring, {
    double velocity = 0,
  }) =>
      animateWith(SpringSimulation(spring, value, target, velocity));

  /// A kick: the value oscillates around 0 and comes to rest. Useful for
  /// transferring energy from one element to another (follow through).
  TickerFuture kick(double velocity, SpringDescription spring) =>
      animateWith(SpringSimulation(spring, value, 0, velocity));
}

/// iOS-style rubber banding: the further you drag past the limit, the less
/// the element moves. [dimension] is the maximum displacement.
double rubberBand(double overshoot, double dimension, {double c = 0.55}) {
  if (overshoot <= 0) return 0;
  return (1 - 1 / (overshoot * c / dimension + 1)) * dimension;
}
