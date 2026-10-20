import 'package:flutter/widgets.dart';

import 'foundation/springs.dart';

/// Motion tokens: the springs and timings the whole interface shares, so
/// everything feels made of the same "material" – just like colour and
/// typography tokens in a design system.
///
/// Put a [MotionScope] at the top of the app to change them in one place.
@immutable
class MotionTokens {
  const MotionTokens({
    this.primary = const EnergySpring(stiffness: 420),
    this.follower = const EnergySpring(stiffness: 280),
    this.secondary = const EnergySpring(
      stiffness: 300,
      calmRatio: 0.9,
      wildRatio: 0.4,
    ),
    this.followerDelay = const Duration(milliseconds: 60),
    this.followerRatioOffset = 0.15,
    this.pressedScale = 0.96,
    this.pressDownStiffness = 900,
    this.pressUpStiffness = 400,
    this.pressUpRatio = 0.5,
    this.indicatorLeadStiffness = 700,
    this.indicatorTrailStiffness = 240,
  });

  /// The primary movement (the element the user drives).
  final EnergySpring primary;

  /// Elements that follow the primary movement (overlapping action).
  final EnergySpring follower;

  /// Secondary details that land a little later (secondary action).
  final EnergySpring secondary;

  /// How long a follower waits before starting from rest.
  final Duration followerDelay;

  /// How much calmer a follower is than the primary movement (damping).
  final double followerRatioOffset;

  /// Press feedback.
  final double pressedScale, pressDownStiffness, pressUpStiffness, pressUpRatio;

  /// Stretchy indicator (tabs/segments): stiff leading, soft trailing edge.
  final double indicatorLeadStiffness, indicatorTrailStiffness;

  SpringDescription get pressDown => SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: pressDownStiffness,
        ratio: 1,
      );

  SpringDescription get pressUp => SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: pressUpStiffness,
        ratio: pressUpRatio,
      );

  static const standard = MotionTokens();
}

/// Passes [MotionTokens] down to everything below it – and, if set, an
/// explicit "Reduce motion" choice that overrides the system setting.
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    this.tokens = MotionTokens.standard,
    this.reduceMotion,
    required super.child,
  });

  final MotionTokens tokens;

  /// Forces "Reduce motion" on (true) or off (false) for everything below,
  /// e.g. for an in-app setting or a test. Null follows the system setting
  /// (`MediaQuery.disableAnimations`).
  final bool? reduceMotion;

  /// Tokens from the nearest [MotionScope] – or the standard ones.
  static MotionTokens of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.tokens ??
      MotionTokens.standard;

  /// Whether the user has asked for less motion ("Reduce motion"): the
  /// nearest [MotionScope.reduceMotion] if set, otherwise the system setting.
  /// Components then only show the state change itself – without bounce,
  /// stretch, blobs and the like. [PressScale] and [GooeyStage] follow it by
  /// themselves; controllers without a context take it as a property (see
  /// [DragSpringController.reduceMotion]).
  static bool reduceMotionOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.reduceMotion ??
      MediaQuery.maybeDisableAnimationsOf(context) ??
      false;

  @override
  bool updateShouldNotify(MotionScope oldWidget) =>
      oldWidget.tokens != tokens || oldWidget.reduceMotion != reduceMotion;
}
