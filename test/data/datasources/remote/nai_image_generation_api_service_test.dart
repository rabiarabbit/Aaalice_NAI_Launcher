import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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

  void completeWithError(Object error) {
    response.completeError(error);
  }
}
