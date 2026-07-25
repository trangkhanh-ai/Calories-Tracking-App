import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../profile/services/profile_api_service.dart';
import '../services/diary_api_service.dart';
import '../services/local_storage_service.dart';
import '../models/diary_dto.dart';
import 'package:dio/dio.dart';

enum DiaryStatus {
  loading,
  empty,
  cached,
  unauthorized,
  timeout,
  rateLimited,
  serverError,
  success
}

class DiaryState {
  final DiaryStatus status;
  final DailyDiaryDto? data;
  final String? errorMessage;

  DiaryState({required this.status, this.data, this.errorMessage});
}


final localStorageProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService();
});

final diaryApiServiceProvider = Provider<DiaryApiService>((ref) {
  return DiaryApiService();
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final dailyDiaryProvider = FutureProvider<DiaryState>((ref) async {
  final diaryService = ref.watch(diaryApiServiceProvider);
  final storage = ref.watch(localStorageProvider);
  final date = ref.watch(selectedDateProvider);

  try {
    // Primary: fetch directly from backend API (/api/diary/daily?date=...)
    final serverDiary = await diaryService.getDailyDiary(date);
    final allEntries = [
      ...serverDiary.breakfast,
      ...serverDiary.lunch,
      ...serverDiary.dinner,
      ...serverDiary.snacks,
    ];
    
    if (allEntries.isEmpty) {
      return DiaryState(status: DiaryStatus.empty, data: serverDiary);
    }
    return DiaryState(status: DiaryStatus.success, data: serverDiary);
  } on DioException catch (e) {
    DiaryStatus errorStatus = DiaryStatus.serverError;
    if (e.response?.statusCode == 401) {
      errorStatus = DiaryStatus.unauthorized;
    } else if (e.response?.statusCode == 429) {
      errorStatus = DiaryStatus.rateLimited;
    } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      errorStatus = DiaryStatus.timeout;
    }

    // Fallback: local storage when offline or unauthenticated
    double targetCalories = (await storage.getDailyGoal()).toDouble();
    try {
      final profile = await profileApiService.getProfile();
      final backendTarget = profile?['targetCalories'];
      if (backendTarget is num && backendTarget > 0) {
        targetCalories = backendTarget.toDouble();
        await storage.setDailyGoal(backendTarget.toInt());
      }
    } catch (_) {}

    final entries = await storage.loadEntries();
    final selectedDateStr = date.toIso8601String().split('T')[0];
    final todaysEntries = entries.where((e) {
      return e.date.toIso8601String().split('T')[0] == selectedDateStr;
    }).toList();

    double totalCalories = 0;
    List<MealItemDto> breakfast = [];
    List<MealItemDto> lunch = [];
    List<MealItemDto> dinner = [];
    List<MealItemDto> snacks = [];

    for (final entry in todaysEntries) {
      totalCalories += entry.calories;
      final item = MealItemDto(
        id: entry.id.hashCode,
        foodId: entry.id.hashCode,
        foodName: entry.name,
        quantity: 1.0,
        calories: entry.calories.toDouble(),
        mealType: entry.mealType,
      );

      switch (entry.mealType.toLowerCase()) {
        case 'breakfast':
          breakfast.add(item);
          break;
        case 'lunch':
          lunch.add(item);
          break;
        case 'dinner':
          dinner.add(item);
          break;
        default:
          snacks.add(item);
          break;
      }
    }

    final localData = DailyDiaryDto(
      date: date,
      totalCaloriesConsumed: totalCalories,
      targetCalories: targetCalories,
      breakfast: breakfast,
      lunch: lunch,
      dinner: dinner,
      snacks: snacks,
    );

    if (errorStatus == DiaryStatus.unauthorized || errorStatus == DiaryStatus.rateLimited) {
       return DiaryState(status: errorStatus, data: localData);
    }
    
    return DiaryState(status: DiaryStatus.cached, data: localData, errorMessage: 'Đang dùng dữ liệu ngoại tuyến.');
  } catch (e) {
    return DiaryState(status: DiaryStatus.serverError, errorMessage: e.toString());
  }
});

final weeklyStatsProvider = FutureProvider<List<DailyStatDto>>((ref) async {
  final diaryService = ref.watch(diaryApiServiceProvider);
  final storage = ref.watch(localStorageProvider);
  final end = DateTime.now();
  final start = end.subtract(const Duration(days: 6));

  try {
    // Primary: fetch from server
    final serverStats = await diaryService.getStats(start, end);
    if (serverStats.isNotEmpty) return serverStats;
  } catch (_) {}

  // Fallback to local entries calculation
  final entries = await storage.loadEntries();
  final Map<String, double> statsMap = {};
  for (var entry in entries) {
    if (entry.date.isAfter(start.subtract(const Duration(days: 1))) &&
        entry.date.isBefore(end.add(const Duration(days: 1)))) {
      final dateStr = DateFormat('yyyy-MM-dd').format(entry.date);
      statsMap[dateStr] = (statsMap[dateStr] ?? 0) + entry.calories.toDouble();
    }
  }

  final List<DailyStatDto> stats = [];
  for (var i = 0; i <= 6; i++) {
    final date = start.add(Duration(days: i));
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    stats.add(DailyStatDto(
      date: date,
      caloriesConsumed: statsMap[dateStr] ?? 0,
    ));
  }
  return stats;
});

class DailyGoalNotifier extends Notifier<int> {
  @override
  int build() {
    return 2000;
  }

  void updateGoal(int goal) {
    state = goal;
  }
}

final dailyGoalProvider = NotifierProvider<DailyGoalNotifier, int>(() => DailyGoalNotifier());
