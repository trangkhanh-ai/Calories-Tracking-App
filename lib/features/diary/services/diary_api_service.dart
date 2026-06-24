import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../models/diary_dto.dart';

class DiaryApiService {
  Future<DailyDiaryDto> getDailyDiary(DateTime date) async {
    try {
      final dateString = date.toIso8601String().split('T')[0];
      final response = await apiClient.get('/diary/daily', queryParameters: {'date': dateString});
      return DailyDiaryDto.fromJson(response.data as Map<String, dynamic>?, date: date);
    } on DioException catch (_) {
      return DailyDiaryDto.empty(date: date);
    } catch (_) {
      return DailyDiaryDto.empty(date: date);
    }
  }

  Future<void> logMeal(LogMealRequest request) async {
    await apiClient.post('/diary', data: request.toJson());
  }

  Future<List<DailyStatDto>> getStats(DateTime startDate, DateTime endDate) async {
    final startString = startDate.toIso8601String().split('T')[0];
    final endString = endDate.toIso8601String().split('T')[0];
    final response = await apiClient.get(
      '/diary/stats',
      queryParameters: {'startDate': startString, 'endDate': endString},
    );
    
    return (response.data as List).map((e) => DailyStatDto.fromJson(e)).toList();
  }
}
