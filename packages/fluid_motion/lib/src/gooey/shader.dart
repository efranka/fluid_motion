import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'field.dart';
import 'neck.dart';
import 'shape.dart';

/// The GPU version of the gooey neck (`shaders/gooey.frag`), for rounded
/// rects.
///
/// Load it once at startup with [load]. Until it is loaded – or if the
/// platform does not support shaders – the CPU version is used
/// automatically, so nothing breaks.
abstract final class GooeyShader {
  static const assetKey = 'packages/fluid_motion/shaders/gooey.frag';

  static ui.FragmentProgram? _program;
  static final List<ui.FragmentShader> _shaders = [];
  static Object? _error;

  /// Whether the shader is loaded and ready.
  static bool get isReady => _program != null;

  /// The error if loading failed (the CPU version is used instead).
  static Object? get error => _error;

  /// Load the shader. If it fails, the error is logged and the CPU version
  /// is used.
  static Future<bool> load() async {
    if (_program != null) return true;
    try {
      _program = await ui.FragmentProgram.fromAsset(assetKey);
      return true;
    } catch (e) {
      _error = e;
      debugPrint('fluid_motion: GPU shader unavailable, using CPU ($e)');
      return false;
    }
  }

  // One shader instance per neck painted in the same frame (uniforms belong
  // to the instance, so two necks must not share one).
  static ui.FragmentShader _shaderFor(int slot) {
    while (_shaders.length <= slot) {
      _shaders.add(_program!.fragmentShader());
    }
    return _shaders[slot];
  }

  /// Paint the neck between [a] and [b]. [slot] must be unique for each neck
  /// painted in the same frame (e.g. the pair's number).
  static void paint(
    Canvas canvas,
    int slot,
    GooeyShape a,
    GooeyShape b,
    GooeyNeckGeometry g, {
    double blendWidth = 0,
  }) {
    final s = _shaderFor(slot);
    var i = 0;
    void f(double v) => s.setFloat(i++, v);
    void rect(Rect r) {
      f(r.left);
      f(r.top);
      f(r.right);
      f(r.bottom);
    }

    void rip(GooeyShape shape) {
      final r = shape.strongestRipple;
      if (r == null) {
        f(0);
        f(0);
        f(0);
        f(0);
      } else {
        f(r.center.dx);
        f(r.center.dy);
        f(r.amplitude);
        f(1 / (r.radius * r.radius));
      }
    }

    void color(Color c) {
      f(c.r);
      f(c.g);
      f(c.b);
      f(c.a);
    }

    rect(a.rect); // uRectA
    rect(b.rect); // uRectB
    f(a.cornerRadius); // uRadius
    f(b.cornerRadius);
    rip(a); // uRipA
    rip(b); // uRipB
    f(g.focus.dx); // uBump
    f(g.focus.dy);
    f(g.bumpAmplitude);
    f(1 / (g.bumpSigma * g.bumpSigma));
    f(g.k); // uParams
    f(GooeyNeckGeometry.overlap);
    f(GooeyNeckGeometry.addsAtLeast);
    f(blendWidth);
    color(a.color); // uColA
    color(b.color); // uColB

    canvas.drawRect(g.region, Paint()..shader = s);
  }

  /// The width over which the shader blends colours for the pair (i, j) –
  /// the same as the colour field, so neck and shapes line up.
  static double blendWidthFor(GooeyColorField? field, int i, int j) =>
      field == null ? 0 : field.widthOf(i, j);
}
