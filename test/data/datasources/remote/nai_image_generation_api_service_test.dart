import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/network/nai_api_endpoint.dart';
import 'package:nai_launcher/core/network/nai_api_endpoint_service.dart';
import 'package:nai_launcher/data/datasources/remote/nai_image_enhancement_api_service.dart';
import 'package:nai_launcher/data/datasources/remote/nai_image_generation_api_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';

void main() {
  test('completed older request must not clear newer cancel token', () async {
    final adapter = _PendingDioAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final endpointService = NaiApiEndpointService();
    final service = NAIImageGenerationApiService(
      dio,
      NAIImageEnhancementApiService(dio, endpointService),
      endpointService,
    );

    final first = service.generateImage(
      const ImageParams(prompt: 'first request'),
    );
    final firstHandled = first.then<Object?>((_) => null).catchError(
          (_) => null,
        );
    await _waitForRequestCount(adapter, 1);

    final second = service.generateImage(
      const ImageParams(prompt: 'second request'),
    );
    final secondHandled = second.then<Object?>((_) => null).catchError(
          (_) => null,
        );
    await _waitForRequestCount(adapter, 2);

    adapter.requests[0].completeWithEmptyZip();
    await firstHandled;

    service.cancelGeneration();

    expect(
      await adapter.requests[1].cancelledWithin(
        const Duration(milliseconds: 100),
      ),
      isTrue,
    );

    adapter.requests[1].completeWithError(
      DioException(
        requestOptions: adapter.requests[1].options,
        type: DioExceptionType.cancel,
      ),
    );
    await secondHandled;
  });

  test('completed older stream request must not clear newer cancel token',
      () async {
    final adapter = _PendingDioAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final endpointService = NaiApiEndpointService();
    final service = NAIImageGenerationApiService(
      dio,
      NAIImageEnhancementApiService(dio, endpointService),
      endpointService,
    );

    final first = service
        .generateImageStream(const ImageParams(prompt: 'first stream'))
        .drain<Object?>();
    final firstHandled = first.then<Object?>((_) => null).catchError(
          (_) => null,
        );
    await _waitForRequestCount(adapter, 1);

    final second = service
        .generateImageStream(const ImageParams(prompt: 'second stream'))
        .drain<Object?>();
    final secondHandled = second.then<Object?>((_) => null).catchError(
          (_) => null,
        );
    await _waitForRequestCount(adapter, 2);

    adapter.requests[0].completeWithError(
      DioException(
        requestOptions: adapter.requests[0].options,
        type: DioExceptionType.cancel,
      ),
    );
    await firstHandled;

    service.cancelGeneration();

    expect(
      await adapter.requests[1].cancelledWithin(
        const Duration(milliseconds: 100),
      ),
      isTrue,
    );

    adapter.requests[1].completeWithError(
      DioException(
        requestOptions: adapter.requests[1].options,
        type: DioExceptionType.cancel,
      ),
    );
    await secondHandled;
  });

  test('stream cancelled before listen must not start a request', () async {
    final adapter = _PendingDioAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final endpointService = NaiApiEndpointService();
    final service = NAIImageGenerationApiService(
      dio,
      NAIImageEnhancementApiService(dio, endpointService),
      endpointService,
    );

    final stream = service.generateImageStream(
      const ImageParams(prompt: 'cancel before listen'),
    );
    service.cancelGeneration();

    final chunksFuture = stream.toList();
    await _waitForOptionalRequest(adapter);
    if (adapter.requests.isNotEmpty) {
      adapter.requests.single.completeWithEmptyStream();
    }
    final chunks = await chunksFuture.timeout(
      const Duration(milliseconds: 100),
    );

    expect(adapter.requests, isEmpty);
    expect(chunks, hasLength(1));
    expect(chunks.single.error, contains('Cancelled'));
  });

  test('cancelGeneration must abort the connection on the wire', () async {
    // 真实 socket 验证：取消必须让服务器观察到连接断开，
    // 否则 NovelAI 不会释放账号并发额度，后续请求持续 429。
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());

    final requestReceived = Completer<void>();
    final connectionClosed = Completer<void>();
    server.listen((socket) {
      socket.listen(
        (_) {
          if (!requestReceived.isCompleted) requestReceived.complete();
        },
        onDone: () {
          if (!connectionClosed.isCompleted) connectionClosed.complete();
        },
        onError: (_) {
          if (!connectionClosed.isCompleted) connectionClosed.complete();
        },
      );
    });

    // 与 imageGenerationDioClient 一致：默认 HTTP/1.1 适配器
    final dio = Dio();
    final endpointService = NaiApiEndpointService()
      ..setCurrent(
        NaiApiEndpointConfig.fromInput(
          mainBaseUrl: '127.0.0.1:${server.port}',
        ),
      );
    final service = NAIImageGenerationApiService(
      dio,
      NAIImageEnhancementApiService(dio, endpointService),
      endpointService,
    );

    final generation = service
        .generateImageStream(const ImageParams(prompt: 'abort on wire'))
        .drain<Object?>()
        .then<Object?>((_) => null)
        .catchError((_) => null);

    // 服务器已收到请求但故意不响应（模拟 NAI 正在排队出图）
    await requestReceived.future.timeout(const Duration(seconds: 10));
    expect(connectionClosed.isCompleted, isFalse);

    service.cancelGeneration();

    await connectionClosed.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => fail(
        'cancelGeneration() did not abort the connection: the server never '
        'observed a disconnect, so NovelAI would keep the per-account '
        'generation slot busy',
      ),
    );

    await generation;
  });
}

Future<void> _waitForOptionalRequest(_PendingDioAdapter adapter) async {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (adapter.requests.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForRequestCount(
  _PendingDioAdapter adapter,
  int expectedCount,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (adapter.requests.length >= expectedCount) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected $expectedCount request(s), got ${adapter.requests.length}.');
}

class _PendingDioAdapter implements HttpClientAdapter {
  final List<_PendingRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final request = _PendingRequest(options, cancelFuture);
    requests.add(request);
    return request.response.future;
  }

  @override
  void close({bool force = false}) {}
}

class _PendingRequest {
  _PendingRequest(this.options, Future<void>? cancelFuture) {
    cancelFuture?.then((_) {
      if (!_cancelled.isCompleted) {
        _cancelled.complete();
      }
    });
  }

  final RequestOptions options;
  final Completer<ResponseBody> response = Completer<ResponseBody>();
  final Completer<void> _cancelled = Completer<void>();

  Future<bool> cancelledWithin(Duration timeout) async {
    try {
      await _cancelled.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void completeWithEmptyZip() {
    final bytes = ZipEncoder().encode(Archive()) ?? const <int>[];
    response.complete(
      ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/x-zip-compressed'],
        },
      ),
    );
  }

  void completeWithEmptyStream() {
    response.complete(
      ResponseBody.fromBytes(
        const <int>[],
        200,
        headers: {
          Headers.contentTypeHeader: ['application/x-msgpack'],
        },
      ),
    );
  }

  void completeWithError(Object error) {
    response.completeError(error);
  }
}
