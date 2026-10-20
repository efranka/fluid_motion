import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';
import 'package:fluid_motion_example/edge_light/edge_light_screen.dart';

/// How alike two images are: the mean and the largest difference per
/// channel (0–255), and the share of pixels that differ by more than 8.
({double mean, int max, double share}) compare(ByteData a, ByteData b) {
  var sum = 0, max = 0, off = 0;
  final n = a.lengthInBytes ~/ 4;
  for (var i = 0; i < n; i++) {
    var worst = 0;
    for (var c = 0; c < 4; c++) {
      final d = (a.getUint8(i * 4 + c) - b.getUint8(i * 4 + c)).abs();
      sum += d;
      if (d > worst) worst = d;
    }
    if (worst > max) max = worst;
    if (worst > 8) off++;
  }
  return (mean: sum / (n * 4), max: max, share: off / n);
}

void main() {
  setUpAll(() async {
    expect(await GooeyShader.load(), isTrue);
  });

  Future<(ui.Image, ui.Image)> render(
    WidgetTester tester, {
    required Brightness brightness,
    required double gap,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFCBC3F5),
          brightness: brightness,
        ),
      ),
      home: EdgeLightScreen(initialGap: gap),
    ));
    await tester.pump();
    Future<ui.Image> grab(Type panel) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .descendant(
                of: find.byType(panel), matching: find.byType(RepaintBoundary))
            .first,
      );
      return boundary.toImage(pixelRatio: 2);
    }

    return (await tester.runAsync(() async =>
        (await grab(EdgeLightFlatPanel), await grab(EdgeLightGooeyPanel))))!;
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'apart, the rim light looks like the plain Flutter one '
        '(${brightness.name})', (tester) async {
      final (flat, gooey) =
          await render(tester, brightness: brightness, gap: 24);
      final (a, b) = (await tester.runAsync(() async => (
            (await flat.toByteData())!,
            (await gooey.toByteData())!,
          )))!;
      final r = compare(a, b);
      // ignore: avoid_print
      print('${brightness.name}: mean ${r.mean.toStringAsFixed(2)}, '
          'max ${r.max}, ${(r.share * 100).toStringAsFixed(2)} % of pixels '
          'differ by more than 8');
      if (Platform.environment['EDGE_LIGHT_IMAGES'] case final dir?) {
        for (final (name, img) in [('flat', flat), ('gooey', gooey)]) {
          final png = (await tester
              .runAsync(() => img.toByteData(format: ui.ImageByteFormat.png)))!;
          File('$dir/${brightness.name}_$name.png')
              .writeAsBytesSync(png.buffer.asUint8List());
        }
      }
      expect(r.mean, lessThan(1.0));
    });
  }
}
