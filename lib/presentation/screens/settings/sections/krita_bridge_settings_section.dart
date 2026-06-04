import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/krita/krita_bridge_notifier.dart';
import '../widgets/settings_card.dart';

class KritaBridgeSettingsSection extends ConsumerWidget {
  const KritaBridgeSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(kritaBridgeNotifierProvider);
    final notifier = ref.read(kritaBridgeNotifierProvider.notifier);

    return SettingsCard(
      title: 'Krita Bridge',
      icon: Icons.brush_outlined,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(_statusIcon(state.status)),
            title: const Text('启用 Krita 本地桥接'),
            subtitle: Text(_statusText(state)),
            value: state.enabled,
            onChanged: state.status == KritaBridgeStatus.starting
                ? null
                : (value) async {
                    await notifier.setEnabled(value);
                  },
          ),
          if (state.enabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.circle,
                size: 12,
                color: _statusColor(theme, state.status),
              ),
              title: Text(_statusLabel(state.status)),
              subtitle: Text(_connectionDetails(state)),
              trailing: TextButton.icon(
                onPressed: state.status == KritaBridgeStatus.starting
                    ? null
                    : () async {
                        await notifier.regenerateSession();
                      },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重生成会话'),
              ),
            ),
            if (state.discoveryFilePath != null)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('发现文件'),
                subtitle: SelectableText(state.discoveryFilePath!),
              ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _statusText(KritaBridgeState state) {
    return switch (state.status) {
      KritaBridgeStatus.disabled => '默认关闭；开启后只监听本机 127.0.0.1',
      KritaBridgeStatus.starting => '正在启动本地桥接服务...',
      KritaBridgeStatus.listening => '等待 Krita 插件连接',
      KritaBridgeStatus.connected => 'Krita 插件已连接',
      KritaBridgeStatus.error => '启动失败，请查看错误信息',
    };
  }

  String _statusLabel(KritaBridgeStatus status) {
    return switch (status) {
      KritaBridgeStatus.disabled => '已关闭',
      KritaBridgeStatus.starting => '启动中',
      KritaBridgeStatus.listening => '监听中',
      KritaBridgeStatus.connected => '已连接',
      KritaBridgeStatus.error => '错误',
    };
  }

  String _connectionDetails(KritaBridgeState state) {
    final endpoint = state.port == null
        ? '等待本地 WebSocket 监听'
        : 'ws://127.0.0.1:${state.port}/krita';
    final client = state.connectedClientLabel;
    if (client == null || client.isEmpty) {
      return endpoint;
    }
    return '$endpoint\n客户端：$client';
  }

  IconData _statusIcon(KritaBridgeStatus status) {
    return switch (status) {
      KritaBridgeStatus.connected => Icons.link,
      KritaBridgeStatus.listening => Icons.sensors,
      KritaBridgeStatus.starting => Icons.hourglass_top,
      KritaBridgeStatus.error => Icons.error_outline,
      KritaBridgeStatus.disabled => Icons.link_off,
    };
  }

  Color _statusColor(ThemeData theme, KritaBridgeStatus status) {
    return switch (status) {
      KritaBridgeStatus.connected => Colors.green,
      KritaBridgeStatus.listening => Colors.amber,
      KritaBridgeStatus.starting => theme.colorScheme.primary,
      KritaBridgeStatus.error => theme.colorScheme.error,
      KritaBridgeStatus.disabled => theme.colorScheme.outline,
    };
  }
}
