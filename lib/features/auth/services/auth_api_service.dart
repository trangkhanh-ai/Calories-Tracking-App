import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

class AuthApiService {
  final Dio _dio;

  AuthApiService() : _dio = ApiClient().dio;

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'username': username,
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    return response.data;
  }
}
