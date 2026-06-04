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

class OutpaintFrameDelta {
  /// Positive values expand the corresponding edge outward.
  /// Negative values move the edge inward and crop that side.
  final int left;
  final int top;
  final int right;
  final int bottom;

  const OutpaintFrameDelta({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  factory OutpaintFrameDelta.fromExpansionEdges(OutpaintEdges edges) {
    return OutpaintFrameDelta(
      left: edges.left,
      top: edges.top,
      right: edges.right,
      bottom: edges.bottom,
    );
  }

  bool get isEmpty => left == 0 && top == 0 && right == 0 && bottom == 0;

  OutpaintEdges get expansionEdges {
    return OutpaintEdges(
      left: left > 0 ? left : 0,
      top: top > 0 ? top : 0,
      right: right > 0 ? right : 0,
      bottom: bottom > 0 ? bottom : 0,
    );
  }

  OutpaintEdges get cropEdges {
    return OutpaintEdges(
      left: left < 0 ? -left : 0,
      top: top < 0 ? -top : 0,
      right: right < 0 ? -right : 0,
      bottom: bottom < 0 ? -bottom : 0,
    );
  }
}

enum OutpaintHorizontalSnapTarget { left, right }

enum OutpaintVerticalSnapTarget { top, bottom }

class OutpaintFrameResolvedGeometry {
  final int sourceWidth;
  final int sourceHeight;
  final int requestedWidth;
  final int requestedHeight;
  final int width;
  final int height;
  final int requestedFrameLeft;
  final int requestedFrameTop;
  final int requestedFrameRight;
  final int requestedFrameBottom;
  final int appliedFrameLeft;
  final int appliedFrameTop;
  final int appliedFrameRight;
  final int appliedFrameBottom;
  final OutpaintFrameDelta requestedDelta;
  final OutpaintEdges requestedExpansionEdges;
  final OutpaintEdges requestedCropEdges;
  final OutpaintEdges appliedExpansionEdges;
  final OutpaintEdges appliedCropEdges;

  const OutpaintFrameResolvedGeometry({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.requestedWidth,
    required this.requestedHeight,
    required this.width,
    required this.height,
    required this.requestedFrameLeft,
    required this.requestedFrameTop,
    required this.requestedFrameRight,
    required this.requestedFrameBottom,
    required this.appliedFrameLeft,
    required this.appliedFrameTop,
    required this.appliedFrameRight,
    required this.appliedFrameBottom,
    required this.requestedDelta,
    required this.requestedExpansionEdges,
    required this.requestedCropEdges,
    required this.appliedExpansionEdges,
    required this.appliedCropEdges,
  });

  bool get hasAppliedChange =>
      !appliedExpansionEdges.isEmpty || !appliedCropEdges.isEmpty;
}

class OutpaintResolvedGeometry {
  final int sourceWidth;
  final int sourceHeight;
  final int requestedWidth;
  final int requestedHeight;
  final int width;
  final int height;
  final int sourceOffsetX;
  final int sourceOffsetY;
  final OutpaintEdges requestedEdges;
  final OutpaintEdges appliedEdges;

  const OutpaintResolvedGeometry({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.requestedWidth,
    required this.requestedHeight,
    required this.width,
    required this.height,
    required this.sourceOffsetX,
    required this.sourceOffsetY,
    required this.requestedEdges,
    required this.appliedEdges,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is OutpaintResolvedGeometry &&
            sourceWidth == other.sourceWidth &&
            sourceHeight == other.sourceHeight &&
            requestedWidth == other.requestedWidth &&
            requestedHeight == other.requestedHeight &&
            width == other.width &&
            height == other.height &&
            sourceOffsetX == other.sourceOffsetX &&
            sourceOffsetY == other.sourceOffsetY &&
            requestedEdges.left == other.requestedEdges.left &&
            requestedEdges.top == other.requestedEdges.top &&
            requestedEdges.right == other.requestedEdges.right &&
            requestedEdges.bottom == other.requestedEdges.bottom &&
            appliedEdges.left == other.appliedEdges.left &&
            appliedEdges.top == other.appliedEdges.top &&
            appliedEdges.right == other.appliedEdges.right &&
            appliedEdges.bottom == other.appliedEdges.bottom;
  }

  @override
  int get hashCode => Object.hashAll([
        sourceWidth,
        sourceHeight,
        requestedWidth,
        requestedHeight,
        width,
        height,
        sourceOffsetX,
        sourceOffsetY,
        requestedEdges.left,
        requestedEdges.top,
        requestedEdges.right,
        requestedEdges.bottom,
        appliedEdges.left,
        appliedEdges.top,
        appliedEdges.right,
        appliedEdges.bottom,
      ]);
}

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

class OutpaintFrameResizeResult {
  final Uint8List sourceImage;
  final Uint8List maskImage;
  final Uint8List? editorOverlayImage;
  final int width;
  final int height;
  final OutpaintFrameDelta requestedDelta;
  final OutpaintEdges requestedExpansionEdges;
  final OutpaintEdges requestedCropEdges;
  final OutpaintEdges appliedExpansionEdges;
  final OutpaintEdges appliedCropEdges;

  const OutpaintFrameResizeResult({
    required this.sourceImage,
    required this.maskImage,
    this.editorOverlayImage,
    required this.width,
    required this.height,
    required this.requestedDelta,
    required this.requestedExpansionEdges,
    required this.requestedCropEdges,
    required this.appliedExpansionEdges,
    required this.appliedCropEdges,
  });
}

class InpaintOutpaintUtils {
  InpaintOutpaintUtils._();

  static const int _maxDimension = 4096;
  static const int _snapSize = 64;

  static OutpaintFrameResizeResult resizeFrame({
    required Uint8List sourceImage,
    Uint8List? existingMask,
    required OutpaintFrameDelta delta,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
    bool includeEditorOverlay = false,
    int editorOverlayAlpha = 140,
  }) {
    final decodedSource = _decodeSourceImage(sourceImage);
    if (decodedSource == null) {
      throw const FormatException('Unable to decode source image');
    }
    final source =
        decodedSource.convert(format: img.Format.uint8, numChannels: 4);
    final geometry = resolveFrameGeometry(
      sourceWidth: source.width,
      sourceHeight: source.height,
      delta: delta,
      snapTo64: snapTo64,
      horizontalSnapTarget: horizontalSnapTarget,
      verticalSnapTarget: verticalSnapTarget,
      validateMaxDimension: false,
    );

    final decodedExistingMask = _decodeExistingMask(
      existingMask,
      source.width,
      source.height,
    );

    _validateExpandedDimensions(geometry.width, geometry.height);

    final resizedSource = _createResizedSource(source, geometry);
    final resizedMask = _createResizedMask(
      source,
      decodedExistingMask,
      geometry,
    );
    final editorOverlay = includeEditorOverlay
        ? _createEditorOverlay(resizedMask, overlayAlpha: editorOverlayAlpha)
        : null;

    return OutpaintFrameResizeResult(
      sourceImage: Uint8List.fromList(img.encodePng(resizedSource)),
      maskImage: Uint8List.fromList(img.encodePng(resizedMask)),
      editorOverlayImage: editorOverlay == null
          ? null
          : Uint8List.fromList(img.encodePng(editorOverlay)),
      width: geometry.width,
      height: geometry.height,
      requestedDelta: geometry.requestedDelta,
      requestedExpansionEdges: geometry.requestedExpansionEdges,
      requestedCropEdges: geometry.requestedCropEdges,
      appliedExpansionEdges: geometry.appliedExpansionEdges,
      appliedCropEdges: geometry.appliedCropEdges,
    );
  }

  static Future<OutpaintFrameResizeResult> resizeFrameAsync({
    required Uint8List sourceImage,
    Uint8List? existingMask,
    required OutpaintFrameDelta delta,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
    bool includeEditorOverlay = false,
    int editorOverlayAlpha = 140,
  }) {
    return Isolate.run(
      () => resizeFrame(
        sourceImage: sourceImage,
        existingMask: existingMask,
        delta: delta,
        snapTo64: snapTo64,
        horizontalSnapTarget: horizontalSnapTarget,
        verticalSnapTarget: verticalSnapTarget,
        includeEditorOverlay: includeEditorOverlay,
        editorOverlayAlpha: editorOverlayAlpha,
      ),
    );
  }

  static OutpaintFrameResolvedGeometry resolveFrameGeometry({
    required int sourceWidth,
    required int sourceHeight,
    required OutpaintFrameDelta delta,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
    bool validateMaxDimension = true,
  }) {
    final requestedFrameLeft = -delta.left;
    final requestedFrameTop = -delta.top;
    final requestedFrameRight = sourceWidth + delta.right;
    final requestedFrameBottom = sourceHeight + delta.bottom;
    final requestedWidth = requestedFrameRight - requestedFrameLeft;
    final requestedHeight = requestedFrameBottom - requestedFrameTop;

    final width = _resolveFrameDimension(
      requestedSize: requestedWidth,
      sourceSize: sourceWidth,
      snapTo64: snapTo64,
    );
    final height = _resolveFrameDimension(
      requestedSize: requestedHeight,
      sourceSize: sourceHeight,
      snapTo64: snapTo64,
    );

    final appliedFrameLeft =
        horizontalSnapTarget == OutpaintHorizontalSnapTarget.left
            ? requestedFrameRight - width
            : requestedFrameLeft;
    final appliedFrameRight =
        horizontalSnapTarget == OutpaintHorizontalSnapTarget.left
            ? requestedFrameRight
            : requestedFrameLeft + width;
    final appliedFrameTop = verticalSnapTarget == OutpaintVerticalSnapTarget.top
        ? requestedFrameBottom - height
        : requestedFrameTop;
    final appliedFrameBottom =
        verticalSnapTarget == OutpaintVerticalSnapTarget.top
            ? requestedFrameBottom
            : requestedFrameTop + height;

    if (validateMaxDimension) {
      _validateExpandedDimensions(width, height);
    }

    final requestedExpansionEdges = delta.expansionEdges;
    final requestedCropEdges = delta.cropEdges;
    final appliedExpansionEdges = OutpaintEdges(
      left: appliedFrameLeft < 0 ? -appliedFrameLeft : 0,
      top: appliedFrameTop < 0 ? -appliedFrameTop : 0,
      right:
          appliedFrameRight > sourceWidth ? appliedFrameRight - sourceWidth : 0,
      bottom: appliedFrameBottom > sourceHeight
          ? appliedFrameBottom - sourceHeight
          : 0,
    );
    final appliedCropEdges = OutpaintEdges(
      left: appliedFrameLeft > 0 ? appliedFrameLeft : 0,
      top: appliedFrameTop > 0 ? appliedFrameTop : 0,
      right:
          appliedFrameRight < sourceWidth ? sourceWidth - appliedFrameRight : 0,
      bottom: appliedFrameBottom < sourceHeight
          ? sourceHeight - appliedFrameBottom
          : 0,
    );

    return OutpaintFrameResolvedGeometry(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      requestedWidth: requestedWidth,
      requestedHeight: requestedHeight,
      width: width,
      height: height,
      requestedFrameLeft: requestedFrameLeft,
      requestedFrameTop: requestedFrameTop,
      requestedFrameRight: requestedFrameRight,
      requestedFrameBottom: requestedFrameBottom,
      appliedFrameLeft: appliedFrameLeft,
      appliedFrameTop: appliedFrameTop,
      appliedFrameRight: appliedFrameRight,
      appliedFrameBottom: appliedFrameBottom,
      requestedDelta: delta,
      requestedExpansionEdges: requestedExpansionEdges,
      requestedCropEdges: requestedCropEdges,
      appliedExpansionEdges: appliedExpansionEdges,
      appliedCropEdges: appliedCropEdges,
    );
  }

  static OutpaintFrameResolvedGeometry? tryResolveFrameGeometry({
    required int sourceWidth,
    required int sourceHeight,
    required OutpaintFrameDelta delta,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
  }) {
    try {
      return resolveFrameGeometry(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        delta: delta,
        snapTo64: snapTo64,
        horizontalSnapTarget: horizontalSnapTarget,
        verticalSnapTarget: verticalSnapTarget,
      );
    } on ArgumentError {
      return null;
    }
  }

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
    final geometry = resolveExpansionGeometry(
      sourceWidth: source.width,
      sourceHeight: source.height,
      edges: edges,
      snapTo64: snapTo64,
      horizontalSnapTarget: horizontalSnapTarget,
      verticalSnapTarget: verticalSnapTarget,
      validateMaxDimension: false,
    );

    final decodedExistingMask = _decodeExistingMask(
      existingMask,
      source.width,
      source.height,
    );

    _validateExpandedDimensions(geometry.width, geometry.height);

    final expandedSource = _createExpandedSource(
      source,
      geometry.width,
      geometry.height,
      geometry.appliedEdges,
    );
    final expandedMask = _createExpandedMask(
      source,
      decodedExistingMask,
      geometry.width,
      geometry.height,
      geometry.appliedEdges,
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
      width: geometry.width,
      height: geometry.height,
      sourceOffsetX: geometry.sourceOffsetX,
      sourceOffsetY: geometry.sourceOffsetY,
      requestedEdges: geometry.requestedEdges,
      appliedEdges: geometry.appliedEdges,
    );
  }

  static OutpaintResolvedGeometry resolveExpansionGeometry({
    required int sourceWidth,
    required int sourceHeight,
    required OutpaintEdges edges,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
    bool validateMaxDimension = true,
  }) {
    _validateEdges(edges);

    final requestedWidth = sourceWidth + edges.left + edges.right;
    final requestedHeight = sourceHeight + edges.top + edges.bottom;
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

    if (validateMaxDimension) {
      _validateExpandedDimensions(width, height);
    }

    final appliedEdges = OutpaintEdges(
      left: appliedLeft,
      top: appliedTop,
      right: appliedRight,
      bottom: appliedBottom,
    );

    return OutpaintResolvedGeometry(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      requestedWidth: requestedWidth,
      requestedHeight: requestedHeight,
      width: width,
      height: height,
      sourceOffsetX: appliedLeft,
      sourceOffsetY: appliedTop,
      requestedEdges: edges,
      appliedEdges: appliedEdges,
    );
  }

  static OutpaintResolvedGeometry? tryResolveExpansionGeometry({
    required int sourceWidth,
    required int sourceHeight,
    required OutpaintEdges edges,
    bool snapTo64 = true,
    OutpaintHorizontalSnapTarget horizontalSnapTarget =
        OutpaintHorizontalSnapTarget.right,
    OutpaintVerticalSnapTarget verticalSnapTarget =
        OutpaintVerticalSnapTarget.bottom,
  }) {
    try {
      return resolveExpansionGeometry(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        edges: edges,
        snapTo64: snapTo64,
        horizontalSnapTarget: horizontalSnapTarget,
        verticalSnapTarget: verticalSnapTarget,
      );
    } on ArgumentError {
      return null;
    }
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

  static void _validateExpandedDimensions(int width, int height) {
    if (width > _maxDimension || height > _maxDimension) {
      throw ArgumentError('Expanded image dimensions exceed 4096');
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

  static int _resolveFrameDimension({
    required int requestedSize,
    required int sourceSize,
    required bool snapTo64,
  }) {
    if (requestedSize > _maxDimension) {
      return requestedSize;
    }
    final clamped = requestedSize.clamp(_snapSize, _maxDimension).toInt();
    if (!snapTo64) {
      return clamped;
    }
    if (requestedSize < sourceSize) {
      final floored = (clamped ~/ _snapSize) * _snapSize;
      return floored.clamp(_snapSize, _maxDimension).toInt();
    }
    return clamped + _snapRemainder(clamped);
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

  static img.Image _createResizedSource(
    img.Image source,
    OutpaintFrameResolvedGeometry geometry,
  ) {
    final resized = img.Image(
      width: geometry.width,
      height: geometry.height,
      numChannels: 4,
    );
    img.fill(resized, color: img.ColorRgba8(0, 0, 0, 0));

    for (var y = 0; y < geometry.height; y++) {
      final sourceY = y + geometry.appliedFrameTop;
      if (sourceY < 0 || sourceY >= source.height) {
        continue;
      }
      for (var x = 0; x < geometry.width; x++) {
        final sourceX = x + geometry.appliedFrameLeft;
        if (sourceX < 0 || sourceX >= source.width) {
          continue;
        }
        final pixel = source.getPixel(sourceX, sourceY);
        resized.setPixelRgba(
          x,
          y,
          pixel.r,
          pixel.g,
          pixel.b,
          pixel.a,
        );
      }
    }

    return resized;
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

  static img.Image _createResizedMask(
    img.Image source,
    img.Image? existingMask,
    OutpaintFrameResolvedGeometry geometry,
  ) {
    final mask = img.Image(
      width: geometry.width,
      height: geometry.height,
      numChannels: 4,
    );
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));

    for (var y = 0; y < geometry.height; y++) {
      final sourceY = y + geometry.appliedFrameTop;
      final outsideSourceY = sourceY < 0 || sourceY >= source.height;
      for (var x = 0; x < geometry.width; x++) {
        final sourceX = x + geometry.appliedFrameLeft;
        final outsideSource =
            outsideSourceY || sourceX < 0 || sourceX >= source.width;
        if (outsideSource) {
          mask.setPixelRgba(x, y, 255, 255, 255, 255);
          continue;
        }
        if (existingMask != null) {
          final pixel = existingMask.getPixel(sourceX, sourceY);
          if (pixel.r.toInt() > 0) {
            mask.setPixelRgba(x, y, 255, 255, 255, 255);
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
