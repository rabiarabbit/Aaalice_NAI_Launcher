import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;

import 'inpaint_mask_utils.dart';

class HardEdgeMaskExportInput {
  const HardEdgeMaskExportInput({
    required this.width,
    required this.height,
    required this.strokes,
    required this.baseMasks,
    required this.additionalRects,
  });

  final int width;
  final int height;
  final List<HardEdgeMaskStroke> strokes;
  final List<HardEdgeMaskBaseImage> baseMasks;
  final List<Rect> additionalRects;
}

class HardEdgeMaskStroke {
  const HardEdgeMaskStroke({
    required this.points,
    required this.size,
    required this.isEraser,
  });

  final List<Offset> points;
  final double size;
  final bool isEraser;
}

class HardEdgeMaskBaseImage {
  const HardEdgeMaskBaseImage({
    required this.bytes,
    required this.offsetX,
    required this.offsetY,
  });

  final Uint8List bytes;
  final int offsetX;
  final int offsetY;
}

class HardEdgeMaskExporter {
  const HardEdgeMaskExporter._();

  static Future<Uint8List> exportAsync(HardEdgeMaskExportInput input) {
    return Isolate.run(() => export(input));
  }

  static Uint8List export(HardEdgeMaskExportInput input) {
    if (input.width <= 0 || input.height <= 0) {
      throw ArgumentError('Mask dimensions must be positive.');
    }

    final mask = img.Image(
      width: input.width,
      height: input.height,
      numChannels: 4,
    );
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));

    for (final baseMask in input.baseMasks) {
      _pasteBaseMask(mask, baseMask);
    }
    for (final rect in input.additionalRects) {
      _fillRect(mask, rect);
    }
    for (final stroke in input.strokes) {
      _drawStroke(mask, stroke);
    }

    return InpaintMaskUtils.normalizeMaskBytes(
      Uint8List.fromList(img.encodePng(mask)),
    );
  }

  static void _pasteBaseMask(
    img.Image mask,
    HardEdgeMaskBaseImage baseMask,
  ) {
    final normalizedBytes = InpaintMaskUtils.normalizeMaskBytes(baseMask.bytes);
    final base = img.decodeImage(normalizedBytes);
    if (base == null) {
      return;
    }

    for (var y = 0; y < base.height; y++) {
      final targetY = y + baseMask.offsetY;
      if (targetY < 0 || targetY >= mask.height) {
        continue;
      }

      for (var x = 0; x < base.width; x++) {
        final targetX = x + baseMask.offsetX;
        if (targetX < 0 || targetX >= mask.width) {
          continue;
        }

        final pixel = base.getPixel(x, y);
        if (pixel.r.toInt() > 0) {
          _setMaskPixel(mask, targetX, targetY, masked: true);
        }
      }
    }
  }

  static void _fillRect(img.Image mask, Rect rect) {
    final left = rect.left.floor().clamp(0, mask.width).toInt();
    final top = rect.top.floor().clamp(0, mask.height).toInt();
    final right = rect.right.ceil().clamp(0, mask.width).toInt();
    final bottom = rect.bottom.ceil().clamp(0, mask.height).toInt();

    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        _setMaskPixel(mask, x, y, masked: true);
      }
    }
  }

  static void _drawStroke(img.Image mask, HardEdgeMaskStroke stroke) {
    if (stroke.points.isEmpty || stroke.size <= 0) {
      return;
    }

    if (stroke.points.length == 1) {
      _drawDisc(
        mask,
        stroke.points.first,
        stroke.size,
        masked: !stroke.isEraser,
      );
      return;
    }

    for (var i = 0; i < stroke.points.length - 1; i++) {
      _drawSegment(
        mask,
        stroke.points[i],
        stroke.points[i + 1],
        stroke.size,
        masked: !stroke.isEraser,
      );
    }
  }

  static void _drawSegment(
    img.Image mask,
    Offset start,
    Offset end,
    double size, {
    required bool masked,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final steps = math.max(dx.abs(), dy.abs()).ceil();
    if (steps == 0) {
      _drawDisc(mask, start, size, masked: masked);
      return;
    }

    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      _drawDisc(
        mask,
        Offset(start.dx + dx * t, start.dy + dy * t),
        size,
        masked: masked,
      );
    }
  }

  static void _drawDisc(
    img.Image mask,
    Offset center,
    double size, {
    required bool masked,
  }) {
    final radius = size / 2;
    final radiusSquared = radius * radius;
    final left = (center.dx - radius).floor().clamp(0, mask.width - 1).toInt();
    final top = (center.dy - radius).floor().clamp(0, mask.height - 1).toInt();
    final right = (center.dx + radius).ceil().clamp(0, mask.width - 1).toInt();
    final bottom =
        (center.dy + radius).ceil().clamp(0, mask.height - 1).toInt();

    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        final pixelCenterX = x + 0.5;
        final pixelCenterY = y + 0.5;
        final distanceX = pixelCenterX - center.dx;
        final distanceY = pixelCenterY - center.dy;
        if (distanceX * distanceX + distanceY * distanceY <= radiusSquared) {
          _setMaskPixel(mask, x, y, masked: masked);
        }
      }
    }
  }

  static void _setMaskPixel(
    img.Image mask,
    int x,
    int y, {
    required bool masked,
  }) {
    if (x < 0 || x >= mask.width || y < 0 || y >= mask.height) {
      return;
    }

    final value = masked ? 255 : 0;
    mask.setPixelRgba(x, y, value, value, value, 255);
  }
}
