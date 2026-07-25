import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/shared/utils/constants.dart';
import 'package:flutter_application_1/core/network/api_client.dart';

void main() {
  group('AppConstants & ApiClient Base URL Sanitization Tests', () {
    test('sanitizeBackendBaseUrl handles standard URL without trailing slash', () {
      final sanitized = AppConstants.sanitizeBackendBaseUrl('http://localhost:5210');
      expect(sanitized, equals('http://localhost:5210'));
    });

    test('sanitizeBackendBaseUrl strips trailing slashes', () {
      final sanitized = AppConstants.sanitizeBackendBaseUrl('https://my-api.render.com/');
      expect(sanitized, equals('https://my-api.render.com'));
    });

    test('sanitizeBackendBaseUrl strips trailing /api and /api/', () {
      final sanitized1 = AppConstants.sanitizeBackendBaseUrl('https://my-api.render.com/api');
      final sanitized2 = AppConstants.sanitizeBackendBaseUrl('https://my-api.render.com/api/');
      expect(sanitized1, equals('https://my-api.render.com'));
      expect(sanitized2, equals('https://my-api.render.com'));
    });

    test('sanitizeBackendBaseUrl defaults empty or whitespace URL to http://localhost:5210', () {
      final sanitized1 = AppConstants.sanitizeBackendBaseUrl('');
      final sanitized2 = AppConstants.sanitizeBackendBaseUrl('   ');
      expect(sanitized1, equals('http://localhost:5210'));
      expect(sanitized2, equals('http://localhost:5210'));
    });

    test('ApiClient.baseUrl appends /api to sanitized base URL', () {
      final baseUrl = ApiClient.baseUrl;
      expect(baseUrl, endsWith('/api'));
      expect(baseUrl.contains('/api/api'), isFalse);
    });
  });
}
