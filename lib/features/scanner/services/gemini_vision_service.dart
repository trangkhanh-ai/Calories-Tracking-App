import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/food_analysis_result.dart';

/// Gửi ảnh món ăn lên backend (.NET) để phân tích dinh dưỡng.
/// Backend giữ Gemini API key và gọi Gemini Vision — client không giữ secret nào.
/// Response schema: xem docs/API_SPEC.md.
class GeminiVisionService {
  static const _analyzePath = '/analysis/food';
  static const _receiveTimeout = Duration(seconds: 60);

  Future<FoodAnalysisResult> analyzeImage(
    String imagePath, {
    int maxRetries = 3,
  }) async {
    final bytes = await XFile(imagePath).readAsBytes();
    return analyzeImageBytes(bytes, imagePath, maxRetries: maxRetries);
  }

  Future<FoodAnalysisResult> analyzeImageBytes(
    Uint8List imageBytes,
    String imagePath, {
    int maxRetries = 3,
  }) async {
    // Không nén ảnh ở client (package:image chạy đơn luồng trên Web, rất chậm).
    // Backend sẽ resize/nén trước khi gửi Gemini.
    final base64Image = base64Encode(imageBytes);

    Exception? lastError;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await _callBackend(base64Image, imagePath);
      } catch (e) {
        lastError = Exception('Lỗi phân tích: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    throw lastError ?? Exception('Không thể phân tích ảnh sau $maxRetries lần thử');
  }

  Future<FoodAnalysisResult> _callBackend(
    String base64Image,
    String imagePath,
  ) async {
    final response = await apiClient.post(
      _analyzePath,
      data: {'imageBase64': base64Image},
      options: Options(receiveTimeout: _receiveTimeout),
    );

    final data = response.data;
    final parsed = data is Map<String, dynamic>
        ? data
        : jsonDecode(data as String) as Map<String, dynamic>;
    return FoodAnalysisResult.fromJson(parsed, imagePath);
  }
}
