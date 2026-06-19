import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';

enum LocalOnnxModelKind { wd14Tagger, clTagger, clTaggerV2, unknown }

class LocalOnnxModelDescriptor {
  const LocalOnnxModelDescriptor({
    required this.name,
    required this.path,
    required this.kind,
    this.labelsPath,
    this.externalDataPath,
  });

  final String name;
  final String path;
  final LocalOnnxModelKind kind;
  final String? labelsPath;
  final String? externalDataPath;

  bool get isOnnx => p.extension(path).toLowerCase() == '.onnx';
}

final localOnnxModelServiceProvider = Provider<LocalOnnxModelService>((ref) {
  return LocalOnnxModelService(ref.read(localStorageServiceProvider));
});

class LocalOnnxModelService {
  const LocalOnnxModelService(this._storage);

  final LocalStorageService _storage;

  String get taggerDirectory =>
      _storage.getSetting<String>(StorageKeys.onnxTaggerModelDirectory) ?? '';

  Future<void> setTaggerDirectory(String path) async {
    await _storage.setSetting(StorageKeys.onnxTaggerModelDirectory, path);
  }

  Future<List<LocalOnnxModelDescriptor>> scanTaggerModels() {
    return _scanModels(
      taggerDirectory,
      allowedKinds: const {
        LocalOnnxModelKind.wd14Tagger,
        LocalOnnxModelKind.clTagger,
        LocalOnnxModelKind.clTaggerV2,
        LocalOnnxModelKind.unknown,
      },
    );
  }

  Future<List<LocalOnnxModelDescriptor>> _scanModels(
    String directoryPath, {
    required Set<LocalOnnxModelKind> allowedKinds,
  }) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final directory = Directory(trimmed);
    if (!await directory.exists()) {
      return const [];
    }

    final result = <LocalOnnxModelDescriptor>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.onnx') continue;
      if (!_isDirectOrChildFile(
        rootPath: directory.path,
        filePath: entity.path,
      )) {
        continue;
      }

      final kind = await _inferKind(entity.path);
      if (!allowedKinds.contains(kind)) continue;

      result.add(
        LocalOnnxModelDescriptor(
          name: _displayName(directory.path, entity.path),
          path: entity.path,
          kind: kind,
          labelsPath: await _findLabelsFile(entity.path),
          externalDataPath: await _findExternalDataFile(entity.path),
        ),
      );
    }

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  bool _isDirectOrChildFile({
    required String rootPath,
    required String filePath,
  }) {
    final relative = p.relative(filePath, from: rootPath);
    return p.split(relative).length <= 3;
  }

  String _displayName(String rootPath, String filePath) {
    final relative = p.relative(filePath, from: rootPath);
    return p.split(relative).length > 1 ? relative : p.basename(filePath);
  }

  Future<LocalOnnxModelKind> _inferKind(String filePath) async {
    final lower = p.basenameWithoutExtension(filePath).toLowerCase();
    final lowerDirectory = p.basename(p.dirname(filePath)).toLowerCase();
    if (await _hasClTaggerV2Sidecar(filePath) ||
        lowerDirectory.contains('cl_tagger_v2') ||
        lowerDirectory.contains('cl-tagger-v2')) {
      return LocalOnnxModelKind.clTaggerV2;
    }
    if (lower.contains('wd14') ||
        lower.contains('wd-v1-4') ||
        lower.contains('wd-v1-5') ||
        lower.contains('convnext') ||
        lower.contains('vit') ||
        lower.contains('swinv2')) {
      return LocalOnnxModelKind.wd14Tagger;
    }
    if ((lower.contains('cl') && lower.contains('tagger')) ||
        lowerDirectory.contains('cl_tagger')) {
      return LocalOnnxModelKind.clTagger;
    }
    return LocalOnnxModelKind.unknown;
  }

  Future<bool> _hasClTaggerV2Sidecar(String onnxPath) async {
    final directory = p.dirname(onnxPath);
    return File(p.join(directory, 'model_vocabulary.json')).exists();
  }

  Future<String?> _findLabelsFile(String onnxPath) async {
    final base = p.withoutExtension(onnxPath);
    final lowerBaseName = p.basenameWithoutExtension(onnxPath).toLowerCase();
    final directory = p.dirname(onnxPath);

    if (lowerBaseName.contains('cl_tagger')) {
      final mapping = p.join(directory, 'tag_mapping.json');
      if (await File(mapping).exists()) {
        return mapping;
      }
    }

    for (final extension in const ['.csv', '.txt', '.json']) {
      final candidate = '$base$extension';
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    for (final name in const [
      'model_vocabulary.json',
      'selected_tags.csv',
      'tags.csv',
      'labels.csv',
      'labels.txt',
      'classes.txt',
      'tag_mapping.json',
    ]) {
      final candidate = p.join(directory, name);
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<String?> _findExternalDataFile(String onnxPath) async {
    final candidate = '$onnxPath.data';
    if (await File(candidate).exists()) {
      return candidate;
    }
    return null;
  }
}
