/// 空状态类型
enum EmptyStateReason {
  searchNoResults,
  noFavorites,
  noItemsInCategory,
  defaultEmpty,
}

/// 空状态信息模型
///
/// 用于显示 Vibe 库空状态时的提示信息，包括标题、副标题和图标名称
/// 注意：使用 String 图标名称而非 IconData，避免数据层依赖 UI 框架
class EmptyStateInfo {
  /// 标题文本
  final String title;

  /// 副标题文本（可选）
  final String? subtitle;

  /// 图标名称（由展示层映射为实际的 IconData）
  final String iconName;

  /// 空状态类型，用于展示层按当前语言解析文案
  final EmptyStateReason reason;

  const EmptyStateInfo({
    required this.title,
    this.subtitle,
    required this.iconName,
    required this.reason,
  });

  /// 创建搜索无结果的空状态信息
  factory EmptyStateInfo.searchNoResults() {
    return const EmptyStateInfo(
      title: 'No matching Vibes',
      subtitle: 'Try a different keyword',
      iconName: 'search_off',
      reason: EmptyStateReason.searchNoResults,
    );
  }

  /// 创建收藏无结果的空状态信息
  factory EmptyStateInfo.noFavorites() {
    return const EmptyStateInfo(
      title: 'No favorite Vibes yet',
      subtitle: 'Click the heart icon to favorite a Vibe',
      iconName: 'favorite_border',
      reason: EmptyStateReason.noFavorites,
    );
  }

  /// 创建分类无结果的空状态信息
  factory EmptyStateInfo.noItemsInCategory() {
    return const EmptyStateInfo(
      title: 'No Vibes in this category',
      subtitle: 'Switch to "All Vibes" to see all entries',
      iconName: 'folder_outlined',
      reason: EmptyStateReason.noItemsInCategory,
    );
  }

  /// 创建默认无结果的空状态信息
  factory EmptyStateInfo.defaultEmpty() {
    return const EmptyStateInfo(
      title: 'No matching results',
      subtitle: null,
      iconName: 'search_off',
      reason: EmptyStateReason.defaultEmpty,
    );
  }

  EmptyStateInfo copyWith({
    String? title,
    String? subtitle,
    String? iconName,
    EmptyStateReason? reason,
  }) {
    return EmptyStateInfo(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      iconName: iconName ?? this.iconName,
      reason: reason ?? this.reason,
    );
  }

  @override
  String toString() {
    return 'EmptyStateInfo(title: $title, subtitle: $subtitle, iconName: $iconName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EmptyStateInfo &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.iconName == iconName;
  }

  @override
  int get hashCode => Object.hash(title, subtitle, iconName);
}
