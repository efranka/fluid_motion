import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

/// The number of floats `shaders/gooey.frag` declares, in declaration order.
int floatsInShader() {
  final source = File('shaders/gooey.frag').readAsStringSync();
  final sizes = {'float': 1, 'vec2': 2, 'vec4': 4};
  var n = 0;
  for (final m in RegExp(r'^uniform (float|vec2|vec4) \w+(?:\[(\d+)\])?;',
          multiLine: true)
      .allMatches(source)) {
    n += sizes[m.group(1)]! * int.parse(m.group(2) ?? '1');
  }
  return n;
}

void main() {
  late ui.FragmentProgram program;

  setUpAll(() async {
    expect(await GooeyShader.load(asset: 'shaders/gooey.frag'), isTrue);
    program = await ui.FragmentProgram.fromAsset('shaders/gooey.frag');
  });

  final a =
      GooeyShape(const Rect.fromLTWH(0, 0, 200, 56), const Color(0xFF333333));
  final b =
      GooeyShape(const Rect.fromLTWH(204, 0, 56, 56), const Color(0xFF6655AA));
  final neck = GooeyNeckGeometry.between(a, b, const GooeyNeckStyle())!;
  // Every part on, so every uniform is written with something.
  const light = GooeyLight(
    edgeColors: [Color(0x40FFFFFF), Color(0x10FFFFFF), Color(0x20FFFFFF)],
    edgeStops: [0, 0.5, 1],
    fillStart: Color(0x10FFFFFF),
    fillEnd: Color(0x10000000),
    glowStart: Color(0x20FFFFFF),
    glowEnd: Color(0x10FFFFFF),
    outlineGlow: Color(0x18FFFFFF),
    shadows: [BoxShadow(color: Color(0x40000000), blurRadius: 12)],
  );

  Canvas canvas() => Canvas(ui.PictureRecorder());

  test('every mode writes exactly the uniforms the shader declares', () {
    final expected = floatsInShader();
    expect(expected, greaterThan(300));

    GooeyShader.paintNeck(canvas(), program.fragmentShader(), a, b, neck,
        light: light);
    expect(GooeyShader.debugUniformsWritten, expected, reason: 'neck');

    GooeyShader.paintNeck(canvas(), program.fragmentShader(), a, b, neck);
    expect(GooeyShader.debugUniformsWritten, expected,
        reason: 'neck, no light');

    GooeyShader.paintSurface(canvas(), program.fragmentShader(), a,
        others: [b], blendWidths: [40], necks: [neck], light: light);
    expect(GooeyShader.debugUniformsWritten, expected, reason: 'surface');

    GooeyShader.paintSurface(canvas(), program.fragmentShader(), a);
    expect(GooeyShader.debugUniformsWritten, expected,
        reason: 'surface, alone');

    GooeyShader.paintShadow(
        canvas(), program.fragmentShader(), [a, b], light.shadows.first,
        neck: neck);
    expect(GooeyShader.debugUniformsWritten, expected, reason: 'shadow');
  });
}
