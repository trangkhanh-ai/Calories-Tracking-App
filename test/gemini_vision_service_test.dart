import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_application_1/features/scanner/services/gemini_vision_service.dart';

class MockDio extends Fake implements Dio {
  int statusCode = 200;
  dynamic responseData;

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
    if (statusCode != 200) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
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
    );
  }
}

void main() {
  group('GeminiVisionService Status Code Error Handling Tests', () {
    late MockDio mockDio;
    late GeminiVisionService service;

    setUp(() {
      mockDio = MockDio();
      service = GeminiVisionService(dio: mockDio);
    });

    test('401 Unauthorized throws session expired message', () async {
      mockDio.statusCode = 401;
      expect(
        () => service.analyzeImageBytes(Uint8List.fromList([1, 2, 3]), 'test.jpg', maxRetries: 1),
        throwsA(predicate((e) => e.toString().contains('Phiên đăng nhập đã hết hạn'))),
      );
    });

    test('413 Payload Too Large throws image too large message', () async {
      mockDio.statusCode = 413;
      expect(
        () => service.analyzeImageBytes(Uint8List.fromList([1, 2, 3]), 'test.jpg', maxRetries: 1),
        throwsA(predicate((e) => e.toString().contains('Kích thước ảnh quá lớn'))),
      );
    });

    test('429 Too Many Requests throws rate limit exceeded message', () async {
      mockDio.statusCode = 429;
      expect(
        () => service.analyzeImageBytes(Uint8List.fromList([1, 2, 3]), 'test.jpg', maxRetries: 1),
        throwsA(predicate((e) => e.toString().contains('Đã đạt giới hạn phân tích'))),
      );
    });

    test('400 Bad Request throws invalid image or detail message', () async {
      mockDio.statusCode = 400;
      mockDio.responseData = {'detail': 'Invalid image'};
      expect(
        () => service.analyzeImageBytes(Uint8List.fromList([1, 2, 3]), 'test.jpg', maxRetries: 1),
        throwsA(predicate((e) => e.toString().contains('Lỗi dữ liệu: Invalid image'))),
      );
    });

    test('500 Internal Server Error retries and throws system busy message', () async {
      mockDio.statusCode = 500;
      expect(
        () => service.analyzeImageBytes(Uint8List.fromList([1, 2, 3]), 'test.jpg', maxRetries: 1),
        throwsA(predicate((e) => e.toString().contains('Dịch vụ AI bận'))),
      );
    });
  });
}
