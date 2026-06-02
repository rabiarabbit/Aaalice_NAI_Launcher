import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/canvas/layer_painter.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/editor_state.dart';

Future<Color> _paintCanvasPixel({
  required bool showTransparentCanvasBackground,
}) async {
  final state = EditorState()..setCanvasSize(const Size(32, 32));
  addTearDown(state.dispose);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  LayerPainter(
    state: state,
    showTransparentCanvasBackground: showTransparentCanvasBackground,
  ).paint(canvas, const Size(32, 32));

  final picture = recorder.endRecording();
  addTearDown(picture.dispose);
  final image = await picture.toImage(32, 32);
  addTearDown(image.dispose);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(byteData, isNotNull);

  final bytes = byteData!.buffer.asUint8List();
  return Color.fromARGB(bytes[3], bytes[0], bytes[1], bytes[2]);
}

void main() {
  test('default canvas background remains white', () async {
    final color = await _paintCanvasPixel(
      showTransparentCanvasBackground: false,
    );

    expect(color, Colors.white);
  });

  test('transparent canvas background shows checkerboard', () async {
    final color = await _paintCanvasPixel(
      showTransparentCanvasBackground: true,
    );

    expect(color, isNot(Colors.white));
  });
}
