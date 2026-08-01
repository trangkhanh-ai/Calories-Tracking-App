import 'dart:math' as math;

import '../../diary/models/diary_dto.dart';
import '../../food_search/models/food_nutrition_item.dart';
import '../models/meal_suggestion.dart';

class CoachRecommendationService {
  static const double _maxMealCalories = 550;
  static const double _minQuantityGrams = 80;
  static const double _maxQuantityGrams = 350;

  List<MealSuggestion> recommend({
    required DailyDiaryDto diary,
    required List<FoodNutritionItem> foods,
    required DateTime now,
  }) {
    final targetCalories = diary.targetCalories.isFinite
        ? diary.targetCalories
        : 0;
    final consumedCalories = diary.totalCaloriesConsumed.isFinite
        ? diary.totalCaloriesConsumed
        : 0;
    final remainingCalories = math.max(0, targetCalories - consumedCalories);
    if (remainingCalories <= 0) return const [];

    final mealBudget = math.min(remainingCalories, _maxMealCalories);
    final mealType = _mealTypeForHour(now.hour);
    final suggestions = <MealSuggestion>[];

    for (final food in foods) {
      final caloriesPer100g = food.calories;
      if (caloriesPer100g == null ||
          !caloriesPer100g.isFinite ||
          caloriesPer100g <= 0) {
        continue;
      }

      final quantityGrams = (mealBudget / caloriesPer100g * 100)
          .clamp(_minQuantityGrams, _maxQuantityGrams)
          .toDouble();
      final calories = caloriesPer100g * quantityGrams / 100;
      if (calories > remainingCalories + 0.5) continue;

      suggestions.add(
        MealSuggestion(
          food: food,
          mealType: mealType,
          quantityGrams: quantityGrams,
          calories: calories,
          reason: 'Phu hop voi ngan sach calo con lai',
        ),
      );
    }

    suggestions.sort((a, b) {
      final calorieDifference = (a.calories - mealBudget).abs().compareTo(
        (b.calories - mealBudget).abs(),
      );
      if (calorieDifference != 0) return calorieDifference;

      final proteinA = a.food.protein ?? 0;
      final proteinB = b.food.protein ?? 0;
      final proteinDifference = proteinB.compareTo(proteinA);
      if (proteinDifference != 0) return proteinDifference;
      return a.food.name.compareTo(b.food.name);
    });

    return suggestions.take(3).toList(growable: false);
  }

  String _mealTypeForHour(int hour) {
    if (hour >= 5 && hour < 11) return 'Breakfast';
    if (hour >= 11 && hour < 16) return 'Lunch';
    if (hour >= 16 && hour < 21) return 'Dinner';
    return 'Snack';
  }
}
