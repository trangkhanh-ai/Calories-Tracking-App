import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/food_analysis_result.dart';
import '../../../shared/utils/constants.dart';

class GeminiVisionService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  static const String _systemPrompt = '''
Bạn là chuyên gia dinh dưỡng người Việt Nam. Hãy phân tích ảnh thức ăn và trả về JSON.
Ưu tiên nhận diện các món ăn Việt Nam (phở, bún, cơm, bánh mì, v.v.).

Trả về CHÍNH XÁC format JSON sau (không thêm markdown, không thêm text):
{
  "food_detected": true,
  "items": [
    {
      "name": "Tên món bằng tiếng Việt",
      "name_en": "English name",
      "serving_size": "Khẩu phần ước tính (VD: 1 bát / 300g)",
      "calories": 350,
      "protein_g": 15.5,
      "carbs_g": 45.0,
      "fat_g": 8.2,
      "confidence": 0.92
    }
  ],
  "image_quality": "good",
  "notes": "Ghi chú bổ sung nếu có"
}

Quy tắc:
- Nếu không thấy thức ăn: food_detected = false, items = []
- image_quality: "good" | "low_light" | "blurry"
- confidence: 0.0 đến 1.0
- Nếu có nhiều món: liệt kê tất cả trong mảng items
- calories và macros là ước tính cho 1 khẩu phần thông thường
''';

  Future<FoodAnalysisResult> analyzeImage(
    String imagePath, {
    int maxRetries = 3,
  }) async {
    final imageBytes = await XFile(imagePath).readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final mimeType = _getMimeType(imagePath);

    Exception? lastError;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _callGeminiApi(base64Image, mimeType, imagePath);
        return result;
      } catch (e) {
        lastError = Exception('Lỗi phân tích: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    throw lastError ?? Exception('Không thể phân tích ảnh sau $maxRetries lần thử');
  }

  Future<FoodAnalysisResult> analyzeImageBytes(
    Uint8List imageBytes,
    String imagePath, {
    int maxRetries = 3,
  }) async {
    final base64Image = base64Encode(imageBytes);
    const mimeType = 'image/jpeg';

    Exception? lastError;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _callGeminiApi(base64Image, mimeType, imagePath);
        return result;
      } catch (e) {
        lastError = Exception('Lỗi phân tích: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    throw lastError ?? Exception('Không thể phân tích ảnh sau $maxRetries lần thử');
  }

  Future<FoodAnalysisResult> _callGeminiApi(
    String base64Image,
    String mimeType,
    String imagePath,
  ) async {
    final apiKey = AppConstants.geminiApiKey;
    if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY') {
      throw Exception('Chưa cấu hình Gemini API Key. Xem file constants.dart');
    }

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': _systemPrompt},
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 8192,
        'responseMimeType': 'application/json',
      },
    };

    final response = await http
        .post(
          Uri.parse('$_baseUrl?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 429) {
      throw Exception('Rate limit exceeded (429)');
    }
    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = responseJson['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Không có phản hồi từ AI');
    }

    final content = candidates[0]['content']['parts'][0]['text'] as String;
    
    // Clean JSON if needed (remove markdown code blocks)
    String cleanJson = content.trim();
    if (cleanJson.startsWith('```')) {
      cleanJson = cleanJson
          .replaceFirst(RegExp(r'```json?\n?'), '')
          .replaceAll(RegExp(r'\n?```$'), '')
          .trim();
    }

    try {
      final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
      return FoodAnalysisResult.fromJson(parsed, imagePath);
    } catch (e) {
      throw Exception('Lỗi JSON ($e). Dữ liệu AI trả về: $cleanJson');
    }
  }

  String _getMimeType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
