import '../models/prompt/algorithm_config.dart';
import '../models/prompt/character_count_config.dart';
import '../models/prompt/prompt_config.dart' as legacy;
import '../models/prompt/random_category.dart';
import '../models/prompt/random_preset.dart';
import '../models/prompt/random_tag_group.dart';
import '../models/prompt/tag_scope.dart';
import '../models/prompt/weighted_tag.dart';

/// Converts the legacy `RandomPromptPreset` tree into the canonical
/// `RandomPreset` structure used by the random configuration screen.
class RandomPromptLegacyAdapter {
  const RandomPromptLegacyAdapter._();

  static RandomPreset fromPreset(legacy.RandomPromptPreset preset) {
    final now = DateTime.now();
    return RandomPreset(
      id: preset.id,
      name: preset.name,
      description: 'Migrated from legacy custom random prompt preset',
      isDefault: preset.isDefault,
      isBasedOnDefault: false,
      version: 2,
      algorithmConfig: const AlgorithmConfig(
        characterCountConfig: CharacterCountConfig(),
      ).copyWith(characterCountConfig: CharacterCountConfig.naiDefault),
      categories: preset.configs.map(_categoryFromConfig).toList(),
      createdAt: preset.createdAt,
      updatedAt: preset.updatedAt ?? now,
    );
  }

  static RandomCategory _categoryFromConfig(legacy.PromptConfig config) {
    return RandomCategory(
      id: config.id,
      name: config.name,
      key: _stableKey(config.name),
      enabled: config.enabled,
      probability:
          config.selectionMode == legacy.SelectionMode.singleProbability
              ? (config.selectProbability ?? 0.5).clamp(0.0, 1.0)
              : 1.0,
      groupSelectionMode: _mapSelectionMode(config.selectionMode),
      groupSelectCount: config.selectCount ?? 1,
      shuffle: config.shuffle,
      scope: TagScope.all,
      groups: [_groupFromConfig(config)],
    );
  }

  static RandomTagGroup _groupFromConfig(
    legacy.PromptConfig config, [
    List<String> parentPath = const [],
  ]) {
    final isNested = config.contentType == legacy.ContentType.nested;
    final path = [...parentPath, config.id];
    return RandomTagGroup(
      id: 'legacy_${path.map(_stableIdSegment).join('_')}',
      name: config.name,
      enabled: config.enabled,
      sourceType: TagGroupSourceType.custom,
      selectionMode: _mapSelectionMode(config.selectionMode),
      multipleNum: config.selectCount ?? 1,
      probability:
          config.selectionMode == legacy.SelectionMode.singleProbability
              ? (config.selectProbability ?? 0.5).clamp(0.0, 1.0)
              : 1.0,
      bracketMin: config.bracketMin,
      bracketMax: config.bracketMax,
      shuffle: config.shuffle,
      nodeType: isNested ? TagGroupNodeType.config : TagGroupNodeType.str,
      tags: isNested
          ? const []
          : config.stringContents
              .map((tag) => WeightedTag.simple(tag, 10, TagSource.custom))
              .toList(),
      children: isNested
          ? config.nestedConfigs
              .map((child) => _groupFromConfig(child, path))
              .toList()
          : const [],
    );
  }

  static SelectionMode _mapSelectionMode(legacy.SelectionMode mode) {
    return switch (mode) {
      legacy.SelectionMode.singleRandom => SelectionMode.single,
      legacy.SelectionMode.singleSequential => SelectionMode.sequential,
      legacy.SelectionMode.singleProbability => SelectionMode.multipleProb,
      legacy.SelectionMode.multipleCount => SelectionMode.multipleNum,
      legacy.SelectionMode.multipleProbability => SelectionMode.multipleProb,
      legacy.SelectionMode.all => SelectionMode.all,
    };
  }

  static String _stableKey(String name) {
    final key = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return key.isEmpty ? 'legacy_category' : 'legacy_$key';
  }

  static String _stableIdSegment(String value) {
    final segment = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return segment.isEmpty ? 'node' : segment;
  }
}
