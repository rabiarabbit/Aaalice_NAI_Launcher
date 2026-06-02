import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/inpaint_outpaint_utils.dart';

void main() {
  group('InpaintOutpaintUtils.expand', () {
    test('expands source without snapping and masks only outpaint edges', () {
      final sourceImage = _sourcePng(4, 4);

      final result = InpaintOutpaintUtils.expand(
        sourceImage: sourceImage,
        edges: const OutpaintEdges(left: 2, top: 1, right: 3, bottom: 2),
        snapTo64: false,
      );

      expect(result.width, equals(9));
      expect(result.height, equals(7));
      expect(result.sourceOffsetX, equals(2));
      expect(result.sourceOffsetY, equals(1));
      expect(result.appliedEdges.left, equals(2));
      expect(result.appliedEdges.top, equals(1));
      expect(result.appliedEdges.right, equals(3));
      expect(result.appliedEdges.bottom, equals(2));

      final expandedSource = img.decodeImage(result.sourceImage)!;
      final shiftedSourcePixel = expandedSource.getPixel(2, 1);
      expect(shiftedSourcePixel.r.toInt(), equals(24));
      expect(shiftedSourcePixel.g.toInt(), equals(48));
      expect(shiftedSourcePixel.b.toInt(), equals(72));
      expect(shiftedSourcePixel.a.toInt(), equals(255));
      expect(expandedSource.getPixel(0, 0).a.toInt(), equals(0));

      final expandedMask = img.decodeImage(result.maskImage)!;
      expect(expandedMask.getPixel(0, 0).r.toInt(), equals(255));
      expect(expandedMask.getPixel(2, 1).r.toInt(), equals(0));
      expect(expandedMask.getPixel(5, 4).r.toInt(), equals(0));
      expect(expandedMask.getPixel(6, 1).r.toInt(), equals(255));
      expect(expandedMask.getPixel(2, 5).r.toInt(), equals(255));
    });

    test('normalizes expanded source to 8-bit RGBA before copying pixels', () {
      final source = img.Image(
        width: 1,
        height: 1,
        format: img.Format.uint16,
        numChannels: 4,
      );
      source.setPixelRgba(0, 0, 0xffff, 0x8000, 0x4000, 0x8000);

      final result = InpaintOutpaintUtils.expand(
        sourceImage: Uint8List.fromList(img.encodePng(source)),
        edges: const OutpaintEdges(left: 1, top: 1),
        snapTo64: false,
      );

      final expandedSource = img.decodeImage(result.sourceImage)!;
      final shiftedPixel = expandedSource.getPixel(1, 1);
      expect(shiftedPixel.r.toInt(), equals(255));
      expect(shiftedPixel.g.toInt(), equals(128));
      expect(shiftedPixel.b.toInt(), equals(64));
      expect(shiftedPixel.a.toInt(), equals(128));
      expect(expandedSource.getPixel(0, 0).a.toInt(), equals(0));
    });

    test('shifts existing normalized mask pixels into expanded coordinates',
        () {
      final sourceImage = _sourcePng(4, 4);
      final existingMask = img.Image(width: 4, height: 4);
      img.fill(existingMask, color: img.ColorRgba8(0, 0, 0, 255));
      existingMask.setPixelRgba(1, 2, 255, 255, 255, 255);

      final result = InpaintOutpaintUtils.expand(
        sourceImage: sourceImage,
        existingMask: Uint8List.fromList(img.encodePng(existingMask)),
        edges: const OutpaintEdges(left: 2, top: 1),
        snapTo64: false,
      );

      final expandedMask = img.decodeImage(result.maskImage)!;
      expect(expandedMask.getPixel(3, 3).r.toInt(), equals(255));
      expect(expandedMask.getPixel(2, 1).r.toInt(), equals(0));
    });

    test('snaps expanded dimensions to 64 multiples on right and bottom', () {
      final sourceImage = _sourcePng(1024, 1216);

      final result = InpaintOutpaintUtils.expand(
        sourceImage: sourceImage,
        edges: const OutpaintEdges(
          left: 200,
          top: 200,
          right: 200,
          bottom: 200,
        ),
      );

      expect(result.width, equals(1472));
      expect(result.height, equals(1664));
      expect(result.appliedEdges.left, equals(200));
      expect(result.appliedEdges.top, equals(200));
      expect(result.appliedEdges.right, equals(248));
      expect(result.appliedEdges.bottom, equals(248));
      expect(result.sourceOffsetX, equals(200));
      expect(result.sourceOffsetY, equals(200));
    });

    test('snaps remainders to left and top when requested', () {
      final sourceImage = _sourcePng(1024, 1216);

      final result = InpaintOutpaintUtils.expand(
        sourceImage: sourceImage,
        edges: const OutpaintEdges(
          left: 200,
          top: 200,
          right: 200,
          bottom: 200,
        ),
        horizontalSnapTarget: OutpaintHorizontalSnapTarget.left,
        verticalSnapTarget: OutpaintVerticalSnapTarget.top,
      );

      expect(result.width, equals(1472));
      expect(result.height, equals(1664));
      expect(result.appliedEdges.left, equals(248));
      expect(result.appliedEdges.top, equals(248));
      expect(result.appliedEdges.right, equals(200));
      expect(result.appliedEdges.bottom, equals(200));
      expect(result.sourceOffsetX, equals(248));
      expect(result.sourceOffsetY, equals(248));

      final expandedSource = img.decodeImage(result.sourceImage)!;
      final shiftedSourcePixel = expandedSource.getPixel(248, 248);
      expect(shiftedSourcePixel.r.toInt(), equals(24));
      expect(shiftedSourcePixel.g.toInt(), equals(48));
      expect(shiftedSourcePixel.b.toInt(), equals(72));
      expect(shiftedSourcePixel.a.toInt(), equals(255));
      expect(expandedSource.getPixel(247, 248).a.toInt(), equals(0));
      expect(expandedSource.getPixel(248, 247).a.toInt(), equals(0));

      final expandedMask = img.decodeImage(result.maskImage)!;
      expect(expandedMask.getPixel(248, 248).r.toInt(), equals(0));
      expect(expandedMask.getPixel(1271, 1463).r.toInt(), equals(0));
      expect(expandedMask.getPixel(247, 248).r.toInt(), equals(255));
      expect(expandedMask.getPixel(248, 247).r.toInt(), equals(255));
      expect(expandedMask.getPixel(1272, 248).r.toInt(), equals(255));
      expect(expandedMask.getPixel(248, 1464).r.toInt(), equals(255));
    });

    test('async expansion matches sync expansion result', () async {
      final sourceImage = _sourcePng(128, 96);
      final existingMask = img.Image(width: 128, height: 96);
      img.fill(existingMask, color: img.ColorRgba8(0, 0, 0, 255));
      existingMask.setPixelRgba(4, 5, 255, 255, 255, 255);

      final syncResult = InpaintOutpaintUtils.expand(
        sourceImage: sourceImage,
        existingMask: Uint8List.fromList(img.encodePng(existingMask)),
        edges: const OutpaintEdges(left: 24, top: 10, right: 13, bottom: 9),
        horizontalSnapTarget: OutpaintHorizontalSnapTarget.left,
        verticalSnapTarget: OutpaintVerticalSnapTarget.top,
      );
      final asyncResult = await InpaintOutpaintUtils.expandAsync(
        sourceImage: sourceImage,
        existingMask: Uint8List.fromList(img.encodePng(existingMask)),
        edges: const OutpaintEdges(left: 24, top: 10, right: 13, bottom: 9),
        horizontalSnapTarget: OutpaintHorizontalSnapTarget.left,
        verticalSnapTarget: OutpaintVerticalSnapTarget.top,
      );

      expect(asyncResult.width, syncResult.width);
      expect(asyncResult.height, syncResult.height);
      expect(asyncResult.sourceOffsetX, syncResult.sourceOffsetX);
      expect(asyncResult.sourceOffsetY, syncResult.sourceOffsetY);
      expect(asyncResult.appliedEdges.left, syncResult.appliedEdges.left);
      expect(asyncResult.appliedEdges.top, syncResult.appliedEdges.top);
      expect(asyncResult.appliedEdges.right, syncResult.appliedEdges.right);
      expect(asyncResult.appliedEdges.bottom, syncResult.appliedEdges.bottom);
      expect(asyncResult.sourceImage, syncResult.sourceImage);
      expect(asyncResult.maskImage, syncResult.maskImage);
    });

    test('async expansion can include editor overlay bytes', () async {
      final sourceImage = _sourcePng(128, 96);

      final result = await InpaintOutpaintUtils.expandAsync(
        sourceImage: sourceImage,
        edges: const OutpaintEdges(left: 32),
        includeEditorOverlay: true,
      );

      expect(result.editorOverlayImage, isNotNull);
      final overlay = img.decodeImage(result.editorOverlayImage!)!;
      expect(overlay.width, result.width);
      expect(overlay.height, result.height);
      expect(overlay.getPixel(0, 0).a.toInt(), greaterThan(0));
      expect(
        overlay.getPixel(result.appliedEdges.left, 0).a.toInt(),
        equals(0),
      );
    });

    test('rejects negative outpaint edges', () {
      final sourceImage = _sourcePng(4, 4);

      expect(
        () => InpaintOutpaintUtils.expand(
          sourceImage: sourceImage,
          edges: const OutpaintEdges(left: -1),
          snapTo64: false,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Outpaint edges must be non-negative',
          ),
        ),
      );
    });

    test('rejects existing mask with mismatched dimensions', () {
      final sourceImage = _sourcePng(4, 4);
      final existingMask = _sourcePng(5, 4);

      expect(
        () => InpaintOutpaintUtils.expand(
          sourceImage: sourceImage,
          existingMask: existingMask,
          edges: const OutpaintEdges(),
          snapTo64: false,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Existing mask dimensions must match source image dimensions',
          ),
        ),
      );
    });

    test('rejects invalid source image bytes with decode message', () {
      final malformedPngHeader = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        0x00,
        0x00,
        0x00,
        0x0d,
        0x49,
        0x48,
        0x44,
        0x52,
      ]);

      for (final invalidBytes in [
        Uint8List.fromList([1, 2, 3, 4]),
        malformedPngHeader,
      ]) {
        expect(
          () => InpaintOutpaintUtils.expand(
            sourceImage: invalidBytes,
            edges: const OutpaintEdges(),
            snapTo64: false,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Unable to decode source image',
            ),
          ),
        );
      }
    });

    test('rejects invalid existing mask bytes with decode message', () {
      final sourceImage = _sourcePng(4, 4);
      final malformedPngHeader = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        0x00,
        0x00,
        0x00,
        0x0d,
        0x49,
        0x48,
        0x44,
        0x52,
      ]);

      for (final invalidMask in [
        Uint8List.fromList([1, 2, 3, 4]),
        malformedPngHeader,
      ]) {
        expect(
          () => InpaintOutpaintUtils.expand(
            sourceImage: sourceImage,
            existingMask: invalidMask,
            edges: const OutpaintEdges(),
            snapTo64: false,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Unable to decode existing mask',
            ),
          ),
        );
      }
    });
  });
}

Uint8List _sourcePng(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgba8(24, 48, 72, 255));
  return Uint8List.fromList(img.encodePng(image));
}
