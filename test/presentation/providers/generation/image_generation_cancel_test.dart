import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/network/dio_client.dart';
import 'package:nai_launcher/data/datasources/remote/nai_image_generation_api_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/image/image_stream_chunk.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/providers/notification_settings_provider.dart';

class MockNAIImageGenerationApiService extends Mock
    implements NAIImageGenerationApiService {}

/// 记录请求与取消状态的假 HTTP 适配器。
///
/// 响应永不返回，模拟仍在服务器上运行的 NAI 生成请求。
class _RecordingHttpAdapter implements HttpClientAdapter {
  final List<bool> cancelled = [];

  int get requestCount => cancelled.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final index = cancelled.length;
    cancelled.add(false);
    cancelFuture?.whenComplete(() => cancelled[index] = true);
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpUntil(
  bool Function() condition, {
  String? reason,
}) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(reason ?? 'Condition not met within timeout');
}

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

  test('immediate cancel before stream starts must not poison next generation',
      () async {
    final mockApiService = MockNAIImageGenerationApiService();
    final stream = StreamController<ImageStreamChunk>();
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
      return stream.stream;
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

    final cancelledGeneration = notifier.generate(params);
    notifier.cancel();
    await cancelledGeneration;

    final secondGeneration = notifier.generate(
      params.copyWith(width: 640, height: 960),
    );
    await Future<void>.delayed(Duration.zero);

    expect(streamCall, 1);

    stream.add(ImageStreamChunk.complete(freshImage));
    await stream.close();
    await secondGeneration;

    final state = container.read(imageGenerationNotifierProvider);
    expect(state.status, GenerationStatus.completed);
    expect(state.currentImages, hasLength(1));
    expect(state.currentImages.single.bytes, orderedEquals(freshImage));
    expect(state.history, hasLength(1));
    expect(state.history.single.bytes, orderedEquals(freshImage));
  });

  test(
      'non-cancelled batch cancelled error must surface instead of completing empty',
      () async {
    final mockApiService = MockNAIImageGenerationApiService();

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
    ).thenAnswer((_) => Stream.value(ImageStreamChunk.error('Cancelled')));
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
          nSamples: 2,
        );

    await notifier.generate(params);

    final state = container.read(imageGenerationNotifierProvider);
    expect(state.status, GenerationStatus.error);
    expect(state.currentImages, isEmpty);
    expect(state.history, isEmpty);
    expect(state.errorMessage, contains('Cancelled'));
  });

  test('single generation must not complete when stream and fallback are empty',
      () async {
    final mockApiService = MockNAIImageGenerationApiService();

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
    ).thenAnswer((_) => const Stream<ImageStreamChunk>.empty());
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
          nSamples: 1,
        );

    await notifier.generate(params);

    final state = container.read(imageGenerationNotifierProvider);
    expect(state.status, GenerationStatus.error);
    expect(state.currentImages, isEmpty);
    expect(state.displayImages, isEmpty);
    expect(state.history, isEmpty);
    expect(state.errorMessage, contains('No images returned'));
  });

  test('cancel must abort the in-flight HTTP request', () async {
    // 不替换 naiImageGenerationApiServiceProvider：走真实服务链路，
    // 复现 generate() 与 cancel() 分别 ref.read 服务实例的生产行为。
    final adapter = _RecordingHttpAdapter();
    final container = ProviderContainer(
      overrides: [
        imageGenerationDioClientProvider.overrideWithValue(
          Dio()..httpClientAdapter = adapter,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(notificationSettingsNotifierProvider.notifier)
        .setSoundEnabled(false);

    final notifier = container.read(imageGenerationNotifierProvider.notifier);
    final params = container.read(generationParamsNotifierProvider).copyWith(
          prompt: '1girl',
          nSamples: 1,
        );

    final firstGeneration = notifier.generate(params);
    await _pumpUntil(
      () => adapter.requestCount >= 1,
      reason: 'first generation never reached the HTTP layer',
    );

    notifier.cancel();
    await _pumpUntil(
      () => adapter.cancelled.first,
      reason: 'cancel() must cancel the CancelToken of the in-flight request; '
          'otherwise the orphaned generation keeps holding the NAI '
          'per-account concurrency slot and later generations fail with 429',
    );
    await firstGeneration;

    final secondGeneration = notifier.generate(params);
    await _pumpUntil(
      () => adapter.requestCount >= 2,
      reason: 'generation after cancel never reached the HTTP layer',
    );
    expect(adapter.cancelled[1], isFalse);

    notifier.cancel();
    await _pumpUntil(() => adapter.cancelled[1]);
    await secondGeneration;
  });

  test('429 concurrency limit must auto-retry until the slot frees', () async {
    final mockApiService = MockNAIImageGenerationApiService();
    final freshImage = _validImageBytes(width: 512, height: 768);
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
      if (streamCall == 1) {
        // 模拟孤儿任务仍占用 NAI 并发额度
        return Stream.value(
          ImageStreamChunk.error(
            'API_ERROR_429|A previous request is still being processed',
          ),
        );
      }
      return Stream.value(ImageStreamChunk.complete(freshImage));
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
          nSamples: 1,
        );

    await notifier.generate(params);

    final state = container.read(imageGenerationNotifierProvider);
    expect(streamCall, 2);
    expect(state.status, GenerationStatus.completed);
    expect(state.currentImages, hasLength(1));
    expect(state.currentImages.single.bytes, orderedEquals(freshImage));
  });

  test('cancel during 429 wait must stop retrying', () async {
    final mockApiService = MockNAIImageGenerationApiService();
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
      return Stream.value(
        ImageStreamChunk.error(
          'API_ERROR_429|A previous request is still being processed',
        ),
      );
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
          nSamples: 1,
        );

    final generation = notifier.generate(params);
    await _pumpUntil(() => streamCall >= 1);

    // 此刻位于 429 等待期内，取消必须终止自动重试
    notifier.cancel();
    await generation;

    expect(
      container.read(imageGenerationNotifierProvider).status,
      GenerationStatus.cancelled,
    );
    final callsAfterCancel = streamCall;
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    expect(streamCall, callsAfterCancel);
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
