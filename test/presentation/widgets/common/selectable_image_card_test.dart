import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/pro_context_menu.dart';
import 'package:nai_launcher/presentation/widgets/common/selectable_image_card.dart';

void main() {
  late Directory hiveTempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    hiveTempDir = await Directory.systemTemp.createTemp(
      'nai_launcher_selectable_card_hive_',
    );
    Hive.init(hiveTempDir.path);
    await Hive.openBox(StorageKeys.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveTempDir.exists()) {
      await hiveTempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await Hive.box(StorageKeys.settingsBox).clear();
  });

  testWidgets('hover actions should expose inpaint and upscale shortcuts',
      (tester) async {
    await tester.pumpWidget(_buildCardApp());

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.byType(SelectableImageCard)));
    await tester.pumpAndSettle();

    expect(find.byTooltip('局部重绘'), findsOneWidget);
    expect(find.byTooltip('放大'), findsOneWidget);
  });

  testWidgets('context menu should expose inpaint and upscale shortcuts',
      (tester) async {
    await tester.pumpWidget(_buildCardApp());

    final center = tester.getCenter(find.byType(SelectableImageCard));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(gesture.removePointer);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('局部重绘'), findsOneWidget);
    expect(find.text('放大'), findsOneWidget);
  });

  testWidgets('context menu closes before invoking route launching actions',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      _buildCardApp(
        navigatorKey: navigatorKey,
        onInpaint: () {
          navigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Text('inpaint route'),
              ),
            ),
          );
        },
      ),
    );

    final center = tester.getCenter(find.byType(SelectableImageCard));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(gesture.removePointer);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('局部重绘'));
    await tester.pumpAndSettle();

    expect(find.text('inpaint route'), findsOneWidget);
    expect(find.byType(ProContextMenu), findsNothing);
  });

  testWidgets('hover actions should expose generation destination shortcuts',
      (tester) async {
    await tester.pumpWidget(
      _buildCardApp(
        onReversePrompt: _noop,
        onImageToImage: _noop,
        onVibeTransfer: _noop,
        onPreciseReference: _noop,
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.byType(SelectableImageCard)));
    await tester.pumpAndSettle();

    expect(find.byTooltip('反推'), findsOneWidget);
    expect(find.byTooltip('图生图'), findsOneWidget);
    expect(find.byTooltip('风格迁移'), findsOneWidget);
    expect(find.byTooltip('精准参考'), findsOneWidget);
  });

  testWidgets('context menu should expose generation destination shortcuts',
      (tester) async {
    await tester.pumpWidget(
      _buildCardApp(
        onReversePrompt: _noop,
        onImageToImage: _noop,
        onVibeTransfer: _noop,
        onPreciseReference: _noop,
      ),
    );

    final center = tester.getCenter(find.byType(SelectableImageCard));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(gesture.removePointer);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('反推'), findsOneWidget);
    expect(find.text('图生图'), findsOneWidget);
    expect(find.text('风格迁移'), findsOneWidget);
    expect(find.text('精准参考'), findsOneWidget);
  });

  testWidgets('disabled hover effects should not expose hover action bar',
      (tester) async {
    await tester.pumpWidget(_buildCardApp(hoverEffectsEnabled: false));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.byType(SelectableImageCard)));
    await tester.pumpAndSettle();

    expect(find.byTooltip('局部重绘'), findsNothing);
    expect(find.byTooltip('放大'), findsNothing);
  });

  testWidgets('favorite button should appear at the top right and toggle',
      (tester) async {
    var toggled = false;
    await tester.pumpWidget(
      _buildCardApp(
        isFavorite: true,
        onFavoriteToggle: () => toggled = true,
      ),
    );

    expect(find.byTooltip('取消收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pump();

    expect(toggled, isTrue);
  });

  testWidgets('read-only card hides save and copy actions but keeps badge',
      (tester) async {
    await tester.pumpWidget(
      _buildCardApp(
        enableSaveAction: false,
        enableCopyAction: false,
        statusBadgeLabel: '失败快照',
        onInpaint: null,
        onUpscale: null,
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.byType(SelectableImageCard)));
    await tester.pumpAndSettle();

    expect(find.text('失败快照'), findsOneWidget);
    expect(find.byTooltip('保存'), findsNothing);
    expect(find.byTooltip('复制'), findsNothing);

    final center = tester.getCenter(find.byType(SelectableImageCard));
    final secondary = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(secondary.removePointer);
    await tester.pumpAndSettle();
    await secondary.up();
    await tester.pumpAndSettle();

    expect(find.text('保存图片'), findsNothing);
    expect(find.text('复制图片'), findsNothing);
    expect(find.byType(ProContextMenu), findsNothing);
  });
}

void _noop() {}

Widget _buildCardApp({
  bool hoverEffectsEnabled = true,
  bool isFavorite = false,
  bool enableSaveAction = true,
  bool enableCopyAction = true,
  String? statusBadgeLabel,
  VoidCallback? onFavoriteToggle,
  VoidCallback? onInpaint = _noop,
  VoidCallback? onUpscale = _noop,
  VoidCallback? onReversePrompt,
  VoidCallback? onImageToImage,
  VoidCallback? onVibeTransfer,
  VoidCallback? onPreciseReference,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 32, height: 32)),
  );

  return ProviderScope(
    child: MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            height: 160,
            child: SelectableImageCard(
              imageBytes: bytes,
              enableSelection: false,
              hoverEffectsEnabled: hoverEffectsEnabled,
              enableSaveAction: enableSaveAction,
              enableCopyAction: enableCopyAction,
              statusBadgeLabel: statusBadgeLabel,
              isFavorite: isFavorite,
              onFavoriteToggle: onFavoriteToggle,
              onInpaint: onInpaint,
              onUpscale: onUpscale,
              onReversePrompt: onReversePrompt,
              onImageToImage: onImageToImage,
              onVibeTransfer: onVibeTransfer,
              onPreciseReference: onPreciseReference,
            ),
          ),
        ),
      ),
    ),
  );
}
