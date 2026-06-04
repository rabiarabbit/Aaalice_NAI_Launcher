import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/utils/app_logger.dart';
import '../../data/models/prompt/random_prompt_result.dart';
import '../../core/storage/local_storage_service.dart';

part 'random_mode_provider.g.dart';

const _defaultRandomGenerationMode = RandomGenerationMode.naiOfficial;

/// 将持久化字符串还原为随机生成模式。
///
/// 未知值回退到官网模式，避免旧版本或损坏配置阻断启动。
RandomGenerationMode randomGenerationModeFromStorage(String value) {
  return switch (value) {
    'nai_official' => RandomGenerationMode.naiOfficial,
    'custom' => RandomGenerationMode.custom,
    'hybrid' => RandomGenerationMode.hybrid,
    _ => _defaultRandomGenerationMode,
  };
}

/// 随机生成模式持久化值。
extension RandomGenerationModeStorageX on RandomGenerationMode {
  String toStorageValue() {
    return switch (this) {
      RandomGenerationMode.naiOfficial => 'nai_official',
      RandomGenerationMode.custom => 'custom',
      RandomGenerationMode.hybrid => 'hybrid',
    };
  }
}

/// 随机生成模式 Provider
///
/// 管理用户选择的随机提示词生成模式
@Riverpod(keepAlive: true)
class RandomModeNotifier extends _$RandomModeNotifier {
  @override
  RandomGenerationMode build() {
    final storage = ref.read(localStorageServiceProvider);
    return randomGenerationModeFromStorage(storage.getRandomGenerationMode());
  }

  /// 设置生成模式
  Future<void> setMode(RandomGenerationMode mode) async {
    final previousMode = state;
    state = mode;
    try {
      await ref
          .read(localStorageServiceProvider)
          .setRandomGenerationMode(mode.toStorageValue());
    } catch (e, stack) {
      state = previousMode;
      AppLogger.e('Failed to persist random generation mode', e, stack);
    }
  }

  /// 切换到官网模式
  Future<void> useNaiOfficial() {
    return setMode(RandomGenerationMode.naiOfficial);
  }

  /// 切换到自定义模式
  Future<void> useCustom() {
    return setMode(RandomGenerationMode.custom);
  }

  /// 切换到混合模式
  Future<void> useHybrid() {
    return setMode(RandomGenerationMode.hybrid);
  }

  /// 切换模式
  Future<void> toggle() {
    final nextMode = switch (state) {
      RandomGenerationMode.naiOfficial => RandomGenerationMode.custom,
      RandomGenerationMode.custom => RandomGenerationMode.hybrid,
      RandomGenerationMode.hybrid => RandomGenerationMode.naiOfficial,
    };
    return setMode(nextMode);
  }
}

/// 便捷 Provider：是否为官网模式
@riverpod
bool isNaiOfficialMode(Ref ref) {
  return ref.watch(randomModeNotifierProvider) ==
      RandomGenerationMode.naiOfficial;
}

/// 便捷 Provider：是否为自定义模式
@riverpod
bool isCustomMode(Ref ref) {
  return ref.watch(randomModeNotifierProvider) == RandomGenerationMode.custom;
}

/// 便捷 Provider：是否为混合模式
@riverpod
bool isHybridMode(Ref ref) {
  return ref.watch(randomModeNotifierProvider) == RandomGenerationMode.hybrid;
}

/// 模式显示信息
extension RandomGenerationModeExtension on RandomGenerationMode {
  /// 获取显示名称
  String get displayName {
    return switch (this) {
      RandomGenerationMode.naiOfficial => '官网模式',
      RandomGenerationMode.custom => '自定义模式',
      RandomGenerationMode.hybrid => '混合模式',
    };
  }

  /// 获取英文显示名称
  String get displayNameEn {
    return switch (this) {
      RandomGenerationMode.naiOfficial => 'NAI Official',
      RandomGenerationMode.custom => 'Custom',
      RandomGenerationMode.hybrid => 'Hybrid',
    };
  }

  /// 获取描述
  String get description {
    return switch (this) {
      RandomGenerationMode.naiOfficial => '复刻 NovelAI 官方随机算法，支持多角色联动',
      RandomGenerationMode.custom => '使用自定义预设生成提示词',
      RandomGenerationMode.hybrid => '官网算法 + 自定义词库',
    };
  }

  /// 获取英文描述
  String get descriptionEn {
    return switch (this) {
      RandomGenerationMode.naiOfficial =>
        'Replicate NovelAI official algorithm with multi-character support',
      RandomGenerationMode.custom => 'Generate prompts using custom presets',
      RandomGenerationMode.hybrid => 'Official algorithm + Custom tag library',
    };
  }

  /// 获取图标名称
  String get iconName {
    return switch (this) {
      RandomGenerationMode.naiOfficial => 'auto_awesome',
      RandomGenerationMode.custom => 'tune',
      RandomGenerationMode.hybrid => 'merge_type',
    };
  }
}
