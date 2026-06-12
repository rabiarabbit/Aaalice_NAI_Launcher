import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/widgets/common/themed_button.dart';
import 'package:nai_launcher/presentation/widgets/common/anlas_cost_badge.dart';

/// 集成价格徽章的生成按钮
class GenerateButtonWithCost extends ConsumerWidget {
  final bool isGenerating;
  final bool showCancel;
  final ImageGenerationState generationState;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

  const GenerateButtonWithCost({
    super.key,
    required this.isGenerating,
    required this.showCancel,
    required this.generationState,
    required this.onGenerate,
    required this.onCancel,
  });

  String _labelText(BuildContext context) {
    final progress =
        '${generationState.currentImage}/${generationState.totalImages}';
    if (showCancel) {
      return generationState.totalImages > 1
          ? '${context.l10n.generation_cancel} $progress'
          : context.l10n.generation_cancel;
    }
    if (isGenerating) {
      return generationState.totalImages > 1
          ? progress
          : context.l10n.generation_generating;
    }
    return context.l10n.generation_generate;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 48,
      child: ThemedButton(
        onPressed: isGenerating ? onCancel : onGenerate,
        icon: showCancel
            ? const Icon(Icons.stop)
            : (isGenerating ? null : const Icon(Icons.auto_awesome)),
        isLoading: isGenerating && !showCancel,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_labelText(context)),
            AnlasCostBadge(isGenerating: isGenerating),
          ],
        ),
        style:
            showCancel ? ThemedButtonStyle.outlined : ThemedButtonStyle.filled,
      ),
    );
  }
}
