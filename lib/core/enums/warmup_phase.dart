/// 预热阶段枚举
enum WarmupPhase {
  /// 关键阶段 - 必须同步完成，阻塞启动
  /// 目标: < 3秒
  critical,

  /// 快速阶段 - 完成后进入主界面
  /// 目标: < 7秒（累计 < 10秒）
  quick,

  /// 后台阶段 - 进入主界面后异步执行
  /// 无时间限制
  background,
}

extension WarmupPhaseExtension on WarmupPhase {
  String get displayName {
    switch (this) {
      case WarmupPhase.critical:
        return 'critical';
      case WarmupPhase.quick:
        return 'quick';
      case WarmupPhase.background:
        return 'background';
    }
  }

  /// 是否需要阻塞等待
  bool get isBlocking => this != WarmupPhase.background;
}
