import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/utils/constants.dart';
import 'network_failure.dart';

/// Coordinates logout across concurrent 401 responses.
///
/// Replaces the previous mutable `static void Function()? onUnauthorized`,
/// where one listener silently overwrote another and state leaked between test
/// cases. Registration returns a disposer, and overlapping 401s collapse into a
/// single logout run.
class UnauthorizedCoordinator {
  UnauthorizedCoordinator();

  final List<Future<void> Function()> _listeners = [];

  /// The in-flight logout, if one is already running.
  Future<void>? _inFlight;

  /// Registers a logout handler and returns its disposer. Callers must invoke
  /// the disposer when torn down, or the handler outlives its owner.
  VoidCallback addListener(Future<void> Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Registered listener count. Exposed so tests can assert no leaks.
  @visibleForTesting
  int get listenerCount => _listeners.length;

  /// Clears every listener and any in-flight run. Test teardown only.
  @visibleForTesting
  void reset() {
    _listeners.clear();
    _inFlight = null;
  }

  /// Runs logout at most once even when several 401s land together.
  ///
  /// Later callers await the first run instead of starting their own, so the
  /// token is cleared once and the router is notified once.
  Future<void> notifyUnauthorized() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final run = _runListeners();
    _inFlight = run;

    return run.whenComplete(() {
      if (identical(_inFlight, run)) {
        _inFlight = null;
      }
    });
  }

  Future<void> _runListeners() async {
    // Snapshot first: a listener may deregister itself during logout.
    for (final listener in List.of(_listeners)) {
      try {
        await listener();
      } catch (error) {
        // One failing listener must not stop the others.
        if (kDebugMode) {
          debugPrint('Unauthorized listener failed: ${error.runtimeType}');
        }
      }
    }
  }
}

/// Bounded retry policy for idempotent requests.
class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 2,
    this.delays = const [Duration(seconds: 1), Duration(seconds: 2)],
  });

  /// Retries after the original attempt: 1 original + 2 retries = 3 attempts.
  final int maxRetries;

  /// Backoff before each retry. Index i is the wait before retry i+1.
  final List<Duration> delays;

  Duration delayFor(int retryNumber) {
    if (delays.isEmpty) return Duration.zero;
    final index = (retryNumber - 1).clamp(0, delays.length - 1);
    return delays[index];
  }
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();

  /// Shared app-wide so every service participates in the same single-flight
  /// logout.
  static final UnauthorizedCoordinator unauthorizedCoordinator = UnauthorizedCoordinator();

  late Dio dio;

  // Base URL đọc từ --dart-define=BACKEND_BASE_URL (mặc định localhost:5210).
  // Android Emulator: dùng --dart-define=BACKEND_BASE_URL=http://10.0.2.2:5210
  static String get baseUrl {
    final sanitized = AppConstants.sanitizeBackendBaseUrl(AppConstants.backendBaseUrl);
    return '$sanitized/api';
  }

  factory ApiClient() => _instance;

  ApiClient._internal() {
    dio = buildDio();
  }

  /// Builds a configured Dio. Exposed so tests can supply their own transport
  /// and a zero-duration delay instead of waiting on real backoff.
  @visibleForTesting
  static Dio buildDio({
    HttpClientAdapter? adapter,
    UnauthorizedCoordinator? coordinator,
    RetryPolicy policy = const RetryPolicy(),
    Future<void> Function(Duration)? delay,
    Future<String?> Function()? readToken,
    Future<void> Function()? clearToken,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // Render free instances cold-start slowly; 60s covers a wake-up without
        // showing the user a spurious timeout.
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }

    dio.interceptors.add(
      _ApiInterceptor(
        dio: dio,
        coordinator: coordinator ?? unauthorizedCoordinator,
        policy: policy,
        delay: delay ?? _realDelay,
        readToken: readToken ?? _readTokenFromPreferences,
        clearToken: clearToken ?? _clearTokenFromPreferences,
      ),
    );

    return dio;
  }

  static Future<void> _realDelay(Duration duration) => Future<void>.delayed(duration);

  static Future<String?> _readTokenFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (_) {
      // Missing platform channels in tests/offline contexts are not an error.
      return null;
    }
  }

  static Future<void> _clearTokenFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
    } catch (_) {
      // Best effort: auth state is cleared regardless.
    }
  }
}

class _ApiInterceptor extends Interceptor {
  _ApiInterceptor({
    required this.dio,
    required this.coordinator,
    required this.policy,
    required this.delay,
    required this.readToken,
    required this.clearToken,
  });

  static const _retryCountKey = 'retryCount';

  final Dio dio;
  final UnauthorizedCoordinator coordinator;
  final RetryPolicy policy;
  final Future<void> Function(Duration) delay;
  final Future<String?> Function() readToken;
  final Future<void> Function() clearToken;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    if (kDebugMode) {
      // Method and path only — never headers or body.
      debugPrint('--> ${options.method} ${options.path}');
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('<-- ${response.statusCode} ${response.requestOptions.path}');
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException error, ErrorInterceptorHandler handler) async {
    if (error.response?.statusCode == 401) {
      await clearToken();
      // Awaiting rather than fire-and-forget keeps auth state and navigation
      // consistent, and collapses concurrent 401s into one logout.
      await coordinator.notifyUnauthorized();
    }

    if (kDebugMode) {
      // Status and path only — no Authorization header, no body.
      debugPrint('<-- Error ${error.response?.statusCode} ${error.requestOptions.path}');
    }

    if (_shouldRetry(error)) {
      final attempted = (error.requestOptions.extra[_retryCountKey] as int?) ?? 0;
      final next = attempted + 1;

      if (next <= policy.maxRetries) {
        try {
          await delay(policy.delayFor(next));
        } on Object {
          // A cancelled delay stops the retry chain immediately.
          return handler.next(error);
        }

        // Re-check after the wait: the caller may have cancelled meanwhile.
        if (error.requestOptions.cancelToken?.isCancelled ?? false) {
          return handler.next(error);
        }

        final options = error.requestOptions..extra[_retryCountKey] = next;

        try {
          final response = await dio.fetch(options);
          return handler.resolve(response);
        } on DioException catch (retryError) {
          // Preserve the final attempt's metadata, not the first attempt's.
          return handler.next(retryError);
        }
      }
    }

    handler.next(error);
  }

  /// Retries only idempotent methods, and only on transient transport or
  /// gateway failures.
  ///
  /// Never retries POST/PUT/PATCH/DELETE — no endpoint carries an idempotency
  /// key, so a retried write could duplicate a diary entry. Never retries
  /// 400/401/403/404/409/413/415/429 or a client cancellation either: those
  /// outcomes do not change by asking again.
  bool _shouldRetry(DioException error) {
    const idempotentMethods = {'GET', 'HEAD', 'OPTIONS'};
    if (!idempotentMethods.contains(error.requestOptions.method.toUpperCase())) {
      return false;
    }

    if (error.type == DioExceptionType.cancel) {
      return false;
    }

    if (error.requestOptions.cancelToken?.isCancelled ?? false) {
      return false;
    }

    return NetworkFailure.fromDioException(error).isRetryable;
  }
}

final apiClient = ApiClient().dio;
