import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../../core/utils/file_explorer_utils.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/gallery/local_image_record.dart';

import '../common/app_toast.dart';

/// Image context menu for copy prompt/seed, open folder, delete
/// 图片右键菜单（复制Prompt/Seed、在文件夹中显示、删除）
class ImageContextMenu {
  /// Show the context menu
  /// 显示上下文菜单
  static Future<void> show(
    BuildContext context,
    LocalImageRecord record,
    Offset position, {
    VoidCallback? onDeleted,
    VoidCallback? onRefresh,
  }) async {
    final metadata = record.metadata;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (metadata?.prompt.isNotEmpty == true)
          PopupMenuItem(
            value: 'copy_prompt',
            child: Row(
              children: [
                const Icon(Icons.content_copy, size: 18),
                const SizedBox(width: 8),
                Text('${context.l10n.common_copy} Prompt'),
              ],
            ),
          ),
        if (metadata?.seed != null)
          PopupMenuItem(
            value: 'copy_seed',
            child: Row(
              children: [
                const Icon(Icons.tag, size: 18),
                const SizedBox(width: 8),
                Text('${context.l10n.common_copy} Seed'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              const Icon(Icons.folder_open, size: 18),
              const SizedBox(width: 8),
              Text(context.l10n.localGallery_showInFolder),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                context.l10n.common_delete,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );

    if (value == null || !context.mounted) return;

    switch (value) {
      case 'copy_prompt':
        if (metadata?.fullPrompt.isNotEmpty == true) {
          await Clipboard.setData(ClipboardData(text: metadata!.fullPrompt));
          if (context.mounted) {
            AppToast.info(context, context.l10n.localGallery_promptCopied);
          }
        }
        break;
      case 'copy_seed':
        if (metadata?.seed != null) {
          await Clipboard.setData(
            ClipboardData(text: metadata!.seed.toString()),
          );
          if (context.mounted) {
            AppToast.info(context, context.l10n.localGallery_seedCopied);
          }
        }
        break;
      case 'open_folder':
        await _openFileInFolder(context, record.path);
        break;
      case 'delete':
        await _confirmDeleteImage(context, record, onDeleted, onRefresh);
        break;
    }
  }

  /// Open file in folder
  /// 在文件夹中打开文件
  static Future<void> _openFileInFolder(
    BuildContext context,
    String filePath,
  ) async {
    try {
      await FileExplorerUtils.revealFile(filePath);
    } catch (e) {
      if (context.mounted) {
        AppToast.info(
          context,
          context.l10n.localGallery_cannotOpenFolder('$e'),
        );
      }
    }
  }

  /// Confirm delete image
  /// 确认删除图片
  static Future<void> _confirmDeleteImage(
    BuildContext context,
    LocalImageRecord record,
    VoidCallback? onDeleted,
    VoidCallback? onRefresh,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.common_confirmDelete),
        content: Text(
          context.l10n.localGallery_confirmDeleteImageContent(
            path.basename(record.path),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.common_cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final file = File(record.path);
        if (await file.exists()) {
          await file.delete();
          onDeleted?.call();
          onRefresh?.call();
          if (context.mounted) {
            AppToast.info(context, context.l10n.localGallery_imageDeleted);
          }
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.info(context, context.l10n.localGallery_deleteFailed('$e'));
        }
      }
    }
  }
}
