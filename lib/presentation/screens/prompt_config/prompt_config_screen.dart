import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                          color: colorScheme.outlineVariant.withOpacity(0.3),
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
                title: const Text('导入预设'),
                subtitle: const Text('从 JSON 文本导入随机配置预设'),
                onTap: () => Navigator.pop(context, 'import'),
              ),
              ListTile(
                enabled: selectedPreset != null,
                leading: const Icon(Icons.upload_rounded),
                title: const Text('导出当前预设'),
                subtitle: Text(selectedPreset?.name ?? '未选择预设'),
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
        AppToast.success(context, '已导入预设 "${imported.name}"');
      }
      return;
    }

    if (action == 'export') {
      if (selectedPreset == null) {
        AppToast.warning(context, '请先选择预设');
        return;
      }
      await PresetImportDialog.showExport(context, selectedPreset);
    }
  }

  Future<void> _showGlobalSettings() async {
    final selectedPreset =
        ref.read(randomPresetNotifierProvider).selectedPreset;
    if (selectedPreset == null) {
      AppToast.warning(context, '请先选择预设');
      return;
    }
    if (selectedPreset.isDefault) {
      AppToast.warning(context, '默认预设为只读，请先新建或复制为自定义预设');
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
      label: const Text('全局人数设置'),
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
            tooltip: '关闭预览',
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
