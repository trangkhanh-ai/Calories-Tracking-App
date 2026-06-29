import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_storage_service.dart';
import '../models/food_entry.dart';
import '../models/diary_dto.dart';

final localStorageProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService();
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final dailyDiaryProvider = FutureProvider<DailyDiaryDto>((ref) async {
  final storage = ref.watch(localStorageProvider);
  final date = ref.watch(selectedDateProvider);
  
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
    targetCalories: (await storage.getDailyGoal()).toDouble(),
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
