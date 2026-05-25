import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/krita/krita_outbound_image.dart';
import '../providers/krita/krita_bridge_notifier.dart';
import '../widgets/common/app_toast.dart';

class KritaSendHelper {
  const KritaSendHelper._();

  static void sendImageBytes(
    BuildContext context,
    WidgetRef ref,
    Uint8List imageBytes, {
    required String name,
  }) {
    final outboundImage = _prepareImage(context, imageBytes, name);
    if (outboundImage == null) {
      return;
    }

    final sent = ref
        .read(kritaBridgeNotifierProvider.notifier)
        .sendImageToKrita(outboundImage.bytes, name: outboundImage.name);
    if (!sent) {
      AppToast.warning(context, 'Krita 未连接，请先在设置中启用桥接并连接插件');
      return;
    }

    AppToast.success(context, '图片已发送到 Krita');
  }

  static KritaOutboundImage? _prepareImage(
    BuildContext context,
    Uint8List imageBytes,
    String name,
  ) {
    try {
      return KritaOutboundImage.prepare(imageBytes, name: name);
    } on FormatException {
      AppToast.warning(context, '图片格式无法发送到 Krita，请换用常见图片格式');
      return null;
    }
  }
}
