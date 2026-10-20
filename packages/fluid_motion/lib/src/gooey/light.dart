import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Edge light for a [GooeyScene]: a thin edge with a gradient, a fill
/// gradient, inner glows and soft shadows – all following the MERGED
/// outline of the shapes, so the edge runs along the neck and vanishes where
/// the shapes have flowed together. Works with every outline.
///
/// Every part is optional and every measure and colour is a parameter, so
/// the same building block gives a hairline edge, a strong glow, a glossy
/// rim light or just a shadow. Colours are laid OVER each shape's own
/// (blended) colour, so one light works for every shape in the scene: use
/// white or black with low opacity, or any colour.
///
/// Gradients run along an axis in each shape's own rect, from [begin] to
/// [end] (like [LinearGradient]); between connected shapes the position on
/// the axis is blended like the colour, so there is no seam.
///
/// The default is a hairline edge and nothing else.
///
/// Drawn on the GPU only (prototype); on the CPU fallback the shapes are
/// drawn without it.
@immutable
class GooeyLight {
  const GooeyLight({
    this.edgeWidth = 1,
    this.edgeColors = const [Color(0x33FFFFFF)],
    this.edgeStops = const [0],
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
    this.fillStart = _none,
    this.fillEnd = _none,
    this.glowStart = _none,
    this.glowEnd = _none,
    this.glowDepth = 12,
    this.outlineGlow = _none,
    this.outlineGlowDepth = 8,
    this.shadows = const [],
  });

  static const _none = Color(0x00000000);

  /// The edge's width (px), inside the merged outline. 0 = no edge.
  final double edgeWidth;

  /// The edge's colours along the axis, at [edgeStops] (0 = [begin],
  /// 1 = [end]). One to four colours, one stop each.
  final List<Color> edgeColors;
  final List<double> edgeStops;

  /// The gradient axis in each shape's rect.
  final Alignment begin, end;

  /// Laid over the fill at the start ([begin]) and at the end ([end]),
  /// each fading to nothing at the other end.
  final Color fillStart, fillEnd;

  /// Inner glow from the start and the end of the axis, fading out over
  /// [glowDepth] px (at most half the shape). Never from the sides.
  final Color glowStart, glowEnd;
  final double glowDepth;

  /// Inner glow all along the merged outline, fading out over
  /// [outlineGlowDepth] px.
  final Color outlineGlow;
  final double outlineGlowDepth;

  /// Soft shadows under the merged shapes, like [BoxShadow]s (one GPU pass
  /// each).
  final List<BoxShadow> shadows;

  GooeyLight copyWith({
    double? edgeWidth,
    List<Color>? edgeColors,
    List<double>? edgeStops,
    Alignment? begin,
    Alignment? end,
    Color? fillStart,
    Color? fillEnd,
    Color? glowStart,
    Color? glowEnd,
    double? glowDepth,
    Color? outlineGlow,
    double? outlineGlowDepth,
    List<BoxShadow>? shadows,
  }) =>
      GooeyLight(
        edgeWidth: edgeWidth ?? this.edgeWidth,
        edgeColors: edgeColors ?? this.edgeColors,
        edgeStops: edgeStops ?? this.edgeStops,
        begin: begin ?? this.begin,
        end: end ?? this.end,
        fillStart: fillStart ?? this.fillStart,
        fillEnd: fillEnd ?? this.fillEnd,
        glowStart: glowStart ?? this.glowStart,
        glowEnd: glowEnd ?? this.glowEnd,
        glowDepth: glowDepth ?? this.glowDepth,
        outlineGlow: outlineGlow ?? this.outlineGlow,
        outlineGlowDepth: outlineGlowDepth ?? this.outlineGlowDepth,
        shadows: shadows ?? this.shadows,
      );

  /// Only the shadows – nothing on the shapes themselves.
  GooeyLight get shadowsOnly => GooeyLight(edgeWidth: 0, shadows: shadows);

  /// Whether anything is drawn on the shapes themselves (not counting the
  /// shadows).
  bool get showsOnSurface =>
      (edgeWidth > 0 && edgeColors.any((c) => c.a > 0)) ||
      fillStart.a > 0 ||
      fillEnd.a > 0 ||
      glowStart.a > 0 ||
      glowEnd.a > 0 ||
      outlineGlow.a > 0;

  @override
  bool operator ==(Object other) =>
      other is GooeyLight &&
      other.edgeWidth == edgeWidth &&
      listEquals(other.edgeColors, edgeColors) &&
      listEquals(other.edgeStops, edgeStops) &&
      other.begin == begin &&
      other.end == end &&
      other.fillStart == fillStart &&
      other.fillEnd == fillEnd &&
      other.glowStart == glowStart &&
      other.glowEnd == glowEnd &&
      other.glowDepth == glowDepth &&
      other.outlineGlow == outlineGlow &&
      other.outlineGlowDepth == outlineGlowDepth &&
      listEquals(other.shadows, shadows);

  @override
  int get hashCode => Object.hash(
        edgeWidth,
        Object.hashAll(edgeColors),
        Object.hashAll(edgeStops),
        begin,
        end,
        fillStart,
        fillEnd,
        glowStart,
        glowEnd,
        glowDepth,
        outlineGlow,
        outlineGlowDepth,
        Object.hashAll(shadows),
      );
}
