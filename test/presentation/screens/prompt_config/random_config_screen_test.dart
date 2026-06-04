import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nai_launcher/data/models/prompt/random_preset.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/random_preset_provider.dart';
import 'package:nai_launcher/presentation/screens/prompt_config/prompt_config_screen.dart';

void main() {
  late Directory hiveDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDir = await Directory.systemTemp.createTemp('random_config_screen_');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  testWidgets('random config screen exposes completed management actions',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          randomPresetNotifierProvider.overrideWith(
            _ScreenTestRandomPresetNotifier.new,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox(
            width: 1200,
            height: 800,
            child: PromptConfigScreen(),
          ),
        ),
      ),
    );

    await _pumpBounded(tester);

    expect(find.text('测试预设'), findsOneWidget);
    expect(find.text('全局人数设置'), findsOneWidget);
    expect(find.byTooltip('生成预览'), findsOneWidget);
    expect(find.byTooltip('导入/导出'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await _pumpBounded(tester);

    await tester.tap(find.text('新建预设...').last);
    await _pumpBounded(tester);

    expect(find.text('创建新预设'), findsOneWidget);

    Navigator.of(tester.element(find.byType(PromptConfigScreen))).pop();
    await _pumpBounded(tester);

    await tester.tap(find.byTooltip('导入/导出'));
    await _pumpBounded(tester);

    expect(find.text('导入预设'), findsOneWidget);
    expect(find.text('导出当前预设'), findsOneWidget);

    Navigator.of(tester.element(find.byType(PromptConfigScreen))).pop();
    await _pumpBounded(tester);

    await tester.tap(find.text('全局人数设置'));
    await _pumpBounded(tester);

    expect(find.text('人数类别配置'), findsOneWidget);

    Navigator.of(tester.element(find.byType(PromptConfigScreen))).pop();
    await _pumpBounded(tester);

    expect(find.text('人数类别配置'), findsNothing);

    await tester.tap(find.byTooltip('生成预览'));
    await _pumpBounded(tester);

    expect(find.text('预览生成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpBounded(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _ScreenTestRandomPresetNotifier extends RandomPresetNotifier {
  @override
  RandomPresetState build() {
    return RandomPresetState(
      presets: [_defaultPreset, _customPreset],
      selectedPresetId: _customPreset.id,
    );
  }
}

const _defaultPreset = RandomPreset(
  id: 'default',
  name: '默认预设',
  isDefault: true,
);

const _customPreset = RandomPreset(
  id: 'custom',
  name: '测试预设',
);
