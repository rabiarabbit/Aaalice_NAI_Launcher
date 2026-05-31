import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/prompt/algorithm_config.dart';
import 'package:nai_launcher/data/models/prompt/character_count_config.dart';
import 'package:nai_launcher/data/models/prompt/random_category.dart';
import 'package:nai_launcher/data/models/prompt/random_preset.dart';
import 'package:nai_launcher/data/models/prompt/random_tag_group.dart';
import 'package:nai_launcher/data/models/prompt/tag_scope.dart';
import 'package:nai_launcher/data/models/prompt/weighted_tag.dart';
import 'package:nai_launcher/data/services/random_preset_merger.dart';

void main() {
  test('hybrid merge replaces matching groups and appends new categories', () {
    final official = _preset(
      id: 'official',
      isDefault: true,
      categories: [
        _category(
          id: 'hair',
          key: 'hair',
          groups: [
            _group(
              id: 'official_hair',
              name: 'Hair',
              sourceId: 'hairColor',
              tags: ['blue hair'],
            ),
          ],
        ),
      ],
    );
    final custom = _preset(
      id: 'custom',
      categories: [
        _category(
          id: 'custom_hair',
          key: 'hair',
          probability: 0.25,
          groups: [
            _group(
              id: 'custom_hair',
              name: 'Hair',
              sourceId: 'hairColor',
              tags: ['pink hair'],
            ),
            _group(id: 'extra', name: 'Extra', tags: ['ribbon']),
          ],
        ),
        _category(
          id: 'eyes',
          key: 'eyes',
          groups: [
            _group(id: 'eyes', name: 'Eyes', tags: ['green eyes']),
          ],
        ),
      ],
    );

    final merged = RandomPresetMerger.merge(
      officialPreset: official,
      customPreset: custom,
    );

    expect(merged.isDefault, isFalse);
    expect(merged.categories.map((category) => category.key), ['hair', 'eyes']);
    final hair = merged.findCategoryByKey('hair')!;
    expect(hair.probability, 0.25);
    expect(hair.groups.map((group) => group.name), ['Hair', 'Extra']);
    expect(hair.groups.first.tags.single.tag, 'pink hair');
  });

  test('custom disabled category disables final category without mutation', () {
    final officialGroup = _group(
      id: 'official_group',
      name: 'Pose',
      tags: ['standing'],
    );
    final official = _preset(
      id: 'official',
      isDefault: true,
      categories: [
        _category(id: 'pose', key: 'pose', groups: [officialGroup]),
      ],
    );
    final custom = _preset(
      id: 'custom',
      categories: [
        _category(
          id: 'custom_pose',
          key: 'pose',
          enabled: false,
          groups: [
            _group(id: 'custom_group', name: 'Pose', tags: ['sitting']),
          ],
        ),
      ],
    );

    final merged = RandomPresetMerger.merge(
      officialPreset: official,
      customPreset: custom,
    );

    expect(merged.findCategoryByKey('pose')!.enabled, isFalse);
    expect(official.findCategoryByKey('pose')!.enabled, isTrue);
    expect(
      official.findCategoryByKey('pose')!.groups.single.tags.single.tag,
      'standing',
    );
  });

  test('custom character count config overrides official algorithm config', () {
    final customConfig = CharacterCountConfig.naiDefault.copyWith(
      categories: [
        CharacterCountConfig.naiDefault.categories.first.copyWith(weight: 99),
      ],
    );
    final official = _preset(
      id: 'official',
      isDefault: true,
      algorithmConfig: const AlgorithmConfig(),
      categories: [_category(id: 'a', key: 'a')],
    );
    final custom = _preset(
      id: 'custom',
      algorithmConfig: AlgorithmConfig(characterCountConfig: customConfig),
      categories: [_category(id: 'b', key: 'b')],
    );

    final merged = RandomPresetMerger.merge(
      officialPreset: official,
      customPreset: custom,
    );

    expect(
      merged.algorithmConfig.effectiveCharacterCountConfig.categories.first
          .weight,
      99,
    );
  });

  test('custom legacy count weights stay effective in hybrid merge', () {
    final official = _preset(
      id: 'official',
      isDefault: true,
      algorithmConfig: AlgorithmConfig(
        characterCountConfig: CharacterCountConfig.naiDefault.copyWith(
          categories: [
            CharacterCountConfig.naiDefault.categories.first.copyWith(
              weight: 1,
            ),
          ],
        ),
      ),
      categories: [_category(id: 'a', key: 'a')],
    );
    const customConfig = AlgorithmConfig(
      characterCountWeights: [
        [0, 100],
        [1, 0],
      ],
    );

    final merged = RandomPresetMerger.merge(
      officialPreset: official,
      customPreset: _preset(
        id: 'custom',
        algorithmConfig: customConfig,
        categories: [_category(id: 'b', key: 'b')],
      ),
    );

    expect(
      merged.algorithmConfig.effectiveCharacterCountConfig
          .findCategoryById('no_humans')!
          .weight,
      100,
    );
  });

  test('same group name with different source ids appends custom group', () {
    final officialUpdatedAt = DateTime(2026);
    final official = _preset(
      id: 'official',
      isDefault: true,
      updatedAt: officialUpdatedAt,
      categories: [
        _category(
          id: 'hair',
          key: 'hair',
          groups: [
            _group(
              id: 'official_hair',
              name: 'Hair',
              sourceId: 'hairColor',
              tags: ['blue hair'],
            ),
          ],
        ),
      ],
    );
    final custom = _preset(
      id: 'custom',
      categories: [
        _category(
          id: 'custom_hair',
          key: 'hair',
          groups: [
            _group(
              id: 'custom_hair',
              name: 'Hair',
              sourceId: 'hairStyle',
              tags: ['bob cut'],
            ),
          ],
        ),
      ],
    );

    final merged = RandomPresetMerger.merge(
      officialPreset: official,
      customPreset: custom,
    );

    final hair = merged.findCategoryByKey('hair')!;
    expect(hair.groups.map((group) => group.sourceId), [
      'hairColor',
      'hairStyle',
    ]);
    expect(hair.groups.map((group) => group.tags.single.tag), [
      'blue hair',
      'bob cut',
    ]);
    expect(merged.updatedAt, officialUpdatedAt);
  });
}

RandomPreset _preset({
  required String id,
  bool isDefault = false,
  AlgorithmConfig algorithmConfig = const AlgorithmConfig(),
  List<RandomCategory> categories = const [],
  DateTime? updatedAt,
}) {
  return RandomPreset(
    id: id,
    name: id,
    isDefault: isDefault,
    algorithmConfig: algorithmConfig,
    categories: categories,
    updatedAt: updatedAt,
  );
}

RandomCategory _category({
  required String id,
  required String key,
  bool enabled = true,
  double probability = 1,
  List<RandomTagGroup> groups = const [],
}) {
  return RandomCategory(
    id: id,
    key: key,
    name: key,
    enabled: enabled,
    probability: probability,
    scope: TagScope.global,
    groups: groups,
  );
}

RandomTagGroup _group({
  required String id,
  required String name,
  String? sourceId,
  List<String> tags = const [],
}) {
  return RandomTagGroup(
    id: id,
    name: name,
    sourceType: sourceId == null
        ? TagGroupSourceType.custom
        : TagGroupSourceType.builtin,
    sourceId: sourceId,
    tags: tags
        .map((tag) => WeightedTag.simple(tag, 10, TagSource.custom))
        .toList(),
  );
}
