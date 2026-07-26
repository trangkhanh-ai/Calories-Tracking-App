import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/network_failure.dart';
import '../models/food_analysis_result.dart';

/// Gửi ảnh món ăn lên backend (.NET) để phân tích dinh dưỡng.
/// Backend giữ Gemini API key và gọi Gemini Vision — client không giữ secret nào.
///
/// There is no direct Gemini SDK usage anywhere in the app: every analysis goes
/// through `POST /api/analysis/food`, which is why `google_generative_ai` has
/// been removed from pubspec.
class GeminiVisionService {
  static const _analyzePath = '/analysis/food';

  /// Analysis is slower than a normal request (image upload plus model
  /// inference), so it carries its own deadline rather than the client default.
  static const _receiveTimeout = Duration(seconds: 60);

  /// Attempts for transient failures only: 1 original + 2 retries.
  static const defaultMaxAttempts = 3;

  final Dio _dio;
  final Future<void> Function(Duration) _delay;

  GeminiVisionService({
    Dio? dio,
    Future<void> Function(Duration)? delay,
  })  : _dio = dio ?? apiClient,
        _delay = delay ?? _realDelay;

  static Future<void> _realDelay(Duration duration) => Future<void>.delayed(duration);

  Future<FoodAnalysisResult> analyzeImage(
    String imagePath, {
    int maxAttempts = defaultMaxAttempts,
    CancelToken? cancelToken,
  }) async {
    final bytes = await XFile(imagePath).readAsBytes();
    return analyzeImageBytes(
      bytes,
      imagePath,
      maxAttempts: maxAttempts,
      cancelToken: cancelToken,
    );
  }

  /// Analyses an image, retrying only genuinely transient failures.
  ///
  /// Never retried: 400, 401, 413, 415, 429, an explicit cancellation, or a
  /// successful response whose body is malformed. Retrying any of those wastes
  /// the user's rate-limit budget without changing the outcome.
  Future<FoodAnalysisResult> analyzeImageBytes(
    Uint8List imageBytes,
    String imagePath, {
    int maxAttempts = defaultMaxAttempts,
    CancelToken? cancelToken,
  }) async {
    final base64Image = base64Encode(imageBytes);
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;

    NetworkFailure? lastFailure;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await _callBackend(base64Image, imagePath, cancelToken);
      } on DioException catch (error) {
        final failure = NetworkFailure.fromDioException(error);

        // Terminal outcomes surface immediately.
        if (!failure.isRetryable) {
          throw failure;
        }

        lastFailure = failure;

        if (attempt < attempts) {
          // Linear backoff: 1s, then 2s.
          await _delay(Duration(seconds: attempt));
        }
      }
    }

    throw lastFailure ?? ServerFailure();
  }

  Future<FoodAnalysisResult> _callBackend(
    String base64Image,
    String imagePath,
    CancelToken? cancelToken,
  ) async {
    final response = await _dio.post(
      _analyzePath,
      data: {'imageBase64': base64Image},
      options: Options(receiveTimeout: _receiveTimeout),
      cancelToken: cancelToken,
    );

    final data = response.data;

    // A 200 with an unusable body is a contract violation, not a transient
    // fault — deliberately thrown outside the retry branch above.
    try {
      final parsed = data is Map<String, dynamic>
          ? data
          : jsonDecode(data as String) as Map<String, dynamic>;
      return FoodAnalysisResult.fromJson(parsed, imagePath);
    } on FormatException {
      throw ServerFailure();
    } on TypeError {
      throw ServerFailure();
    }
  }
}
