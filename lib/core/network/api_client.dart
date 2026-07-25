import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/utils/constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late Dio dio;
  static void Function()? onUnauthorized;

  // Base URL đọc từ --dart-define=BACKEND_BASE_URL (mặc định localhost:5210).
  // Android Emulator: dùng --dart-define=BACKEND_BASE_URL=http://10.0.2.2:5210
  static String get baseUrl {
    final sanitized = AppConstants.sanitizeBackendBaseUrl(AppConstants.backendBaseUrl);
    return '$sanitized/api';
  }

  factory ApiClient() {
    return _instance;
  }

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('jwt_token');
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } catch (_) {
            // Ignore shared preferences failures in tests/offline contexts.
          }
          if (kDebugMode) {
            debugPrint('--> ${options.method} ${options.uri}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            debugPrint('<-- ${response.statusCode} ${response.requestOptions.uri}');
          }
          return handler.next(response);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            onUnauthorized?.call();
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('jwt_token');
            } catch (_) {}
          }
          
          // Retry logic cho GET/idempotent requests (Render cold-start)
          if (e.requestOptions.method.toUpperCase() == 'GET' && _shouldRetry(e)) {
            final retries = e.requestOptions.extra['retries'] as int? ?? 0;
            if (retries < 3) {
              if (kDebugMode) {
                debugPrint('Cold start retry: ${e.requestOptions.uri} (Attempt ${retries + 1})');
              }
              e.requestOptions.extra['retries'] = retries + 1;
              await Future.delayed(Duration(seconds: 2 * (retries + 1))); // exponential backoff
              try {
                final response = await dio.fetch(e.requestOptions);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                e = retryError;
              }
            }
          }

          if (kDebugMode) {
            debugPrint('<-- Error ${e.response?.statusCode} ${e.message}');
          }
          
          if (_isConnectionError(e)) {
            final customError = DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: 'Server đang khởi động (cold-start). Vui lòng chờ 1 phút rồi thử lại.',
            );
            return handler.next(customError);
          }
          
          return handler.next(e);
        },
      ),
    );
  }

  bool _shouldRetry(DioException e) {
    return e.type == DioExceptionType.connectionTimeout || 
           e.type == DioExceptionType.receiveTimeout || 
           e.type == DioExceptionType.sendTimeout ||
           e.type == DioExceptionType.connectionError ||
           e.response?.statusCode == 502 || 
           e.response?.statusCode == 503 || 
           e.response?.statusCode == 504;
  }
  
  bool _isConnectionError(DioException e) {
    return e.type == DioExceptionType.connectionTimeout || 
           e.type == DioExceptionType.receiveTimeout || 
           e.type == DioExceptionType.connectionError ||
           e.response?.statusCode == 502 || 
           e.response?.statusCode == 503;
  }
}

final apiClient = ApiClient().dio;
