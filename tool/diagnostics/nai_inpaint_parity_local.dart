import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/inpaint_mask_utils.dart';

const _width = 256;
const _height = 192;

void main(List<String> args) {
  final outputDir = Directory(
    args.isNotEmpty ? args.first : 'build/diagnostics/nai_inpaint_parity',
  );
  outputDir.createSync(recursive: true);

  final source = _buildSourceImage();
  final generated = _buildGeneratedImage();
  final alphaMask = _buildMask(alphaMask: true);
  final bwMask = _buildMask(alphaMask: false);

  final sourceBytes = _writePng(outputDir, 'source.png', source);
  final generatedBytes = _writePng(outputDir, 'generated.png', generated);
  final alphaMaskBytes = _writePng(outputDir, 'mask_alpha.png', alphaMask);
  final bwMaskBytes = _writePng(outputDir, 'mask_bw.png', bwMask);

  _writeLocalOutputs(
    outputDir: outputDir,
    label: 'alpha',
    sourceBytes: sourceBytes,
    generatedBytes: generatedBytes,
    maskBytes: alphaMaskBytes,
  );
  _writeLocalOutputs(
    outputDir: outputDir,
    label: 'bw',
    sourceBytes: sourceBytes,
    generatedBytes: generatedBytes,
    maskBytes: bwMaskBytes,
  );

  final officialCompositeMask =
      File('${outputDir.path}/official_composite_mask.png');
  if (officialCompositeMask.existsSync()) {
    final finalWithOfficialMask = InpaintMaskUtils.compositeGeneratedImage(
      sourceImage: sourceBytes,
      maskImage: officialCompositeMask.readAsBytesSync(),
      generatedImage: generatedBytes,
      normalizeMask: false,
    );
    File('${outputDir.path}/local_final_with_official_mask.png')
        .writeAsBytesSync(finalWithOfficialMask);
  }

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'outputDir': outputDir.absolute.path,
      'width': _width,
      'height': _height,
      'inputs': [
        'source.png',
        'generated.png',
        'mask_alpha.png',
        'mask_bw.png',
      ],
      'localOutputs': [
        'local_request_mask_alpha.png',
        'local_request_mask_bw.png',
        'local_composite_mask_alpha.png',
        'local_composite_mask_bw.png',
        'local_final_alpha.png',
        'local_final_bw.png',
      ],
    }),
  );
}

void _writeLocalOutputs({
  required Directory outputDir,
  required String label,
  required Uint8List sourceBytes,
  required Uint8List generatedBytes,
  required Uint8List maskBytes,
}) {
  final requestMask = InpaintMaskUtils.prepareNovelAiRequestMaskBytes(
    maskBytes,
    targetWidth: _width,
    targetHeight: _height,
  );
  File('${outputDir.path}/local_request_mask_$label.png')
      .writeAsBytesSync(requestMask);

  final compositeMask =
      InpaintMaskUtils.prepareGeneratedImageCompositeMaskBytes(
    maskBytes,
    targetWidth: _width,
    targetHeight: _height,
  );
  File('${outputDir.path}/local_composite_mask_$label.png')
      .writeAsBytesSync(compositeMask);

  final finalImage = InpaintMaskUtils.compositeGeneratedImage(
    sourceImage: sourceBytes,
    maskImage: compositeMask,
    generatedImage: generatedBytes,
    normalizeMask: false,
  );
  File('${outputDir.path}/local_final_$label.png').writeAsBytesSync(finalImage);
}

Uint8List _writePng(Directory outputDir, String name, img.Image image) {
  final bytes = Uint8List.fromList(img.encodePng(image));
  File('${outputDir.path}/$name').writeAsBytesSync(bytes);
  return bytes;
}

img.Image _buildSourceImage() {
  final image = img.Image(width: _width, height: _height, numChannels: 4);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final r = (24 + x * 0.62 + y * 0.10).round().clamp(0, 255);
      final g = (42 + y * 0.72 + 18 * math.sin(x / 19)).round().clamp(0, 255);
      final b = (82 + x * 0.18 + y * 0.34).round().clamp(0, 255);
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return image;
}

img.Image _buildGeneratedImage() {
  final image = img.Image(width: _width, height: _height, numChannels: 4);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final r = (190 + 28 * math.sin((x + y) / 17)).round().clamp(0, 255);
      final g = (98 + x * 0.26 + 20 * math.cos(y / 15)).round().clamp(0, 255);
      final b = (142 + y * 0.41 + 24 * math.sin(x / 13)).round().clamp(0, 255);
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return image;
}

img.Image _buildMask({required bool alphaMask}) {
  final image = img.Image(width: _width, height: _height, numChannels: 4);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final masked = _isMasked(x, y);
      if (alphaMask) {
        image.setPixelRgba(x, y, 255, 255, 255, masked ? 255 : 0);
      } else {
        final value = masked ? 255 : 0;
        image.setPixelRgba(x, y, value, value, value, 255);
      }
    }
  }
  return image;
}

bool _isMasked(int x, int y) {
  final wobble = 1 +
      0.13 * math.sin(y / 6.0) +
      0.08 * math.cos(x / 8.0) +
      0.05 * math.sin((x + y) / 9.0);
  final dx = (x - 126) / 48;
  final dy = (y - 92) / 31;
  final blob = dx * dx + dy * dy < wobble;
  final leftPatch = x >= 34 && x <= 76 && y >= 48 && y <= 86;
  final thinStroke =
      (x - y).abs() <= 2 && x >= 148 && x <= 206 && y >= 40 && y <= 98;
  final lowerPatch = x >= 92 && x <= 146 && y >= 132 && y <= 154;
  return blob || leftPatch || thinStroke || lowerPatch;
}
