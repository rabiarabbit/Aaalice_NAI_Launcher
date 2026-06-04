import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/hard_edge_mask_exporter.dart';

void main() {
  test('exports additional mask rects as white hard-edge pixels', () async {
    final bytes = await HardEdgeMaskExporter.exportAsync(
      const HardEdgeMaskExportInput(
        width: 8,
        height: 6,
        strokes: [],
        baseMasks: [],
        additionalRects: [Rect.fromLTWH(0, 0, 3, 2)],
      ),
    );

    final mask = img.decodeImage(bytes)!;
    expect(mask.width, equals(8));
    expect(mask.height, equals(6));
    expect(mask.getPixel(0, 0).r, equals(255));
    expect(mask.getPixel(2, 1).r, equals(255));
    expect(mask.getPixel(3, 1).r, equals(0));
  });

  test('draws stroke polylines and erases over earlier strokes', () async {
    final bytes = await HardEdgeMaskExporter.exportAsync(
      const HardEdgeMaskExportInput(
        width: 16,
        height: 8,
        strokes: [
          HardEdgeMaskStroke(
            points: [Offset(1, 4), Offset(14, 4)],
            size: 5,
            isEraser: false,
          ),
          HardEdgeMaskStroke(
            points: [Offset(8, 4)],
            size: 5,
            isEraser: true,
          ),
        ],
        baseMasks: [],
        additionalRects: [],
      ),
    );

    final mask = img.decodeImage(bytes)!;
    expect(mask.getPixel(2, 4).r, equals(255));
    expect(mask.getPixel(8, 4).r, equals(0));
    expect(mask.getPixel(13, 4).r, equals(255));
  });

  test('pastes an offset base mask before drawing strokes', () async {
    final base = img.Image(width: 2, height: 2, numChannels: 4);
    img.fill(base, color: img.ColorRgba8(0, 0, 0, 0));
    base.setPixelRgba(0, 0, 255, 255, 255, 255);

    final bytes = await HardEdgeMaskExporter.exportAsync(
      HardEdgeMaskExportInput(
        width: 6,
        height: 6,
        strokes: const [],
        baseMasks: [
          HardEdgeMaskBaseImage(
            bytes: Uint8List.fromList(img.encodePng(base)),
            offsetX: 2,
            offsetY: 3,
          ),
        ],
        additionalRects: const [],
      ),
    );

    final mask = img.decodeImage(bytes)!;
    expect(mask.getPixel(2, 3).r, equals(255));
    expect(mask.getPixel(1, 3).r, equals(0));
  });

  test('draws additional mask rects after eraser strokes', () async {
    final bytes = await HardEdgeMaskExporter.exportAsync(
      const HardEdgeMaskExportInput(
        width: 8,
        height: 6,
        strokes: [
          HardEdgeMaskStroke(
            points: [Offset(1, 1)],
            size: 5,
            isEraser: true,
          ),
        ],
        baseMasks: [],
        additionalRects: [Rect.fromLTWH(0, 0, 4, 4)],
      ),
    );

    final mask = img.decodeImage(bytes)!;
    expect(mask.getPixel(1, 1).r, equals(255));
    expect(mask.getPixel(4, 1).r, equals(0));
  });

  test('ordered operations preserve base and stroke order', () async {
    final basePixel = _singleWhitePixelPng();

    final bytes = await HardEdgeMaskExporter.exportAsync(
      HardEdgeMaskExportInput(
        width: 8,
        height: 6,
        strokes: const [],
        baseMasks: const [],
        additionalRects: const [],
        orderedOperations: [
          HardEdgeMaskBaseImageOperation(
            baseMask: HardEdgeMaskBaseImage(
              bytes: basePixel,
              offsetX: 2,
              offsetY: 2,
            ),
          ),
          const HardEdgeMaskStrokeOperation(
            stroke: HardEdgeMaskStroke(
              points: [Offset(2, 2), Offset(4, 2)],
              size: 3,
              isEraser: true,
            ),
          ),
          HardEdgeMaskBaseImageOperation(
            baseMask: HardEdgeMaskBaseImage(
              bytes: basePixel,
              offsetX: 4,
              offsetY: 2,
            ),
          ),
        ],
      ),
    );

    final mask = img.decodeImage(bytes)!;
    expect(mask.getPixel(2, 2).r, equals(0));
    expect(mask.getPixel(4, 2).r, equals(255));
  });

  test('draws three-point strokes with smoothed quadratic path semantics',
      () async {
    final bytes = await HardEdgeMaskExporter.exportAsync(
      const HardEdgeMaskExportInput(
        width: 22,
        height: 14,
        strokes: [
          HardEdgeMaskStroke(
            points: [Offset(2, 10), Offset(10, 2), Offset(18, 10)],
            size: 3,
            isEraser: false,
          ),
        ],
        baseMasks: [],
        additionalRects: [],
      ),
    );

    final mask = img.decodeImage(bytes)!;
    expect(mask.getPixel(9, 5).r, equals(255));
    expect(mask.getPixel(10, 2).r, equals(0));
  });
}

Uint8List _singleWhitePixelPng() {
  final base = img.Image(width: 1, height: 1, numChannels: 4);
  base.setPixelRgba(0, 0, 255, 255, 255, 255);
  return Uint8List.fromList(img.encodePng(base));
}
