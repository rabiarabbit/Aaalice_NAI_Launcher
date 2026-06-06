import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/random_preset_provider.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/prompt/diy/dialogs/preset_import_dialog.dart';
import '../../widgets/prompt/global_settings_dialog.dart';
import '../../widgets/prompt/random_manager/preview_generator_panel.dart';
import '../../widgets/prompt/random_manager/preset_selector_bar.dart';
import '../../widgets/prompt/random_manager/algorithm_config_card.dart';
import '../../widgets/prompt/random_manager/category_card.dart';

/// 随机提示词配置页面 - 左右分栏布局
///
/// 布局结构:
/// ┌─────────────────────────────────────────────────────────────┐
/// │                   PresetSelectorBar                          │
/// ├──────────────────────┬──────────────────────────────────────┤
/// │  AlgorithmConfigCard │         CategoryCardList              │
/// │                      │   ┌────────────────────────────────┐  │
/// │  ProbabilitySection  │   │ Category 1                     │  │
/// │                      │   ├────────────────────────────────┤  │
/// │                      │   │ Category 2                     │  │
/// │                      │   ├────────────────────────────────┤  │
/// │                      │   │ Category 3                     │  │
/// │                      │   └────────────────────────────────┘  │
/// └──────────────────────┴──────────────────────────────────────┘
class PromptConfigScreen extends ConsumerStatefulWidget {
  const PromptConfigScreen({super.key});

  @override
  ConsumerState<PromptConfigScreen> createState() => _PromptConfigScreenState();
}

class _PromptConfigScreenState extends ConsumerState<PromptConfigScreen> {
  bool _showPreview = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: Column(
        children: [
          // 预设选择栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: PresetSelectorBar(
              onGeneratePreview: () {
                setState(() => _showPreview = true);
              },
              onImportExport: _showImportExportActions,
            ),
          ),

          // 主内容区 - 左右分栏
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;

                if (isWide) {
                  // 宽屏: 左右分栏布局
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧: 算法配置 + 概率分布预览
                        SizedBox(
                          width: 420,
                          child: _LeftPanel(
                            showPreview: _showPreview,
                            onGlobalSettings: _showGlobalSettings,
                            onClosePreview: () {
                              setState(() => _showPreview = false);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 右侧: 类别配置垂直列表
                        const Expanded(
                          child: CategoryCardList(),
                        ),
                      ],
                    ),
                  );
                } else {
                  // 窄屏: 上下布局
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AlgorithmConfigCard(),
                        const SizedBox(height: 12),
                        _GlobalSettingsButton(onPressed: _showGlobalSettings),
                        if (_showPreview) ...[
                          const SizedBox(height: 16),
                          _PreviewSection(
                            onClose: () {
                              setState(() => _showPreview = false);
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        Divider(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.3),
                          height: 1,
                        ),
                        const SizedBox(height: 16),
                        const CategoryCardGrid(),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportExportActions() async {
    final presetState = ref.read(randomPresetNotifierProvider);
    final selectedPreset = presetState.selectedPreset;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: Text(context.l10n.randomManager_importPreset),
                subtitle: Text(context.l10n.randomManager_importPresetSubtitle),
                onTap: () => Navigator.pop(context, 'import'),
              ),
              ListTile(
                enabled: selectedPreset != null,
                leading: const Icon(Icons.upload_rounded),
                title: Text(context.l10n.randomManager_exportCurrentPreset),
                subtitle: Text(
                  selectedPreset?.name ??
                      context.l10n.randomManager_noPresetSelected,
                ),
                onTap: selectedPreset == null
                    ? null
                    : () => Navigator.pop(context, 'export'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'import') {
      final imported = await PresetImportDialog.showImport(context);
      if (!mounted || imported == null) return;
      await ref.read(randomPresetNotifierProvider.notifier).addPreset(imported);
      await ref.read(randomPresetNotifierProvider.notifier).selectPreset(
            imported.id,
          );
      if (mounted) {
        AppToast.success(
          context,
          context.l10n.randomManager_presetImported(imported.name),
        );
      }
      return;
    }

    if (action == 'export') {
      if (selectedPreset == null) {
        AppToast.warning(context, context.l10n.randomManager_selectPresetFirst);
        return;
      }
      await PresetImportDialog.showExport(context, selectedPreset);
    }
  }

  Future<void> _showGlobalSettings() async {
    final selectedPreset =
        ref.read(randomPresetNotifierProvider).selectedPreset;
    if (selectedPreset == null) {
      AppToast.warning(context, context.l10n.randomManager_selectPresetFirst);
      return;
    }
    if (selectedPreset.isDefault) {
      AppToast.warning(
        context,
        context.l10n.randomManager_defaultPresetReadonly,
      );
      return;
    }
    await GlobalSettingsDialog.show(context);
  }
}

/// 左侧面板 - 算法配置
class _LeftPanel extends StatelessWidget {
  const _LeftPanel({
    required this.showPreview,
    required this.onGlobalSettings,
    required this.onClosePreview,
  });

  final bool showPreview;
  final VoidCallback onGlobalSettings;
  final VoidCallback onClosePreview;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 算法配置卡片
          const AlgorithmConfigCard(),
          const SizedBox(height: 12),
          _GlobalSettingsButton(onPressed: onGlobalSettings),
          if (showPreview) ...[
            const SizedBox(height: 16),
            _PreviewSection(onClose: onClosePreview),
          ],
        ],
      ),
    );
  }
}

class _GlobalSettingsButton extends StatelessWidget {
  const _GlobalSettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.manage_accounts_outlined),
      label: Text(context.l10n.randomManager_globalPeopleSettings),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: context.l10n.randomManager_closePreview,
          ),
        ),
        const SizedBox(
          height: 360,
          child: PreviewGeneratorPanel(),
        ),
      ],
    );
  }
}
