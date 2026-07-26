import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_application_1/core/network/network_failure.dart';
import 'package:flutter_application_1/features/scanner/services/gemini_vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts calls so retry behaviour can be asserted exactly, and can fail a
/// configurable number of times before succeeding.
class MockDio extends Fake implements Dio {
  int statusCode = 200;
  dynamic responseData;

  /// Fail this many times, then return 200. Null means always use [statusCode].
  int? failuresBeforeSuccess;

  int postCallCount = 0;

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    postCallCount++;

    final shouldFail = failuresBeforeSuccess == null
        ? statusCode != 200
        : postCallCount <= failuresBeforeSuccess!;

    if (shouldFail) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: statusCode,
          data: responseData,
        ),
      );
    }

    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: responseData ?? {'foodName': 'Pho Bo', 'calories': 350},
    ) as Response<T>;
  }
}

void main() {
  late MockDio mockDio;
  late GeminiVisionService service;

  setUp(() {
    mockDio = MockDio();
    // Zero-duration delay keeps retry tests instant instead of sleeping for
    // the real 1s/2s backoff.
    service = GeminiVisionService(dio: mockDio, delay: (_) async {});
  });

  Future<Object?> capture(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (error) {
      return error;
    }
  }

  Future<Object?> analyze({int maxAttempts = GeminiVisionService.defaultMaxAttempts}) {
    return capture(() => service.analyzeImageBytes(
          Uint8List.fromList([1, 2, 3]),
          'test.jpg',
          maxAttempts: maxAttempts,
        ));
  }

  group('terminal statuses are surfaced without retrying', () {
    test('400 maps to ValidationFailure and shows the server detail', () async {
      mockDio.statusCode = 400;
      mockDio.responseData = {'detail': 'Ảnh không chứa thực phẩm.'};

      final error = await analyze();

      expect(error, isA<ValidationFailure>());
      expect((error! as NetworkFailure).message, contains('Ảnh không chứa thực phẩm.'));
      expect(mockDio.postCallCount, 1, reason: '400 must not be retried');
    });

    test('401 maps to UnauthorizedFailure', () async {
      mockDio.statusCode = 401;

      final error = await analyze();

      expect(error, isA<UnauthorizedFailure>());
      expect((error! as NetworkFailure).message, contains('Phiên đăng nhập đã hết hạn'));
      expect(mockDio.postCallCount, 1);
    });

    test('413 reports the 5 MB limit, not 20 MB', () async {
      mockDio.statusCode = 413;

      final error = await analyze();

      expect(error, isA<PayloadTooLargeFailure>());

      final message = (error! as NetworkFailure).message;
      expect(message, contains('5 MB'));
      // The old copy claimed 20MB, which never matched the server budget.
      expect(message, isNot(contains('20')));
      expect(mockDio.postCallCount, 1);
    });

    test('415 reports the supported image formats', () async {
      mockDio.statusCode = 415;

      final error = await analyze();

      expect(error, isA<UnsupportedMediaFailure>());

      final message = (error! as NetworkFailure).message;
      expect(message, contains('JPEG'));
      expect(message, contains('PNG'));
      expect(message, contains('WebP'));
      expect(mockDio.postCallCount, 1);
    });

    test('429 is never retried', () async {
      mockDio.statusCode = 429;

      final error = await analyze();

      expect(error, isA<RateLimitFailure>());
      expect(mockDio.postCallCount, 1, reason: 'retrying a rate limit deepens the hole');
    });
  });

  group('transient failures retry within a bounded count', () {
    test('503 retries up to the attempt limit then throws', () async {
      mockDio.statusCode = 503;

      final error = await analyze(maxAttempts: 3);

      expect(error, isA<ColdStartFailure>());
      expect(mockDio.postCallCount, 3, reason: '1 original + 2 retries');
    });

    test('a transient 502 followed by success returns the result', () async {
      mockDio.statusCode = 502;
      mockDio.failuresBeforeSuccess = 1;

      final result = await service.analyzeImageBytes(
        Uint8List.fromList([1, 2, 3]),
        'test.jpg',
      );

      expect(result, isNotNull);
      expect(mockDio.postCallCount, 2);
    });

    test('maxAttempts of 1 disables retrying entirely', () async {
      mockDio.statusCode = 503;

      final error = await analyze(maxAttempts: 1);

      expect(error, isA<ColdStartFailure>());
      expect(mockDio.postCallCount, 1);
    });
  });

  group('cancellation', () {
    test('a cancelled request is not retried', () async {
      final cancellingDio = _CancellingDio();
      final cancellingService = GeminiVisionService(
        dio: cancellingDio,
        delay: (_) async {},
      );

      final error = await capture(() => cancellingService.analyzeImageBytes(
            Uint8List.fromList([1, 2, 3]),
            'test.jpg',
          ));

      expect(error, isA<CancelledFailure>());
      expect(cancellingDio.postCallCount, 1);
    });
  });
}

/// Always throws a cancellation, so the retry branch must be skipped.
class _CancellingDio extends Fake implements Dio {
  int postCallCount = 0;

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    postCallCount++;
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.cancel,
    );
  }
}
