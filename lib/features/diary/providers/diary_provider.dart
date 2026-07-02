import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../profile/services/profile_api_service.dart';
import '../services/local_storage_service.dart';
import '../models/diary_dto.dart';

final localStorageProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService();
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

// LƯU Ý KIẾN TRÚC: các bữa ăn (entries) hiện lưu LOCAL (SharedPreferences).
// Backend có sẵn Diary API (/api/diary) nhưng client chưa nối — planned.
// Riêng MỤC TIÊU CALO ưu tiên lấy từ profile backend (user thiết lập qua
// /goal-setup); chỉ fallback về giá trị local khi offline/chưa đăng nhập.
final dailyDiaryProvider = FutureProvider<DailyDiaryDto>((ref) async {
  final storage = ref.watch(localStorageProvider);
  final date = ref.watch(selectedDateProvider);

  double targetCalories = (await storage.getDailyGoal()).toDouble();
  try {
    final profile = await profileApiService.getProfile();
    final backendTarget = profile?['targetCalories'];
    if (backendTarget is num && backendTarget > 0) {
      targetCalories = backendTarget.toDouble();
      await storage.setDailyGoal(backendTarget.toInt()); // đồng bộ cache local
    }
  } catch (_) {
    // Offline / backend không chạy: dùng giá trị local
  }

  final entries = await storage.loadEntries();
  
  // Filter for selected date
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

  return DailyDiaryDto(
    date: date,
    totalCaloriesConsumed: totalCalories,
    targetCalories: targetCalories,
    breakfast: breakfast,
    lunch: lunch,
    dinner: dinner,
    snacks: snacks,
  );
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
