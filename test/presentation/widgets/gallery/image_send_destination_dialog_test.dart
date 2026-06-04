import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/gallery/image_send_destination_dialog.dart';

void main() {
  testWidgets('selecting Krita returns the Krita send destination', (
    tester,
  ) async {
    SendDestination? selected;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                selected = await ImageSendDestinationDialog.show(
                  context,
                  _record(),
                );
              },
              child: const Text('open dialog'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Krita'), findsOneWidget);
    expect(find.text('发送到已连接的 Krita 插件'), findsOneWidget);

    await tester.tap(find.text('Krita'));
    await tester.pumpAndSettle();

    expect(selected, SendDestination.krita);
  });
}

LocalImageRecord _record() {
  return LocalImageRecord(
    path: 'G:/gallery/image.png',
    size: 42,
    modifiedAt: DateTime(2026, 5, 10),
  );
}
