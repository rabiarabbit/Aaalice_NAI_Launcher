import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/prompt/prompt_config.dart' as legacy;
import 'package:nai_launcher/data/models/prompt/random_tag_group.dart';
import 'package:nai_launcher/data/services/random_prompt_legacy_adapter.dart';

void main() {
  test('converts legacy string configs into canonical random preset categories',
      () {
    final legacyPreset = legacy.RandomPromptPreset.create(
      name: 'Legacy',
      configs: [
        legacy.PromptConfig.create(
          name: 'Hair Color',
          selectionMode: legacy.SelectionMode.all,
          stringContents: ['blue hair', 'pink hair'],
          bracketMin: 1,
          bracketMax: 1,
        ),
      ],
    );

    final preset = RandomPromptLegacyAdapter.fromPreset(legacyPreset);

    expect(preset.id, legacyPreset.id);
    expect(preset.categories, hasLength(1));
    expect(preset.categories.single.key, 'legacy_hair_color');
    expect(
      preset.categories.single.groups.single.selectionMode,
      SelectionMode.all,
    );
    expect(preset.categories.single.groups.single.tags.map((tag) => tag.tag), [
      'blue hair',
      'pink hair',
    ]);
    expect(preset.categories.single.groups.single.bracketMin, 1);
  });

  test('converts legacy nested configs into nested random tag groups', () {
    final child = legacy.PromptConfig.create(
      name: 'Child',
      stringContents: ['child tag'],
    );
    final legacyPreset = legacy.RandomPromptPreset.create(
      name: 'Legacy',
      configs: [
        legacy.PromptConfig.create(
          name: 'Parent',
          contentType: legacy.ContentType.nested,
          nestedConfigs: [child],
        ),
      ],
    );

    final preset = RandomPromptLegacyAdapter.fromPreset(legacyPreset);
    final group = preset.categories.single.groups.single;

    expect(group.nodeType, TagGroupNodeType.config);
    expect(group.children, hasLength(1));
    expect(group.children.single.tags.single.tag, 'child tag');
  });

  test('uses deterministic group ids for repeated legacy conversions', () {
    final legacyPreset = legacy.RandomPromptPreset.create(
      name: 'Legacy',
      configs: [
        legacy.PromptConfig.create(
          name: 'Sequential',
          selectionMode: legacy.SelectionMode.singleSequential,
          stringContents: ['first', 'second'],
        ),
      ],
    );

    final first = RandomPromptLegacyAdapter.fromPreset(legacyPreset);
    final second = RandomPromptLegacyAdapter.fromPreset(legacyPreset);

    expect(
      first.categories.single.groups.single.id,
      second.categories.single.groups.single.id,
    );
  });
}
