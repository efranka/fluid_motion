import 'dart:io';
import 'dart:typed_data';
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

/// Each uniform in `shaders/gooey.frag` with its first vec4 slot – as most
/// GPUs place them: every uniform and every array element starts a new slot.
List<(String, int)> slotsInShader() {
  final source = File('shaders/gooey.frag').readAsStringSync();
  final slots = <(String, int)>[];
  var slot = 0;
  for (final m in RegExp(r'^uniform (?:float|vec2|vec4) (\w+)(?:\[(\d+)\])?;',
          multiLine: true)
      .allMatches(source)) {
    slots.add((m.group(1)!, slot));
    slot += int.parse(m.group(2) ?? '1');
  }
  return slots;
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

  test('a rounded rect reads only the first 46 slots; vertices come last', () {
    // The iPhone 11 in Safari drew the shapes but not the light or the
    // shadow while their uniforms came after the vertex arrays (slot 124
    // on). Keep everything but the vertices in the first slots.
    final slots = slotsInShader();
    final firstVertex = slots.firstWhere((u) => u.$1.startsWith('uVert')).$2;
    expect(firstVertex, 46);
    for (final (name, _) in slots.skipWhile((u) => !u.$1.startsWith('uVert'))) {
      expect(name, startsWith('uVert'), reason: 'only vertices after them');
    }
  });

  group('drawn', () {
    const size = Size(220, 120);
    final shape = GooeyShape(
        const Rect.fromLTWH(10, 10, 200, 56), const Color(0xFF211F26));

    Future<ByteData> pixels(void Function(Canvas c) draw) async {
      final recorder = ui.PictureRecorder();
      draw(Canvas(recorder));
      final image = await recorder
          .endRecording()
          .toImage(size.width.toInt(), size.height.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }

    int channel(ByteData d, int x, int y, int c) =>
        d.getUint8((y * size.width.toInt() + x) * 4 + c);

    void surface(Canvas c, GooeyLight? light) {
      c.save();
      c.translate(shape.rect.left, shape.rect.top);
      GooeyShader.paintSurface(c, program.fragmentShader(), shape,
          light: light);
      c.restore();
    }

    test('the edge light shows on a surface alone', () async {
      final plain = await pixels((c) => surface(c, null));
      final lit = await pixels((c) => surface(c, light));
      // The fill is drawn either way …
      expect(channel(plain, 110, 38, 3), 255);
      // … and the edge, one pixel inside the top, only with the light.
      var most = 0;
      for (var x = 60; x < 160; x++) {
        for (var k = 0; k < 3; k++) {
          final d = (channel(lit, x, 10, k) - channel(plain, x, 10, k)).abs();
          if (d > most) most = d;
        }
      }
      expect(most, greaterThan(6));
    });

    // The vertices are packed two per vec4: the GPU outline must match the
    // CPU one for odd and even corner counts, and for a sampled field.
    for (final (name, geometry) in [
      ('star (10 corners)', const GooeyStar() as GooeyGeometry),
      ('polygon (7 corners)', GooeyPolygon.regular(7)),
      (
        'field',
        GooeyPathGeometry((s) => Path()
          ..moveTo(0, s.height)
          ..lineTo(s.width / 2, 0)
          ..lineTo(s.width, s.height)
          ..close()),
      ),
    ]) {
      test('a $name is drawn where the CPU outline is', () async {
        final s = GooeyShape(
            const Rect.fromLTWH(10, 10, 100, 100), const Color(0xFF6655AA),
            geometry: geometry);
        // A field's texture is uploaded asynchronously.
        for (var i = 0; i < 100 && !GooeyShader.canDraw(s); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(GooeyShader.canDraw(s), isTrue);
        final drawn = await pixels((c) {
          c.translate(s.rect.left, s.rect.top);
          GooeyShader.paintSurface(c, program.fragmentShader(), s);
        });
        var checked = 0;
        for (var y = 0; y < size.height; y += 3) {
          for (var x = 0; x < size.width; x += 3) {
            final d = s.distance(x + 0.5, y + 0.5);
            if (d.abs() < 2.5) continue;
            final alpha = channel(drawn, x, y, 3);
            expect(alpha, d < 0 ? greaterThan(200) : lessThan(50),
                reason: '($x, $y), distance $d');
            checked++;
          }
        }
        expect(checked, greaterThan(500));
      });
    }

    test('the shadow shows under a shape alone', () async {
      final shadow = await pixels((c) => GooeyShader.paintShadow(
          c, program.fragmentShader(), [shape], light.shadows.first));
      // Just below the shape, where only the shadow is.
      expect(channel(shadow, 110, 68, 3), greaterThan(2));
    });
  });
}
