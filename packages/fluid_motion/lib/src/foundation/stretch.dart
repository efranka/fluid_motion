import 'package:flutter/widgets.dart';

/// Stretch along [velocity] (px/s) and squeeze across it, preserving volume.
/// Use with `Transform(alignment: Alignment.center, transform: ...)`.
Matrix4 directionalStretch(
  Offset velocity, {
  double perSpeed = 0.00012,
  double max = 0.15,
}) {
  final s = (velocity.distance * perSpeed).clamp(0.0, max);
  if (s == 0) return Matrix4.identity();
  final a = velocity.direction;
  return Matrix4.rotationZ(a)
    ..multiply(Matrix4.diagonal3Values(1 + s, 1 / (1 + s), 1))
    ..multiply(Matrix4.rotationZ(-a));
}
