import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/inpaint_outpaint_utils.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/image_editor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop Save and Close is disabled during outpaint commit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImageEditorScreen(
          initialSize: Size(128, 96),
          mode: ImageEditorMode.inpaint,
          title: 'Inpaint test',
          initialOutpaintCommitPending: true,
          initialShowLayerPanel: false,
        ),
      ),
    );
    await tester.pump();

    final saveButton = find.ancestor(
      of: find.text('完成'),
      matching: find.byType(FilledButton),
    );
    expect(saveButton, findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'outpaint source replacement failure rolls back screen transaction',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageEditorScreen(
            initialImage: _buildSolidPng(
              128,
              96,
              const Color(0xFFAA3322),
            ),
            mode: ImageEditorMode.inpaint,
            title: 'Inpaint test',
            initialShowLayerPanel: false,
            debugFailOutpaintSourceReplacement: true,
          ),
        ),
      );
      await _pumpForAsyncEditorWork(tester);
      await _pumpUntil(tester, () {
        final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
        return List<String>.from(state.debugLayerNames).contains('底图');
      });

      final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
      final previousLayerNames = List<String>.from(state.debugLayerNames);

      expect(state.debugCanvasSize, const Size(128, 96));
      expect(state.debugFocusedInpaintEnabled, isFalse);
      expect(state.debugHasOutpaintChanges, isFalse);
      expect(state.debugOutpaintSourceWidth, isNull);
      expect(state.debugOutpaintSourceHeight, isNull);

      await tester.runAsync(() async {
        await state.debugApplyOutpaintEdges(
          const OutpaintEdges(right: 32),
        );
      });
      await _pumpForAsyncEditorWork(tester);

      expect(state.debugCanvasSize, const Size(128, 96));
      expect(state.debugFocusedInpaintEnabled, isFalse);
      expect(state.debugHasOutpaintChanges, isFalse);
      expect(state.debugOutpaintSourceWidth, isNull);
      expect(state.debugOutpaintSourceHeight, isNull);
      expect(state.debugLayerNames, previousLayerNames);
      expect(state.debugLayerNames.where((name) => name == '蒙版'), isEmpty);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'outpaint source replacement failure does not disable focused inpaint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageEditorScreen(
            initialImage: _buildSolidPng(
              128,
              96,
              const Color(0xFFAA3322),
            ),
            existingFocusRect: const Rect.fromLTWH(16, 16, 48, 48),
            mode: ImageEditorMode.inpaint,
            title: 'Inpaint test',
            initialShowLayerPanel: false,
            debugFailOutpaintSourceReplacement: true,
          ),
        ),
      );
      await _pumpForAsyncEditorWork(tester);
      await _pumpUntil(tester, () {
        final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
        return List<String>.from(state.debugLayerNames).contains('底图');
      });

      final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
      final previousLayerNames = List<String>.from(state.debugLayerNames);

      expect(state.debugCanvasSize, const Size(128, 96));
      expect(state.debugFocusedInpaintEnabled, isTrue);

      await tester.runAsync(() async {
        await state.debugApplyOutpaintEdges(
          const OutpaintEdges(right: 32),
        );
      });
      await _pumpForAsyncEditorWork(tester);

      expect(state.debugCanvasSize, const Size(128, 96));
      expect(state.debugFocusedInpaintEnabled, isTrue);
      expect(state.debugHasOutpaintChanges, isFalse);
      expect(state.debugOutpaintSourceWidth, isNull);
      expect(state.debugOutpaintSourceHeight, isNull);
      expect(state.debugLayerNames, previousLayerNames);
      expect(state.debugLayerNames.where((name) => name == '蒙版'), isEmpty);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'later outpaint failure restores focused state, tool, selection and layers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageEditorScreen(
            initialImage: _buildSolidPng(
              128,
              96,
              const Color(0xFFAA3322),
            ),
            initialFocusedInpaintEnabled: true,
            mode: ImageEditorMode.inpaint,
            title: 'Inpaint test',
            initialShowLayerPanel: false,
            debugFailOutpaintAfterFocusedDisable: true,
          ),
        ),
      );
      await _pumpForAsyncEditorWork(tester);
      await _pumpUntil(tester, () {
        final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
        return List<String>.from(state.debugLayerNames).contains('底图');
      });

      final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
      state.debugSetToolById('brush');
      state.debugSetSelectionRect(const Rect.fromLTWH(12, 14, 30, 32));
      state.debugSetPreviewRect(const Rect.fromLTWH(20, 22, 36, 38));
      state.debugSetToolById('rect_selection');
      await tester.pump();

      final previousLayerNames = List<String>.from(state.debugLayerNames);
      final previousActiveLayerId = state.debugActiveLayerId as String?;
      final previousActiveLayerName = state.debugActiveLayerName as String?;

      expect(state.debugCanvasSize, const Size(128, 96));
      expect(state.debugFocusedInpaintEnabled, isTrue);
      expect(state.debugCurrentToolId, 'rect_selection');
      expect(state.debugSelectionBounds, const Rect.fromLTWH(12, 14, 30, 32));
      expect(state.debugPreviewBounds, const Rect.fromLTWH(20, 22, 36, 38));

      await tester.runAsync(() async {
        await state.debugApplyOutpaintEdges(
          const OutpaintEdges(right: 32),
        );
      });
      await _pumpForAsyncEditorWork(tester);

      expect(state.debugCanvasSize, const Size(128, 96));
      expect(state.debugFocusedInpaintEnabled, isTrue);
      expect(state.debugCurrentToolId, 'rect_selection');
      expect(state.debugSelectionBounds, const Rect.fromLTWH(12, 14, 30, 32));
      expect(state.debugPreviewBounds, const Rect.fromLTWH(20, 22, 36, 38));
      expect(state.debugHasOutpaintChanges, isFalse);
      expect(state.debugOutpaintSourceWidth, isNull);
      expect(state.debugOutpaintSourceHeight, isNull);
      expect(state.debugLayerNames, previousLayerNames);
      expect(state.debugLayerNames.where((name) => name == '蒙版'), isEmpty);
      expect(state.debugActiveLayerId, previousActiveLayerId);
      expect(state.debugActiveLayerName, previousActiveLayerName);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<void> _pumpForAsyncEditorWork(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 10; i++) {
    if (condition()) {
      return;
    }
    await _pumpForAsyncEditorWork(tester);
  }
  expect(condition(), isTrue);
}

Uint8List _buildSolidPng(int width, int height, Color color) {
  final image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgba8(
      (color.r * 255).round().clamp(0, 255),
      (color.g * 255).round().clamp(0, 255),
      (color.b * 255).round().clamp(0, 255),
      (color.a * 255).round().clamp(0, 255),
    ),
  );
  return Uint8List.fromList(img.encodePng(image));
}
