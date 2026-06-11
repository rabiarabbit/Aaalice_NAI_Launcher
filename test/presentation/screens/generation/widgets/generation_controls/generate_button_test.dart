import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/cost_estimate_provider.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/generation_controls/generate_button.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  Future<void> pumpButton(
    WidgetTester tester, {
    required bool isGenerating,
    required bool showCancel,
    ImageGenerationState generationState = const ImageGenerationState(),
    VoidCallback? onGenerate,
    VoidCallback? onCancel,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Free generation hides the cost badge and avoids unrelated providers.
          isFreeGenerationProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: GenerateButtonWithCost(
                isGenerating: isGenerating,
                showCancel: showCancel,
                generationState: generationState,
                onGenerate: onGenerate ?? () {},
                onCancel: onCancel ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('idle: shows generate label and triggers onGenerate on tap',
      (tester) async {
    var generateCalled = false;
    var cancelCalled = false;
    await pumpButton(
      tester,
      isGenerating: false,
      showCancel: false,
      onGenerate: () => generateCalled = true,
      onCancel: () => cancelCalled = true,
    );

    expect(find.text(l10n.generation_generate), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(generateCalled, isTrue);
    expect(cancelCalled, isFalse);
  });

  testWidgets('generating: shows cancel label and triggers onCancel on tap',
      (tester) async {
    var generateCalled = false;
    var cancelCalled = false;
    await pumpButton(
      tester,
      isGenerating: true,
      showCancel: true,
      onGenerate: () => generateCalled = true,
      onCancel: () => cancelCalled = true,
    );

    expect(find.text(l10n.generation_cancel), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    expect(cancelCalled, isTrue);
    expect(generateCalled, isFalse);
  });

  testWidgets('generating multiple images: cancel label keeps batch progress',
      (tester) async {
    await pumpButton(
      tester,
      isGenerating: true,
      showCancel: true,
      generationState: const ImageGenerationState(
        currentImage: 2,
        totalImages: 4,
      ),
    );

    expect(find.text('${l10n.generation_cancel} 2/4'), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('generating without cancel (bridge busy): keeps generating label',
      (tester) async {
    await pumpButton(
      tester,
      isGenerating: true,
      showCancel: false,
    );

    expect(find.text(l10n.generation_generating), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
  });
}
