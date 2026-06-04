# Random Config Mode Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the random configuration mode so the launcher has a coherent, persisted, test-covered flow for official, custom, and hybrid random prompt generation, with the random configuration screen able to create, preview, import/export, and apply presets that actually affect generation.

**Architecture:** Keep `randomPromptModeProvider` as the persisted on/off auto-random toggle. Make `randomModeNotifierProvider` the persisted generation algorithm selector. Use `RandomPreset` as the canonical preset model for runtime generation. Route all generation modes through explicit mode handlers. Use an adapter only to migrate old `RandomPromptPreset`/`PromptConfig` data into the new preset model.

**Tech Stack:** Flutter, Dart, Riverpod generated providers, Hive-backed `LocalStorageService`, existing prompt random models and widgets, `flutter_test` and existing repository validation scripts.

---

## Current State Summary

The existing code exposes a random configuration mode, but the implementation is split across old and new systems:

- `randomPromptModeProvider` is a persisted boolean for the auto-random draw toggle.
- `randomModeNotifierProvider` is an in-memory `RandomGenerationMode` selector.
- `RandomGenerationMode.hybrid` exists in the model and provider helpers, but the UI hides it and generation routing does not implement it.
- The random configuration screen edits `RandomPreset`, while the old custom generation path still uses `RandomPromptPreset` and `PromptConfig`.
- The official mode currently depends on the selected `RandomPreset` when one exists, so official/custom boundaries are unclear.
- The random configuration page has preset creation, preview, import/export, and global setting widgets available, but important entry points are not wired.
- Several advanced preset fields exist in the model but are not consumed by generation.

## Scope Decisions

- `RandomPreset` is the canonical runtime model for random configuration.
- `RandomGenerationMode.naiOfficial` uses the immutable/default official preset data.
- `RandomGenerationMode.custom` uses the selected user preset.
- `RandomGenerationMode.hybrid` merges the default official preset with the selected user preset using a deterministic merge policy.
- `randomPromptModeProvider` remains a boolean feature toggle and is not renamed.
- `randomModeNotifierProvider` becomes persisted mode state and is used only for algorithm selection.
- `AlgorithmConfig.characterCountConfig` becomes the canonical character count and gender configuration used by generation.
- Existing `RandomPromptPreset` and `PromptConfig` data are migrated or adapted into `RandomPreset`; new writes should use `RandomPreset`.
- Generated files are updated through code generation only.

## Responsibility Map

- `lib/core/constants/storage_keys.dart`: add the storage key for the generation mode.
- `lib/core/storage/local_storage_service.dart`: store and load the generation mode as a string.
- `lib/presentation/providers/random_mode_provider.dart`: persist mode selection and expose stable serialization.
- `lib/presentation/providers/prompt_config_provider.dart`: route official, custom, and hybrid generation explicitly.
- `lib/presentation/providers/random_preset_provider.dart`: keep selected `RandomPreset` state as the source of custom preset generation.
- `lib/data/services/random_prompt_generator.dart`: generate from canonical presets and consume effective algorithm and group rules.
- `lib/data/services/random_prompt_legacy_adapter.dart`: convert old custom prompt config data into `RandomPreset`.
- `lib/data/services/random_preset_merger.dart`: merge official and custom presets for hybrid mode.
- `lib/data/services/random_preset_generation_context.dart`: hold generation-time context for dependencies, visibility, branches, variables, and post-processing.
- `lib/presentation/screens/prompt_config/prompt_config_screen.dart`: wire preset creation, preview, import/export, and global settings.
- `lib/presentation/widgets/prompt/random_mode_selector.dart`: expose implemented modes and show correct labels.
- `lib/presentation/widgets/prompt/random_manager/algorithm_config_card.dart`: edit fields that generation actually uses.
- `test/`: add focused provider, service, and widget tests. Update `.gitignore` if needed so these tests are not accidentally excluded.

## Task 1: Characterize Existing Gaps With Tests

Files:

- `test/presentation/providers/random_mode_provider_test.dart`
- `test/presentation/providers/prompt_config_random_mode_test.dart`
- `test/data/services/random_prompt_generator_preset_test.dart`
- `test/presentation/screens/prompt_config/random_config_screen_test.dart`
- `.gitignore`

Steps:

- [ ] Inspect `.gitignore` test allowlists before adding files. If the intended test paths are ignored, add precise negation rules for the new test files or place them in already tracked test directories.
- [ ] Add a provider test proving `randomModeNotifierProvider` starts at official mode and can switch to custom and hybrid.
- [ ] Add a generation routing test proving current custom generation and official generation are distinguishable by selected preset input.
- [ ] Add a characterization test showing hybrid currently has no distinct runtime behavior. Mark this as an expected failing test only during the red phase; the final implementation must pass it.
- [ ] Add a widget test for `RandomModeSelector` labels and available menu entries after hybrid is implemented.
- [ ] Add a widget or provider test around the random configuration screen preset creation path so the create action is not left behind a "开发中" toast.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/random_mode_provider_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/prompt_config_random_mode_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_preset_test.dart
```

Expected outcome:

- Tests document the current intended behavior before production edits.
- Any failing red-phase tests are converted to passing tests by later tasks.

Suggested commit:

```text
test(random-config): characterize incomplete mode routing
```

## Task 2: Persist Generation Mode State

Files:

- `lib/core/constants/storage_keys.dart`
- `lib/core/storage/local_storage_service.dart`
- `lib/presentation/providers/random_mode_provider.dart`
- `lib/presentation/providers/random_mode_provider.g.dart`
- `test/presentation/providers/random_mode_provider_test.dart`

Steps:

- [ ] Add `StorageKeys.randomGenerationMode = 'random_generation_mode'`.
- [ ] Add string-based getters and setters to `LocalStorageService` so core storage does not import prompt model enums:

```dart
String getRandomGenerationMode() => getSetting<String>(
      StorageKeys.randomGenerationMode,
      defaultValue: 'nai_official',
    ) ?? 'nai_official';

Future<void> setRandomGenerationMode(String value) async =>
    setSetting(StorageKeys.randomGenerationMode, value);
```

- [ ] Add serialization helpers in `random_mode_provider.dart`, for example `RandomGenerationModeStorageX.toStorageValue()` and `randomGenerationModeFromStorage(String value)`.
- [ ] Update `RandomModeNotifier.build()` to read the persisted value through `localStorageServiceProvider`.
- [ ] Update `setMode`, `useNaiOfficial`, `useCustom`, and `useHybrid` to persist the selected value after updating state.
- [ ] Decide whether `toggle()` cycles only official/custom or all implemented modes. After hybrid is fully implemented, make the cycle explicit and covered by tests.
- [ ] Add `isHybridModeProvider` if UI or generation code needs the derived boolean.
- [ ] Run `dart run build_runner build --delete-conflicting-outputs` to regenerate `random_mode_provider.g.dart`.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe run build_runner build --delete-conflicting-outputs
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/random_mode_provider_test.dart
```

Expected outcome:

- Generation mode survives provider rebuilds and app restarts.
- Unknown stored values safely fall back to `RandomGenerationMode.naiOfficial`.

Suggested commit:

```text
fix(random-config): persist generation mode
```

## Task 3: Route All Generation Modes Through Canonical Presets

Files:

- `lib/presentation/providers/prompt_config_provider.dart`
- `lib/presentation/providers/random_preset_provider.dart`
- `lib/data/services/random_prompt_generator.dart`
- `lib/data/models/prompt/random_prompt_result.dart`
- `test/presentation/providers/prompt_config_random_mode_test.dart`
- `test/data/services/random_prompt_generator_preset_test.dart`

Steps:

- [ ] Replace the two-branch mode check in `PromptConfigNotifier.generateRandomPrompt` with a full `switch` over `RandomGenerationMode.naiOfficial`, `RandomGenerationMode.custom`, and `RandomGenerationMode.hybrid`.
- [ ] Implement `_generateOfficialPrompt()` so official mode uses the default official preset or the existing NAI-style generator, independent of the selected user preset.
- [ ] Implement `_generateCustomPresetPrompt()` so custom mode uses the selected `RandomPreset` and returns a clear failure result when no usable custom preset is selected.
- [ ] Implement `_generateHybridPrompt()` to call the hybrid merger introduced in Task 8.
- [ ] Keep `RandomPromptResult.mode` accurate for every branch.
- [ ] Preserve existing public method names where possible so generation screen callers do not need broad UI changes.
- [ ] Add test fixtures with tiny official and custom presets so each mode can be asserted deterministically.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/prompt_config_random_mode_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_preset_test.dart
```

Expected outcome:

- Official mode no longer changes because the user selected a custom preset.
- Custom mode uses the random configuration screen's selected preset.
- Hybrid mode has an explicit code path instead of silently behaving like custom.

Suggested commit:

```text
fix(random-config): route modes through random presets
```

## Task 4: Adapt Legacy Custom Configs Into RandomPreset

Files:

- `lib/data/services/random_prompt_legacy_adapter.dart`
- `lib/data/models/prompt/random_preset.dart`
- `lib/data/models/prompt/random_category.dart`
- `lib/data/models/prompt/random_tag_group.dart`
- `lib/presentation/providers/prompt_config_provider.dart`
- `lib/presentation/widgets/prompt/diy/dialogs/save_as_preset_dialog.dart`
- `test/data/services/random_prompt_legacy_adapter_test.dart`

Steps:

- [ ] Create `RandomPromptLegacyAdapter` with methods that convert `RandomPromptPreset` and `PromptConfig` into a `RandomPreset`.
- [ ] Map old character, style, quality, and negative prompt groups into stable `RandomCategory` and `RandomTagGroup` entries.
- [ ] Preserve old weights as group/tag weights where equivalent fields exist.
- [ ] Update `SaveAsPresetDialog` so new saves go through `randomPresetNotifierProvider`, not the old `promptConfigNotifierProvider`.
- [ ] Keep old Hive reads available only as a migration/readback path until a later cleanup removes obsolete storage.
- [ ] Add tests proving old configs convert into usable `RandomPreset` objects and can be generated by `RandomPromptGenerator.generateFromPreset`.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_legacy_adapter_test.dart
```

Expected outcome:

- Existing users' old custom prompt configs can be represented in the new random preset pipeline.
- New custom preset saves do not deepen the split between old and new systems.

Suggested commit:

```text
fix(random-config): migrate legacy custom presets
```

## Task 5: Wire Random Configuration Screen Actions

Files:

- `lib/presentation/screens/prompt_config/prompt_config_screen.dart`
- `lib/presentation/widgets/prompt/random_manager/preset_selector_bar.dart`
- `lib/presentation/widgets/prompt/random_manager/preview_generator_panel.dart`
- `lib/presentation/widgets/prompt/diy/dialogs/preset_import_dialog.dart`
- `lib/presentation/widgets/prompt/global_settings_dialog.dart`
- `test/presentation/screens/prompt_config/random_config_screen_test.dart`

Steps:

- [ ] In `PresetSelectorBar`, replace the `__create_new__` warning toast with the existing `_showCreatePresetDialog(context)` path.
- [ ] In `PromptConfigScreen`, pass `onGeneratePreview` to open or reveal `PreviewGeneratorPanel`.
- [ ] Place `PreviewGeneratorPanel` inside a bounded container, for example a fixed-height panel, because the widget uses `Expanded` internally.
- [ ] Pass `onImportExport` to open `PresetImportDialog` for import and a matching export action for the selected preset.
- [ ] Add a visible entry point for `GlobalSettingsDialog.show` and apply the returned `AlgorithmConfig` to the selected preset.
- [ ] Ensure no action silently succeeds when no preset is selected; show an actionable empty state instead.
- [ ] Add widget tests covering create, preview, import/export entry point visibility, and global settings entry point visibility.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/screens/prompt_config/random_config_screen_test.dart
```

Expected outcome:

- The random configuration screen is not a partial editor with dead buttons.
- Users can create a preset from the dropdown, preview generation, import/export presets, and edit global settings.

Suggested commit:

```text
feat(random-config): wire preset management actions
```

## Task 6: Make Algorithm Configuration Effective

Files:

- `lib/data/models/prompt/random_preset.dart`
- `lib/data/services/random_prompt_generator.dart`
- `lib/presentation/widgets/prompt/random_manager/algorithm_config_card.dart`
- `lib/presentation/widgets/prompt/global_settings_dialog.dart`
- `test/data/services/random_prompt_generator_algorithm_test.dart`
- `test/presentation/widgets/prompt/random_manager/algorithm_config_card_test.dart`

Steps:

- [ ] Treat `AlgorithmConfig.characterCountConfig` as the field consumed by generation.
- [ ] Add an `effectiveCharacterCountConfig` helper or equivalent method on `AlgorithmConfig` that falls back to `CharacterCountConfig.naiDefault`.
- [ ] If legacy `characterCountWeights` or `genderWeights` contain user values and `characterCountConfig` is null, convert them into `CharacterCountConfig` during migration or provider load.
- [ ] Update `AlgorithmConfigCard` to display and edit `CharacterCountConfig` values that generation actually consumes.
- [ ] Stop presenting `characterCountWeights` and `genderWeights` as effective controls unless they are retained only for migration.
- [ ] Update `GlobalSettingsDialog` to save the same canonical config shape.
- [ ] Add generator tests proving character count weights and gender ratios change generated output distribution or selected character count.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_algorithm_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/prompt/random_manager/algorithm_config_card_test.dart
```

Expected outcome:

- Algorithm settings shown on screen affect actual random prompt generation.
- There is one canonical configuration path for character count and gender selection.

Suggested commit:

```text
fix(random-config): make algorithm settings affect generation
```

## Task 7: Implement Preset Runtime Rules

Files:

- `lib/data/services/random_preset_generation_context.dart`
- `lib/data/services/random_prompt_generator.dart`
- `lib/data/models/prompt/random_tag_group.dart`
- `lib/data/models/prompt/random_category.dart`
- `lib/data/models/prompt/random_preset.dart`
- `test/data/services/random_prompt_generator_rules_test.dart`

Steps:

- [ ] Create `RandomPresetGenerationContext` to track category outputs, selected group ids, selected tags, variables, global tags, character tags, character count, character gender, and generation time.
- [ ] Pass the context through preset, category, and group generation methods.
- [ ] Apply `AlgorithmConfig.globalTimeConditions` before category generation.
- [ ] Apply `AlgorithmConfig.globalVisibilityRules` and `AlgorithmConfig.isCategoryGloballyVisible` before category selection.
- [ ] Apply `RandomTagGroup.timeCondition` using the existing `isTimeConditionActive` model helper.
- [ ] Apply `RandomTagGroup.visibilityRules` using the existing `checkVisibility` model helper.
- [ ] Apply `RandomTagGroup.dependencyConfig` using `DependencyConfig.checkDependency` and context counts.
- [ ] Apply `RandomTagGroup.conditionalBranchConfig` using `ConditionalBranchConfig.selectBranch`.
- [ ] Apply `RandomTagGroup.postProcessRules` and global post-process rules after tag selection.
- [ ] Apply `RandomTagGroup.emphasisProbability` when emitting tags that support weight/emphasis formatting.
- [ ] Add unit tests for each rule type with minimal fixtures.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_rules_test.dart
```

Expected outcome:

- Fields exposed by the random preset model are not inert.
- Advanced DIY rules produce predictable generation behavior and are covered by focused tests.

Suggested commit:

```text
feat(random-config): apply preset DIY rules
```

## Task 8: Implement Hybrid Preset Merge

Files:

- `lib/data/services/random_preset_merger.dart`
- `lib/data/services/random_prompt_generator.dart`
- `lib/presentation/providers/prompt_config_provider.dart`
- `lib/presentation/widgets/prompt/random_mode_selector.dart`
- `test/data/services/random_preset_merger_test.dart`
- `test/presentation/providers/prompt_config_random_mode_test.dart`

Merge policy:

- `naiOfficial`: use the default official preset only.
- `custom`: use the selected custom preset only.
- `hybrid`: merge the default official preset with the selected custom preset.
- If a selected category has the same stable key as an official category, selected category settings override probability, enabled state, scope, bracket behavior, and group selection settings.
- If a selected group has the same `sourceType + sourceId` pair as an official group, it replaces that group.
- If a selected group lacks source ids but has the same name as an official group in the same category, it replaces that group.
- New selected categories append after official categories.
- New selected groups append after official groups inside the matched category.
- A disabled selected category disables the final merged category.
- The merged algorithm config uses the selected preset's `characterCountConfig` when present, otherwise the official default.

Steps:

- [ ] Create `RandomPresetMerger.merge({required RandomPreset officialPreset, required RandomPreset customPreset})`.
- [ ] Keep merge order stable so tests can assert output order.
- [ ] Use deep copies or immutable copies so merging never mutates the official preset or user preset.
- [ ] Wire `_generateHybridPrompt()` to merge then call `RandomPromptGenerator.generateFromPreset`.
- [ ] Update `RandomModeSelector` to expose hybrid after the merge path and tests are complete.
- [ ] Update indicator labels so official, custom, and hybrid are all displayed accurately.
- [ ] Add focused tests for replacement, append, disable, algorithm config override, and no-mutation guarantees.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_preset_merger_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/prompt_config_random_mode_test.dart
```

Expected outcome:

- Hybrid mode is a real third generation mode.
- UI exposes hybrid only when runtime support is implemented and tested.

Suggested commit:

```text
feat(random-config): support hybrid preset merge
```

## Task 9: Clean Up Duplicate Generation Paths

Files:

- `lib/data/services/random_prompt_generator.dart`
- `lib/data/services/strategies/preset_generator_strategy.dart`
- `test/data/services/random_prompt_generator_preset_test.dart`
- `test/data/services/random_prompt_generator_rules_test.dart`

Steps:

- [ ] Decide whether `PresetGeneratorStrategy` becomes the implementation used by `RandomPromptGenerator` or is removed.
- [ ] If retained, move preset-category-group generation logic into the strategy and make `RandomPromptGenerator.generateFromPreset` delegate to it.
- [ ] If removed, delete unused strategy wiring and private reserved fields from `RandomPromptGenerator`.
- [ ] Ensure there is one tested generation path for official, custom, and hybrid preset generation.
- [ ] Run the preset and rule tests after cleanup to catch behavior drift.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_preset_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_rules_test.dart
```

Expected outcome:

- Future random generation changes have one authoritative implementation point.
- Strategy and generator code no longer diverge.

Suggested commit:

```text
refactor(random-config): consolidate preset generation path
```

## Task 10: UX and Localization Hardening

Files:

- `lib/presentation/widgets/prompt/random_mode_selector.dart`
- `lib/presentation/screens/prompt_config/prompt_config_screen.dart`
- `lib/l10n/*.arb`
- `test/presentation/widgets/prompt/random_mode_selector_test.dart`
- `test/presentation/screens/prompt_config/random_config_screen_test.dart`

Steps:

- [ ] Replace hard-coded mode display fallbacks with `RandomGenerationMode.getName(context)` or localized strings.
- [ ] Add a distinct hybrid label, icon, tooltip, and description.
- [ ] Add an empty-state message for custom and hybrid modes when no usable custom preset is selected.
- [ ] Add localized strings for create preset, preview generation, import preset, export preset, global settings, and hybrid mode descriptions if missing.
- [ ] Run l10n generation after ARB edits.
- [ ] Add widget tests for localized labels and empty states.

Validation:

```powershell
flutter gen-l10n
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/prompt/random_mode_selector_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/screens/prompt_config/random_config_screen_test.dart
```

Expected outcome:

- Users can understand which random mode is active.
- Missing preset states are explicit instead of failing silently.

Suggested commit:

```text
feat(random-config): polish random mode UX
```

## Task 11: Final Validation

Files:

- All files touched by Tasks 1 through 10.
- Generated files from l10n and Riverpod build generation.

Steps:

- [ ] Run code generation after provider/model/l10n inputs change.
- [ ] Format touched Dart files.
- [ ] Run all focused random configuration tests.
- [ ] Run the repository analyzer.
- [ ] Run the Windows release build if focused validation passes.
- [ ] Check that `build\windows\x64\runner\Release\data\app.so` and `build\windows\x64\runner\Release\data\flutter_assets` timestamps are refreshed. Do not rely only on `nai_launcher.exe` timestamp.
- [ ] Inspect `git status --short` and confirm no unrelated dirty files were included.

Validation:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe run build_runner build --delete-conflicting-outputs
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe format lib test
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/random_mode_provider_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/prompt_config_random_mode_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_preset_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_algorithm_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_prompt_generator_rules_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/data/services/random_preset_merger_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot analyze
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot build windows --release
```

Expected outcome:

- Focused tests pass.
- Analyzer passes.
- Windows release build completes or any environment-specific Flutter wrapper issue is documented separately from production-code failures.

Suggested final commit:

```text
test(random-config): cover random mode completion
```

## Implementation Order

1. Add characterization tests.
2. Persist generation mode.
3. Route all modes through canonical preset generation.
4. Add legacy adapter to prevent old custom configs from being orphaned.
5. Wire random configuration screen actions.
6. Make algorithm settings effective.
7. Implement runtime DIY rules.
8. Implement hybrid merge and expose hybrid in UI.
9. Consolidate duplicate generation paths.
10. Harden UX and localization.
11. Run full validation and inspect the final diff.

## Risks and Mitigations

- Risk: old custom prompt configs may not map perfectly into `RandomPreset`.
  Mitigation: keep adapter behavior explicit, test representative old configs, and preserve old reads until migration coverage is sufficient.

- Risk: generator rule execution can become order-dependent.
  Mitigation: introduce `RandomPresetGenerationContext`, keep rule order documented in tests, and avoid hidden shared mutable state.

- Risk: hybrid mode can surprise users by mixing disabled or overridden groups.
  Mitigation: implement a deterministic merge policy, test no-mutation guarantees, and show clear UI descriptions.

- Risk: new tests may be ignored by repository `.gitignore`.
  Mitigation: check ignore status before adding tests and add precise allowlist entries for new test paths.

- Risk: Riverpod generated files and localization outputs can drift.
  Mitigation: run build generation and l10n generation after provider/model/ARB edits and never hand-edit generated outputs.

## Completion Criteria

- `RandomGenerationMode.naiOfficial`, `custom`, and `hybrid` are all implemented as distinct tested runtime paths.
- Generation mode is persisted separately from the random auto-draw boolean.
- Random configuration screen create, preview, import/export, and global settings actions are wired.
- Custom mode uses `RandomPreset`, not the old `RandomPromptPreset` path.
- Existing old custom configs have an adapter or migration path into `RandomPreset`.
- Algorithm settings shown in UI affect generated prompts.
- Advanced preset rules that are exposed by the model are consumed by generation or removed from the UI surface.
- Hybrid mode has a deterministic merge policy and no longer behaves as custom by accident.
- Focused tests, analyzer, and release build validation have been run and reported.
