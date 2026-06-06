import 'package:flutter/material.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';

import '../../../data/models/gallery/local_image_record.dart';

/// 图片发送目标类型
enum SendDestination {
  /// 发送到图生图
  img2img,

  /// 发送到反推
  reversePrompt,

  /// 发送到Vibe Transfer
  vibeTransfer,

  /// 发送到 Krita
  krita,
}

/// 图片发送目标选择对话框
///
/// 用于选择将图片发送到何处：
/// - 图生图 (img2img)
/// - Vibe Transfer
class ImageSendDestinationDialog extends StatelessWidget {
  /// 创建发送目标选择对话框
  const ImageSendDestinationDialog({
    super.key,
    required this.record,
  });

  /// 图片记录
  final LocalImageRecord record;

  /// 显示对话框并返回用户选择
  ///
  /// 返回 [SendDestination] 或 null（用户取消）
  static Future<SendDestination?> show(
    BuildContext context,
    LocalImageRecord record,
  ) async {
    return showDialog<SendDestination>(
      context: context,
      builder: (context) => ImageSendDestinationDialog(record: record),
    );
  }

  /// 检查图片是否有 vibe 数据
  bool get hasVibeData => record.vibeData != null || record.hasVibeMetadata;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.gallery_send_to),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 发送到图生图
            _buildOption(
              context,
              icon: Icons.image,
              title: context.l10n.gallery_sendToImg2Img,
              subtitle: context.l10n.gallery_useImageForGeneration,
              onTap: () => Navigator.of(context).pop(SendDestination.img2img),
            ),
            const SizedBox(height: 8),
            _buildOption(
              context,
              icon: Icons.manage_search_rounded,
              title: context.l10n.gallery_sendToReversePromptTitle,
              subtitle: context.l10n.gallery_addToReversePromptModule,
              onTap: () =>
                  Navigator.of(context).pop(SendDestination.reversePrompt),
            ),
            const SizedBox(height: 8),
            // 发送到 Vibe Transfer
            _buildOption(
              context,
              icon: Icons.style,
              title: 'Vibe Transfer',
              subtitle: hasVibeData
                  ? context.l10n.gallery_applyVibeFromImage
                  : context.l10n.gallery_noVibeData,
              enabled: hasVibeData,
              onTap: hasVibeData
                  ? () =>
                      Navigator.of(context).pop(SendDestination.vibeTransfer)
                  : null,
            ),
            const SizedBox(height: 8),
            _buildOption(
              context,
              icon: Icons.brush_outlined,
              title: context.l10n.gallery_sendToKrita,
              subtitle: context.l10n.gallery_sendToConnectedKrita,
              onTap: () => Navigator.of(context).pop(SendDestination.krita),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.common_cancel),
        ),
      ],
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: enabled
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.38),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: enabled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.38,
                              ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.38,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                )
              else
                Icon(
                  Icons.block,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
