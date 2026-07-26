import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_application_1/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable adapter: each entry is applied to the corresponding attempt, and
/// the last entry repeats once the script runs out.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.script);

  /// Either an int status code, or a DioExceptionType to throw.
  final List<Object> script;

  final List<String> methods = [];

  int get callCount => methods.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = methods.length;
    methods.add(options.method);

    final step = script[index < script.length ? index : script.length - 1];

    if (step is DioExceptionType) {
      throw DioException(requestOptions: options, type: step);
    }

    final status = step as int;
    return ResponseBody.fromString(
      '{"ok":${status == 200}}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late List<Duration> observedDelays;

  /// Zero-duration delay so retry tests never sleep for the real 1s/2s backoff,
  /// while still recording what the policy asked for.
  Future<void> recordDelay(Duration duration) async {
    observedDelays.add(duration);
  }

  Dio buildClient(
    ScriptedAdapter adapter, {
    UnauthorizedCoordinator? coordinator,
    RetryPolicy policy = const RetryPolicy(),
  }) {
    return ApiClient.buildDio(
      adapter: adapter,
      coordinator: coordinator ?? UnauthorizedCoordinator(),
      policy: policy,
      delay: recordDelay,
      readToken: () async => 'test-token',
      clearToken: () async {},
    );
  }

  setUp(() {
    observedDelays = [];
  });

  group('GET retry', () {
    test('a transient failure followed by success resolves', () async {
      final adapter = ScriptedAdapter([DioExceptionType.connectionError, 200]);
      final dio = buildClient(adapter);

      final response = await dio.get('/diary/daily');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2, reason: '1 original + 1 retry');
    });

    test('retries are bounded at exactly 3 total attempts', () async {
      final adapter = ScriptedAdapter([DioExceptionType.connectionError]);
      final dio = buildClient(adapter);

      await expectLater(dio.get('/diary/daily'), throwsA(isA<DioException>()));

      expect(adapter.callCount, 3, reason: '1 original + 2 retries');
    });

    test('backoff is 1s then 2s', () async {
      final adapter = ScriptedAdapter([DioExceptionType.connectionError]);
      final dio = buildClient(adapter);

      await expectLater(dio.get('/diary/daily'), throwsA(isA<DioException>()));

      expect(observedDelays, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
    });

    test('503 is retried', () async {
      final adapter = ScriptedAdapter([503, 503, 200]);
      final dio = buildClient(adapter);

      final response = await dio.get('/diary/daily');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 3);
    });

    test('502 and 504 are retried', () async {
      for (final status in [502, 504]) {
        observedDelays = [];
        final adapter = ScriptedAdapter([status, 200]);
        final dio = buildClient(adapter);

        final response = await dio.get('/diary/daily');

        expect(response.statusCode, 200, reason: 'status $status should retry');
        expect(adapter.callCount, 2);
      }
    });

    test('a timeout is retried', () async {
      final adapter = ScriptedAdapter([DioExceptionType.receiveTimeout, 200]);
      final dio = buildClient(adapter);

      final response = await dio.get('/diary/daily');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('the final attempt metadata is preserved, not the first', () async {
      final adapter = ScriptedAdapter([DioExceptionType.connectionError, 503, 503]);
      final dio = buildClient(adapter);

      try {
        await dio.get('/diary/daily');
        fail('expected a DioException');
      } on DioException catch (error) {
        // Reports the last outcome (503), not the initial connection error.
        expect(error.response?.statusCode, 503);
      }
    });
  });

  group('methods that are never retried', () {
    test('POST is not retried', () async {
      final adapter = ScriptedAdapter([DioExceptionType.connectionError]);
      final dio = buildClient(adapter);

      await expectLater(
        dio.post('/diary', data: {'foodName': 'Phở'}),
        throwsA(isA<DioException>()),
      );

      // No endpoint carries an idempotency key, so a retried POST could
      // double-log a meal.
      expect(adapter.callCount, 1);
      expect(observedDelays, isEmpty);
    });

    test('PUT, PATCH, and DELETE are not retried', () async {
      for (final call in <Future<Response<dynamic>> Function(Dio)>[
        (dio) => dio.put('/profile', data: const {}),
        (dio) => dio.patch('/profile', data: const {}),
        (dio) => dio.delete('/diary/1'),
      ]) {
        final adapter = ScriptedAdapter([DioExceptionType.connectionError]);
        final dio = buildClient(adapter);

        await expectLater(call(dio), throwsA(isA<DioException>()));
        expect(adapter.callCount, 1);
      }
    });
  });

  group('statuses that are never retried', () {
    for (final status in [400, 401, 403, 404, 409, 413, 415, 429]) {
      test('$status is not retried', () async {
        final adapter = ScriptedAdapter([status]);
        final dio = buildClient(adapter);

        await expectLater(dio.get('/diary/daily'), throwsA(isA<DioException>()));

        expect(adapter.callCount, 1, reason: '$status must not be retried');
        expect(observedDelays, isEmpty);
      });
    }
  });

  group('cancellation', () {
    test('an explicit cancellation is not retried', () async {
      final adapter = ScriptedAdapter([DioExceptionType.cancel]);
      final dio = buildClient(adapter);

      await expectLater(dio.get('/diary/daily'), throwsA(isA<DioException>()));

      expect(adapter.callCount, 1);
    });

    test('cancelling during the backoff stops further attempts', () async {
      final adapter = ScriptedAdapter([DioExceptionType.connectionError]);
      final cancelToken = CancelToken();

      final dio = ApiClient.buildDio(
        adapter: adapter,
        coordinator: UnauthorizedCoordinator(),
        // Cancel while the interceptor is waiting out the backoff.
        delay: (_) async => cancelToken.cancel(),
        readToken: () async => null,
        clearToken: () async {},
      );

      await expectLater(
        dio.get('/diary/daily', cancelToken: cancelToken),
        throwsA(isA<DioException>()),
      );

      expect(adapter.callCount, 1, reason: 'the retry must be abandoned');
    });
  });

  group('401 handling', () {
    test('concurrent 401s trigger exactly one logout', () async {
      final coordinator = UnauthorizedCoordinator();
      var logoutCount = 0;

      coordinator.addListener(() async {
        logoutCount++;
        // Yield so overlapping notifications land while this one is in flight.
        await Future<void>.delayed(Duration.zero);
      });

      final adapter = ScriptedAdapter([401]);
      final dio = buildClient(adapter, coordinator: coordinator);

      await Future.wait([
        dio.get('/diary/daily').catchError((Object _) => Response(requestOptions: RequestOptions(path: '/'))),
        dio.get('/diary/stats').catchError((Object _) => Response(requestOptions: RequestOptions(path: '/'))),
        dio.get('/profile').catchError((Object _) => Response(requestOptions: RequestOptions(path: '/'))),
      ]);

      expect(logoutCount, 1, reason: 'three concurrent 401s must collapse into one logout');
    });

    test('the token is cleared on 401', () async {
      var cleared = 0;

      final adapter = ScriptedAdapter([401]);
      final dio = ApiClient.buildDio(
        adapter: adapter,
        coordinator: UnauthorizedCoordinator(),
        delay: recordDelay,
        readToken: () async => 'expired-token',
        clearToken: () async => cleared++,
      );

      await expectLater(dio.get('/diary/daily'), throwsA(isA<DioException>()));

      expect(cleared, 1);
    });

    test('a listener can be deregistered so it does not leak', () async {
      final coordinator = UnauthorizedCoordinator();
      var calls = 0;

      final remove = coordinator.addListener(() async => calls++);
      expect(coordinator.listenerCount, 1);

      remove();
      expect(coordinator.listenerCount, 0);

      await coordinator.notifyUnauthorized();
      expect(calls, 0);
    });

    test('a failing listener does not block the others', () async {
      final coordinator = UnauthorizedCoordinator();
      var secondRan = false;

      coordinator.addListener(() async => throw StateError('boom'));
      coordinator.addListener(() async => secondRan = true);

      await coordinator.notifyUnauthorized();

      expect(secondRan, isTrue);
    });

    test('sequential logouts each run once the previous completes', () async {
      final coordinator = UnauthorizedCoordinator();
      var calls = 0;

      coordinator.addListener(() async => calls++);

      await coordinator.notifyUnauthorized();
      await coordinator.notifyUnauthorized();

      // Single-flight applies to overlapping calls, not to a later, separate
      // session expiring again.
      expect(calls, 2);
    });
  });
}
