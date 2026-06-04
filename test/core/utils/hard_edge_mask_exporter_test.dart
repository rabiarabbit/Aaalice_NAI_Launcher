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
}
