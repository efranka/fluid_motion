import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'contact.dart';
import 'contour.dart';
import 'field.dart';
import 'shape.dart';

/// How the neck between two shapes behaves as they approach each other – in
/// three phases:
///
///  1. Closer than [reach] px: both shapes "pull" a bump out towards each
///     other, centred where they are closest (without meeting yet).
///  2. At [meetAt] px: the tips of the bumps meet in a thin neck.
///  3. Closer still: the neck widens until the surfaces have merged.
@immutable
class GooeyNeckStyle {
  const GooeyNeckStyle({
    this.reach = 12,
    this.meetAt = 8,
    this.smoothnessMin = 6,
    this.smoothnessMax = 12,
    this.smoothnessMerged = 28,
    this.spreadMin = 6,
    this.spreadMax = 36,
    this.letGoAt = 4,
    this.mergeDepth = 10,
    this.cell = 2,
  }) : assert(meetAt < reach);

  /// Gap (px) at which the attraction starts. Set it to the shapes' resting
  /// distance so nothing happens at rest.
  final double reach;

  /// Gap (px) at which the tips of the bumps meet.
  final double meetAt;

  /// Softness of the merge at [reach] and at touch. Low = the bumps drive
  /// the shape; high = the surfaces melt together all at once.
  final double smoothnessMin, smoothnessMax;

  /// Softness once the shapes overlap ([mergeDepth] px or more): the fluid
  /// fillet in the notch between them.
  final double smoothnessMerged, mergeDepth;

  /// The bump's width (px) when the attraction starts and when it is full.
  final double spreadMin, spreadMax;

  /// Gap (px) at which the bumps let go again just before touching –
  /// otherwise the shapes would puff up in every direction around the
  /// contact.
  final double letGoAt;

  /// Grid resolution in px (CPU version only).
  final double cell;
}

/// The geometry of the neck between two shapes in one frame. The same
/// numbers drive the CPU version and the GPU shader, so they look alike.
@immutable
class GooeyNeckGeometry {
  const GooeyNeckGeometry({
    required this.k,
    required this.bumpAmplitude,
    required this.bumpSigma,
    required this.focus,
    required this.region,
  });

  /// Smooth-min softness.
  final double k;

  /// The bumps' height (px) and width (sigma, px).
  final double bumpAmplitude, bumpSigma;

  /// Where the shapes are closest.
  final Offset focus;

  /// The area the neck can appear in.
  final Rect region;

  static const overlap = 0.75;
  static const addsAtLeast = 0.05;

  /// The neck between [a] and [b] – or null if there is none.
  static GooeyNeckGeometry? between(
    GooeyShape a,
    GooeyShape b,
    GooeyNeckStyle style, {
    double margin = 2,
  }) {
    final ra = a.rect, rb = b.rect;
    final (gap, focus) = GooeyContact.measure(a, b);
    final bulge = a.maxBulge + b.maxBulge;
    // A small tolerance, so a spring that has not landed exactly does not
    // light up the neck at rest.
    if (gap - bulge >= math.max(style.reach, style.smoothnessMax / 2) - 0.05) {
      return null;
    }

    // How far the attraction has come: 0 at reach, 1 when touching.
    final pull = ((style.reach - gap) / style.reach).clamp(0.0, 1.0);

    // How deep the shapes overlap (0 when they do not touch).
    final double depth;
    if (a.isRoundedRect && b.isRoundedRect) {
      final ox = math.min(ra.right, rb.right) - math.max(ra.left, rb.left);
      final oy = math.min(ra.bottom, rb.bottom) - math.max(ra.top, rb.top);
      depth = ox > 0 && oy > 0 ? math.min(ox, oy) : 0.0;
    } else {
      // Any outline: how far inside both shapes the closest point lies.
      final da = a.distance(focus.dx, focus.dy);
      final db = b.distance(focus.dx, focus.dy);
      depth = gap > 0 ? 0.0 : math.max(0.0, -(da + db));
    }
    final merged = (depth / style.mergeDepth).clamp(0.0, 1.0);

    // Softness grows while the shapes approach and falls again once they
    // overlap, so the joint does not turn into big wings.
    final k = lerpDouble(
      lerpDouble(style.smoothnessMin, style.smoothnessMax, pull)!,
      style.smoothnessMerged,
      merged,
    )!;

    // The bump's height: grows linearly so the tips meet exactly at meetAt,
    // and lets go again over the last [letGoAt] px before touching.
    final letGo = (gap / style.letGoAt).clamp(0.0, 1.0);
    final amp = style.meetAt /
        2 *
        style.reach /
        (style.reach - style.meetAt) *
        pull *
        letGo;
    // The bump starts narrow (pointed) and widens, so the neck grows out.
    final sigma = lerpDouble(style.spreadMin, style.spreadMax, pull)!;

    // The area: the neck between the shapes plus the bumps around the focus
    // (which reach ~2 sigma along the edges).
    final m = math.max(k + amp + bulge, gap) + margin;
    var region = ra.inflate(m).intersect(rb.inflate(m));
    final bumpReach = 2 * sigma + amp + k;
    final bumps = Rect.fromCircle(center: focus, radius: bumpReach)
        .intersect(ra.expandToInclude(rb).inflate(amp + k + margin));
    if (bumps.width > 0 && bumps.height > 0) {
      region = region.width > 0 && region.height > 0
          ? region.expandToInclude(bumps)
          : bumps;
    }
    if (region.width <= 0 || region.height <= 0) return null;

    return GooeyNeckGeometry(
      k: k,
      bumpAmplitude: amp,
      bumpSigma: sigma,
      focus: focus,
      region: region,
    );
  }
}

/// The CPU version of the neck: distance field on a grid → marching squares
/// → one smooth path. Used for shapes the GPU shader cannot draw, and when
/// the shader is unavailable.
abstract final class GooeyNeckCpu {
  static Float64List _fieldBuf = Float64List(0);

  /// Paint the neck between [a] and [b]. With [field] it is painted from the
  /// shared colour field (so it lines up seamlessly with the shapes),
  /// otherwise with a simple gradient between the shapes' colours.
  static void paint(
    Canvas canvas,
    GooeyShape a,
    GooeyShape b,
    GooeyNeckGeometry g,
    double cell, {
    GooeyColorField? field,
  }) {
    final ra = a.rect, rb = b.rect;
    // The grid is locked to fixed coordinates (multiples of cell). Otherwise
    // the whole grid shifts by a fraction of a pixel with the shapes every
    // frame and the contour shimmers.
    final left = (g.region.left / cell).floorToDouble() * cell;
    final top = (g.region.top / cell).floorToDouble() * cell;
    final region = Rect.fromLTRB(left, top, g.region.right, g.region.bottom);

    final cols = (region.width / cell).ceil();
    final rows = (region.height / cell).ceil();
    if (cols < 1 || rows < 1) return;
    final stride = cols + 1;
    final needed = stride * (rows + 1);
    if (_fieldBuf.length < needed) _fieldBuf = Float64List(needed);
    final f = _fieldBuf;

    final fx = g.focus.dx, fy = g.focus.dy;
    final amp = g.bumpAmplitude;
    final inv = 1 / (g.bumpSigma * g.bumpSigma);
    for (var j = 0; j <= rows; j++) {
      final y = region.top + j * cell;
      final dy2 = (y - fy) * (y - fy);
      final edgeRow = j == 0 || j == rows;
      for (var i = 0; i <= cols; i++) {
        final x = region.left + i * cell;
        final da = a.distance(x, y);
        final db = b.distance(x, y);
        final bump =
            amp > 0 ? amp * math.exp(-((x - fx) * (x - fx) + dy2) * inv) : 0.0;
        // Only what the merge ADDS outside the shapes (plus a thin rim
        // tucked under them, so there is no seam). The shapes' own surfaces
        // are never painted here – otherwise they would peek out at full
        // size when a shape is scaled down (e.g. when pressed).
        final sm = smoothMin(da - bump, db - bump, g.k);
        final plain = math.min(da, db);
        var v = math.max(
          math.max(sm, -(plain + GooeyNeckGeometry.overlap)),
          sm - plain + GooeyNeckGeometry.addsAtLeast,
        );
        // Force the area's border "outside" so every contour is closed.
        if ((edgeRow || i == 0 || i == cols) && v < 1e-3) v = 1e-3;
        f[j * stride + i] = v;
      }
    }

    final path = traceContour(f, cols, rows, region.left, region.top, cell);
    if (path == null) return;

    if (field != null) {
      canvas.save();
      canvas.clipPath(path);
      field.paint(canvas, path.getBounds().inflate(1), cell: 3);
      canvas.restore();
      return;
    }

    // Without a colour field: a gradient from A's edge to B's edge (or over a
    // short stretch around the focus when they overlap).
    Offset clampInto(Offset p, Rect r) =>
        Offset(p.dx.clamp(r.left, r.right), p.dy.clamp(r.top, r.bottom));
    var from = clampInto(g.focus, ra), to = clampInto(g.focus, rb);
    if ((to - from).distance < 1) {
      final axis = rb.center - ra.center;
      final dir = axis.distance > 0 ? axis / axis.distance : const Offset(1, 0);
      from = g.focus - dir * 8;
      to = g.focus + dir * 8;
    }
    canvas.drawPath(
      path,
      Paint()..shader = ui.Gradient.linear(from, to, [a.color, b.color]),
    );
  }
}
