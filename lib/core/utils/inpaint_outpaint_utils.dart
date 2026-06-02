import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/inpaint_mask_utils.dart';

class OutpaintEdges {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const OutpaintEdges({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  bool get isEmpty => left == 0 && top == 0 && right == 0 && bottom == 0;
}

enum OutpaintHorizontalSnapTarget { left, right }

enum OutpaintVerticalSnapTarget { top, bottom }

class OutpaintExpansionResult {
  final Uint8List sourceImage;
  final Uint8List maskImage;
  final Uint8List? editorOverlayImage;
  final int width;
  final int height;
  final int sourceOffsetX;
  final int sourceOffsetY;
  final OutpaintEdges requestedEdges;
  final OutpaintEdges appliedEdges;

  const OutpaintExpansionResult({
    required this.sourceImage,
    required this.maskImage,
    this.editorOverlayImage,
    required this.width,
    required this.height,
    required this.sourceOffsetX,
    required this.sourceOffsetY,
    required this.requestedEdges,
    required this.appliedEdges,
  });
}

class InpaintOutpaintUtils {
  InpaintOutpaintUtils._();

  static const int _maxDimension = 4096;
  static const int _snapSize = 64;

  static OutpaintExpansionResult expand({
    required Uint8List sourceImage,
    Uint8List? existingMask,
    required OutpaintEdges edges,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
    bool includeEditorOverlay = false,
    int editorOverlayAlpha = 140,
  }) {
    _validateEdges(edges);

    final decodedSource = _decodeSourceImage(sourceImage);
    if (decodedSource == null) {
      throw const FormatException('Unable to decode source image');
    }
    final source =
        decodedSource.convert(format: img.Format.uint8, numChannels: 4);

    final decodedExistingMask = _decodeExistingMask(
      existingMask,
      source.width,
      source.height,
    );

    final requestedWidth = source.width + edges.left + edges.right;
    final requestedHeight = source.height + edges.top + edges.bottom;
    var appliedLeft = edges.left;
    var appliedTop = edges.top;
    var appliedRight = edges.right;
    var appliedBottom = edges.bottom;

    var width = requestedWidth;
    var height = requestedHeight;
    if (snapTo64) {
      final widthRemainder = _snapRemainder(width);
      width += widthRemainder;
      if (horizontalSnapTarget == OutpaintHorizontalSnapTarget.left) {
        appliedLeft += widthRemainder;
      } else {
        appliedRight += widthRemainder;
      }

      final heightRemainder = _snapRemainder(height);
      height += heightRemainder;
      if (verticalSnapTarget == OutpaintVerticalSnapTarget.top) {
        appliedTop += heightRemainder;
      } else {
        appliedBottom += heightRemainder;
      }
    }

    if (width > _maxDimension || height > _maxDimension) {
      throw ArgumentError('Expanded image dimensions exceed 4096');
    }

    final appliedEdges = OutpaintEdges(
      left: appliedLeft,
      top: appliedTop,
      right: appliedRight,
      bottom: appliedBottom,
    );
    final expandedSource = _createExpandedSource(
      source,
      width,
      height,
      appliedEdges,
    );
    final expandedMask = _createExpandedMask(
      source,
      decodedExistingMask,
      width,
      height,
      appliedEdges,
    );
    final editorOverlay = includeEditorOverlay
        ? _createEditorOverlay(expandedMask, overlayAlpha: editorOverlayAlpha)
        : null;

    return OutpaintExpansionResult(
      sourceImage: Uint8List.fromList(img.encodePng(expandedSource)),
      maskImage: Uint8List.fromList(img.encodePng(expandedMask)),
      editorOverlayImage: editorOverlay == null
          ? null
          : Uint8List.fromList(img.encodePng(editorOverlay)),
      width: width,
      height: height,
      sourceOffsetX: appliedEdges.left,
      sourceOffsetY: appliedEdges.top,
      requestedEdges: edges,
      appliedEdges: appliedEdges,
    );
  }

  static Future<OutpaintExpansionResult> expandAsync({
    required Uint8List sourceImage,
    Uint8List? existingMask,
    required OutpaintEdges edges,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
    bool includeEditorOverlay = false,
    int editorOverlayAlpha = 140,
  }) {
    return Isolate.run(
      () => expand(
        sourceImage: sourceImage,
        existingMask: existingMask,
        edges: edges,
        snapTo64: snapTo64,
        horizontalSnapTarget: horizontalSnapTarget,
        verticalSnapTarget: verticalSnapTarget,
        includeEditorOverlay: includeEditorOverlay,
        editorOverlayAlpha: editorOverlayAlpha,
      ),
    );
  }

  static void _validateEdges(OutpaintEdges edges) {
    if (edges.left < 0 ||
        edges.top < 0 ||
        edges.right < 0 ||
        edges.bottom < 0) {
      throw ArgumentError('Outpaint edges must be non-negative');
    }
  }

  static img.Image? _decodeSourceImage(Uint8List sourceImage) {
    try {
      return img.decodeImage(sourceImage);
    } catch (_) {
      throw const FormatException('Unable to decode source image');
    }
  }

  static img.Image? _decodeExistingMask(
    Uint8List? existingMask,
    int sourceWidth,
    int sourceHeight,
  ) {
    if (existingMask == null) {
      return null;
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(existingMask);
    } catch (_) {
      throw const FormatException('Unable to decode existing mask');
    }
    if (decoded == null) {
      throw const FormatException('Unable to decode existing mask');
    }
    if (decoded.width != sourceWidth || decoded.height != sourceHeight) {
      throw ArgumentError(
        'Existing mask dimensions must match source image dimensions',
      );
    }

    final normalized = InpaintMaskUtils.normalizeMaskBytes(existingMask);
    try {
      return img.decodeImage(normalized);
    } catch (_) {
      throw const FormatException('Unable to decode existing mask');
    }
  }

  static int _snapRemainder(int value) {
    return (_snapSize - value % _snapSize) % _snapSize;
  }

  static img.Image _createExpandedSource(
    img.Image source,
    int width,
    int height,
    OutpaintEdges appliedEdges,
  ) {
    final expanded = img.Image(width: width, height: height, numChannels: 4);
    img.fill(expanded, color: img.ColorRgba8(0, 0, 0, 0));

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final pixel = source.getPixel(x, y);
        expanded.setPixelRgba(
          x + appliedEdges.left,
          y + appliedEdges.top,
          pixel.r,
          pixel.g,
          pixel.b,
          pixel.a,
        );
      }
    }

    return expanded;
  }

  static img.Image _createExpandedMask(
    img.Image source,
    img.Image? existingMask,
    int width,
    int height,
    OutpaintEdges appliedEdges,
  ) {
    final mask = img.Image(width: width, height: height, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));

    final sourceLeft = appliedEdges.left;
    final sourceTop = appliedEdges.top;
    final sourceRight = sourceLeft + source.width;
    final sourceBottom = sourceTop + source.height;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final outsideSource = x < sourceLeft ||
            x >= sourceRight ||
            y < sourceTop ||
            y >= sourceBottom;
        if (outsideSource) {
          mask.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }

    if (existingMask != null) {
      for (var y = 0; y < existingMask.height; y++) {
        for (var x = 0; x < existingMask.width; x++) {
          final pixel = existingMask.getPixel(x, y);
          if (pixel.r.toInt() > 0) {
            mask.setPixelRgba(
              x + appliedEdges.left,
              y + appliedEdges.top,
              255,
              255,
              255,
              255,
            );
          }
        }
      }
    }

    return mask;
  }

  static img.Image _createEditorOverlay(
    img.Image mask, {
    required int overlayAlpha,
  }) {
    final overlay = img.Image(
      width: mask.width,
      height: mask.height,
      numChannels: 4,
    );
    img.fill(overlay, color: img.ColorRgba8(0, 0, 0, 0));

    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (mask.getPixel(x, y).r.toInt() > 0) {
          overlay.setPixelRgba(x, y, 96, 170, 255, overlayAlpha);
        }
      }
    }

    return overlay;
  }
}
