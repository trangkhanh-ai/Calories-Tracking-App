import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/diary_dto.dart';

class DiaryApiService {
  final Dio _dio;

  DiaryApiService({Dio? dio}) : _dio = dio ?? apiClient;

  Future<DailyDiaryDto> getDailyDiary(DateTime date) async {
    final dateString = date.toIso8601String().split('T')[0];
    final response = await _dio.get('/diary/daily', queryParameters: {'date': dateString});
    return DailyDiaryDto.fromJson(response.data as Map<String, dynamic>?, date: date);
  }

  /// Logs a meal and returns the server's view of that day, when the backend
  /// provides one.
  ///
  /// `POST /api/diary` now answers `{ message, diary }`. The `diary` field is
  /// optional here so the client still works against a backend that predates
  /// that change — callers treat a null result as "saved, state unknown" and
  /// refresh from the server.
  Future<DailyDiaryDto?> logMeal(LogMealRequest request) async {
    final response = await _dio.post('/diary', data: request.toJson());

    final body = response.data;
    if (body is! Map<String, dynamic>) {
      return null;
    }

    final diary = body['diary'];
    if (diary is! Map<String, dynamic>) {
      return null;
    }

    return DailyDiaryDto.fromJson(diary, date: request.date);
  }

  Future<List<DailyStatDto>> getStats(DateTime startDate, DateTime endDate) async {
    final startString = startDate.toIso8601String().split('T')[0];
    final endString = endDate.toIso8601String().split('T')[0];
    final response = await _dio.get(
      '/diary/stats',
      queryParameters: {'startDate': startString, 'endDate': endString},
    );

    if (response.data is! List) return [];
    return (response.data as List).map((e) => DailyStatDto.fromJson(e as Map<String, dynamic>)).toList();
  }
}
