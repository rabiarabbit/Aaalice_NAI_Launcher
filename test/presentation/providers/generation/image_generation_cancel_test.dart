import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/data/datasources/remote/nai_image_generation_api_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/image/image_stream_chunk.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/providers/notification_settings_provider.dart';

class MockNAIImageGenerationApiService extends Mock
    implements NAIImageGenerationApiService {}

void main() {
  late Directory hiveTempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerFallbackValue(const ImageParams());
    hiveTempDir = await Directory.systemTemp.createTemp('nai_launcher_hive_');
    Hive.init(hiveTempDir.path);
    await Hive.openBox(StorageKeys.settingsBox);
    await Hive.openBox(StorageKeys.historyBox);
    await Hive.openBox(StorageKeys.statisticsCacheBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveTempDir.exists()) {
      await hiveTempDir.delete(recursive: true);
    }
  });

  test('cancelled generation must ignore late stream images after restart',
      () async {
    final mockApiService = MockNAIImageGenerationApiService();
    final firstStream = StreamController<ImageStreamChunk>();
    final secondStream = StreamController<ImageStreamChunk>();
    final staleImage = _validImageBytes(width: 512, height: 768);
    final freshImage = _validImageBytes(width: 640, height: 960);
    var streamCall = 0;

    when(
      () => mockApiService.generateImage(
        any(),
        onProgress: any(named: 'onProgress'),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer((_) async => (<Uint8List>[], <int, String>{}));
    when(
      () => mockApiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer((_) {
      streamCall += 1;
      return streamCall == 1 ? firstStream.stream : secondStream.stream;
    });
    when(() => mockApiService.cancelGeneration()).thenReturn(null);

    final container = ProviderContainer(
      overrides: [
        naiImageGenerationApiServiceProvider.overrideWithValue(mockApiService),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(notificationSettingsNotifierProvider.notifier)
        .setSoundEnabled(false);

    final notifier = container.read(imageGenerationNotifierProvider.notifier);
    final params = container.read(generationParamsNotifierProvider).copyWith(
          prompt: '1girl',
          width: 512,
          height: 768,
        );

    final firstGeneration = notifier.generate(params);
    await Future<void>.delayed(Duration.zero);

    notifier.cancel();

    final secondGeneration = notifier.generate(
      params.copyWith(width: 640, height: 960),
    );
    await Future<void>.delayed(Duration.zero);

    secondStream.add(ImageStreamChunk.complete(freshImage));
    await secondStream.close();
    await secondGeneration;

    firstStream.add(ImageStreamChunk.complete(staleImage));
    await firstStream.close();
    await firstGeneration;

    final state = container.read(imageGenerationNotifierProvider);
    expect(state.status, GenerationStatus.completed);
    expect(state.currentImages, hasLength(1));
    expect(state.currentImages.single.bytes, orderedEquals(freshImage));
    expect(state.displayImages, hasLength(1));
    expect(state.displayImages.single.bytes, orderedEquals(freshImage));
    expect(state.history, hasLength(1));
    expect(state.history.single.bytes, orderedEquals(freshImage));
  });
}

Uint8List _validImageBytes({
  required int width,
  required int height,
}) {
  return Uint8List.fromList(
    img.encodePng(
      img.Image(width: width, height: height),
    ),
  );
}
