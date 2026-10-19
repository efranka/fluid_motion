import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'field.dart';
import 'geometry.dart';
import 'neck.dart';
import 'shape.dart';

/// The GPU side of the gooey system (`shaders/gooey.frag`): necks and shape
/// surfaces – with colour blending and blobs – for every built-in outline.
///
/// Load it once at startup with [load]. Until it is loaded – or if the
/// platform does not support shaders, or for a custom geometry without a
/// [GooeySdf.gpu] description – the CPU version is used automatically, so
/// nothing breaks.
abstract final class GooeyShader {
  static const assetKey = 'packages/fluid_motion/shaders/gooey.frag';

  static ui.FragmentProgram? _program;
  static ui.Image? _empty;
  static Object? _error;

  /// Whether the shader is loaded and ready.
  static bool get isReady => _program != null && _empty != null;

  /// The error if loading failed (the CPU version is used instead).
  static Object? get error => _error;

  /// Notifies when something new became drawable on the GPU (e.g. a path's
  /// distance field finished uploading), so scenes can repaint.
  static Listenable get updates => _updates;
  static final _updates = _Updates();

  /// Load the shader. If it fails, the error is logged and the CPU version
  /// is used.
  static Future<bool> load() async {
    if (isReady) return true;
    try {
      _program ??= await ui.FragmentProgram.fromAsset(assetKey);
      // Samplers must always be bound; unused ones get this 1×1 image.
      _empty ??= await _image(Uint8List.fromList([128, 128, 128, 255]), 1, 1);
      return true;
    } catch (e) {
      _error = e;
      debugPrint('fluid_motion: GPU shader unavailable, using CPU ($e)');
      return false;
    }
  }

  /// A new shader instance. Uniforms belong to the instance, so each thing
  /// painted in the same frame – and each retained picture – needs its own.
  static ui.FragmentShader newShader() => _program!.fragmentShader();

  // -------------------------------------------------------------------------
  // What the GPU can draw
  // -------------------------------------------------------------------------

  /// Whether [shape] can be drawn on the GPU right now. A path's distance
  /// field is uploaded in the background the first time it is asked for;
  /// until then this returns false (and [updates] notifies when it is
  /// ready).
  static bool canDraw(GooeyShape shape) {
    if (!isReady) return false;
    final g = shape.sdf.gpu;
    if (g == null) return false;
    if (g.type == GooeyGpuShape.typeField) return _textureFor(g.field!) != null;
    return true;
  }

  static final _textures = Expando<ui.Image>();
  static final _pending = Expando<bool>();

  /// The field's distances range ±[_fieldRange] field units over 0..255.
  static const _fieldRange = 32.0;

  static ui.Image? _textureFor(GooeyGpuField f) {
    final ready = _textures[f.values];
    if (ready != null) return ready;
    if (_pending[f.values] == true) return null;
    _pending[f.values] = true;
    final bytes = Uint8List(f.cols * f.rows * 4);
    for (var i = 0; i < f.values.length; i++) {
      final v =
          (127.5 + f.values[i] / _fieldRange * 127.5).round().clamp(0, 255);
      bytes[4 * i] = v;
      bytes[4 * i + 1] = v;
      bytes[4 * i + 2] = v;
      bytes[4 * i + 3] = 255;
    }
    _image(bytes, f.cols, f.rows).then((image) {
      _textures[f.values] = image;
      _updates.ping();
    });
    return null;
  }

  static Future<ui.Image> _image(Uint8List rgba, int width, int height) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  // -------------------------------------------------------------------------
  // Painting
  // -------------------------------------------------------------------------

  /// Paint the neck between [a] and [b] (in scene coordinates) with [shader].
  static void paintNeck(
    Canvas canvas,
    ui.FragmentShader shader,
    GooeyShape a,
    GooeyShape b,
    GooeyNeckGeometry g, {
    double blendWidth = 0,
    double pixelRatio = 1,
  }) {
    final w = _UniformWriter(shader);
    w.vec4(0, g.k, GooeyNeckGeometry.overlap, GooeyNeckGeometry.addsAtLeast);
    w.vec4(blendWidth, 0, 0, pixelRatio);
    w.vec4(g.focus.dx, g.focus.dy, g.bumpAmplitude,
        1 / (g.bumpSigma * g.bumpSigma));
    w.color(a.color);
    w.color(b.color);
    w.color(b.color);
    w.color(b.color);
    w.vec4(0, 0, 0, 0);
    _shape(w, a, 0);
    _shape(w, b, 1);
    _shape(w, null, 2);
    _shape(w, null, 3);
    canvas.drawRect(g.region, Paint()..shader = shader);
  }

  /// How many neighbours a shape's surface can blend towards at once – the
  /// number of neighbour slots in the shader. Each slot costs a little for
  /// every pixel of a surface, used or not, so it is kept small; a shape
  /// rarely touches more than three others at the same time. To raise it,
  /// add slots to `shaders/gooey.frag` too.
  static const maxNeighbours = 3;

  /// Paint the surface of [shape] on a canvas whose origin is the shape's
  /// top left corner, blending towards each of [others] over the matching
  /// width in [blendWidths] (px). Empty [others] = the shape's own colour.
  ///
  /// At most [maxNeighbours] others are used – pass the most connected
  /// first.
  static void paintSurface(
    Canvas canvas,
    ui.FragmentShader shader,
    GooeyShape shape, {
    List<GooeyShape> others = const [],
    List<double> blendWidths = const [],
    double pixelRatio = 1,
  }) {
    assert(
        others.length == blendWidths.length, 'one blend width per other shape');
    final n = others.length < maxNeighbours ? others.length : maxNeighbours;
    GooeyShape? other(int i) => i < n ? others[i] : null;
    double width(int i) => i < n ? blendWidths[i] : 0;

    final origin = shape.rect.topLeft;
    final w = _UniformWriter(shader);
    w.vec4(1, 1, 0, 0);
    w.vec4(0, origin.dx, origin.dy, pixelRatio);
    w.vec4(0, 0, 0, 1);
    w.color(shape.color);
    for (var i = 0; i < maxNeighbours; i++) {
      w.color(other(i)?.color ?? shape.color);
    }
    w.vec4(width(0), width(1), width(2), 0);
    _shape(w, shape, 0);
    for (var i = 0; i < maxNeighbours; i++) {
      _shape(w, other(i), i + 1);
    }
    final area = shape.rect.inflate(shape.maxBulge + 2).shift(-origin);
    canvas.drawRect(area, Paint()..shader = shader);
  }

  /// Writes one shape's uniforms: rect, kind, three ripples, 24 vertices –
  /// and binds its texture (or the empty one) to sampler [slot].
  static void _shape(_UniformWriter w, GooeyShape? s, int slot) {
    final g = s?.sdf.gpu;
    ui.Image texture = _empty!;
    if (s == null || g == null) {
      w.vec4(0, 0, 0, 0);
      w.vec4(-1, 0, 0, 0);
      w.zeros(12 + 2 * GooeyGpuShape.maxVertices);
      w.shader.setImageSampler(slot, texture);
      return;
    }
    final r = s.rect;
    w.vec4(r.left, r.top, r.right, r.bottom);
    final verts = g.vertices;
    w.vec4(g.type.toDouble(), g.p1, g.p2,
        verts == null ? 0 : (verts.length ~/ 2).toDouble());

    // The three strongest ripples.
    final ripples = [...s.ripples]
      ..sort((x, y) => y.amplitude.abs().compareTo(x.amplitude.abs()));
    for (var i = 0; i < 3; i++) {
      if (i < ripples.length) {
        final rp = ripples[i];
        w.vec4(rp.center.dx, rp.center.dy, rp.amplitude,
            1 / (rp.radius * rp.radius));
      } else {
        w.vec4(0, 0, 0, 0);
      }
    }

    // Vertices – or, for a field, its mapping into the texture.
    var written = 0;
    final f = g.field;
    if (f != null) {
      texture = _textureFor(f) ?? _empty!;
      w
        ..vec4(f.ax, f.ay, f.bx, f.by)
        ..vec4(f.padded.left, f.padded.top, f.padded.right, f.padded.bottom)
        ..vec4(2 * _fieldRange * f.distanceScale, f.cols.toDouble(),
            f.rows.toDouble(), 0);
      written = 12;
    } else if (verts != null) {
      for (final v in verts) {
        w.float(v);
      }
      written = verts.length;
    }
    w.zeros(2 * GooeyGpuShape.maxVertices - written);
    w.shader.setImageSampler(slot, texture);
  }

  /// The width over which colours blend for the pair (i, j) – the same as
  /// the colour field, so neck and shapes line up.
  static double blendWidthFor(GooeyColorField? field, int i, int j) =>
      field == null ? 0 : field.widthOf(i, j);
}

class _Updates extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _UniformWriter {
  _UniformWriter(this.shader);
  final ui.FragmentShader shader;
  int _i = 0;

  void float(double v) => shader.setFloat(_i++, v);

  void vec4(double a, double b, double c, double d) {
    float(a);
    float(b);
    float(c);
    float(d);
  }

  void color(Color c) => vec4(c.r, c.g, c.b, c.a);

  void zeros(int n) {
    for (var k = 0; k < n; k++) {
      float(0);
    }
  }
}
