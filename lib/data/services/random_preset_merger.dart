import '../models/prompt/algorithm_config.dart';
import '../models/prompt/random_category.dart';
import '../models/prompt/random_preset.dart';
import '../models/prompt/random_tag_group.dart';

/// Deterministically merges the official preset with a selected user preset.
class RandomPresetMerger {
  const RandomPresetMerger._();

  static RandomPreset merge({
    required RandomPreset officialPreset,
    required RandomPreset customPreset,
  }) {
    final mergedCategories =
        officialPreset.categories.map(_copyCategory).toList();

    for (final customCategory in customPreset.categories) {
      final index = mergedCategories.indexWhere(
        (category) => _sameCategory(category, customCategory),
      );

      if (index == -1) {
        mergedCategories.add(_copyCategory(customCategory));
        continue;
      }

      mergedCategories[index] = _mergeCategory(
        mergedCategories[index],
        customCategory,
      );
    }

    return officialPreset.copyWith(
      id: 'hybrid_${officialPreset.id}_${customPreset.id}',
      name: '${officialPreset.name} + ${customPreset.name}',
      description: customPreset.description ?? officialPreset.description,
      isDefault: false,
      isBasedOnDefault: true,
      algorithmConfig: _mergeAlgorithmConfig(
        customPreset.algorithmConfig,
      ),
      categories: mergedCategories,
      tagGroupMappings: [
        ...officialPreset.tagGroupMappings,
        ...customPreset.tagGroupMappings,
      ],
      poolMappings: [
        ...officialPreset.poolMappings,
        ...customPreset.poolMappings,
      ],
    );
  }

  static AlgorithmConfig _mergeAlgorithmConfig(AlgorithmConfig customConfig) {
    return customConfig.copyWith(
      characterCountConfig: customConfig.characterCountConfig ??
          customConfig.effectiveCharacterCountConfig,
    );
  }

  static RandomCategory _mergeCategory(
    RandomCategory officialCategory,
    RandomCategory customCategory,
  ) {
    final mergedGroups =
        officialCategory.groups.map((g) => g.copyWith()).toList();

    for (final customGroup in customCategory.groups) {
      final index = mergedGroups.indexWhere(
        (group) => _sameGroup(group, customGroup),
      );
      if (index == -1) {
        mergedGroups.add(customGroup.copyWith());
      } else {
        mergedGroups[index] = customGroup.copyWith();
      }
    }

    return officialCategory.copyWith(
      name: customCategory.name,
      emoji: customCategory.emoji,
      enabled: officialCategory.enabled && customCategory.enabled,
      probability: customCategory.probability,
      groupSelectionMode: customCategory.groupSelectionMode,
      groupSelectCount: customCategory.groupSelectCount,
      shuffle: customCategory.shuffle,
      unifiedBracketMin: customCategory.unifiedBracketMin,
      unifiedBracketMax: customCategory.unifiedBracketMax,
      useUnifiedBracket: customCategory.useUnifiedBracket,
      genderRestrictionEnabled: customCategory.genderRestrictionEnabled,
      applicableGenders: customCategory.applicableGenders,
      scope: customCategory.scope,
      groups: mergedGroups,
    );
  }

  static RandomCategory _copyCategory(RandomCategory category) {
    return category.copyWith(
      groups: category.groups.map((group) => group.copyWith()).toList(),
    );
  }

  static bool _sameCategory(RandomCategory left, RandomCategory right) {
    return _categoryKey(left) == _categoryKey(right);
  }

  static String _categoryKey(RandomCategory category) {
    return category.key.trim().isNotEmpty
        ? category.key.trim()
        : category.name.trim();
  }

  static bool _sameGroup(RandomTagGroup left, RandomTagGroup right) {
    if (left.sourceId != null &&
        right.sourceId != null &&
        left.sourceId!.trim().isNotEmpty &&
        right.sourceId!.trim().isNotEmpty &&
        left.sourceId == right.sourceId &&
        left.sourceType == right.sourceType) {
      return true;
    }

    // Name fallback is only for user groups that do not carry stable source ids.
    if (right.sourceId == null || right.sourceId!.trim().isEmpty) {
      return left.name.trim() == right.name.trim();
    }

    return false;
  }
}
