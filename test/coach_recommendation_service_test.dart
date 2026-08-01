import 'package:flutter_application_1/features/coach/models/meal_suggestion.dart';
import 'package:flutter_application_1/features/coach/services/coach_recommendation_service.dart';
import 'package:flutter_application_1/features/diary/models/diary_dto.dart';
import 'package:flutter_application_1/features/food_search/models/food_nutrition_item.dart';
import 'package:flutter_test/flutter_test.dart';

const _chicken = FoodNutritionItem(
  id: 'chicken',
  name: 'Chicken Breast',
  sourceType: 'USDA',
  category: 'Proteins',
  calories: 165,
  protein: 31,
  carbs: 0,
  fat: 3.6,
  sugar: 0,
  fiber: 0,
  sodium: 74,
);

const _banana = FoodNutritionItem(
  id: 'banana',
  name: 'Banana',
  sourceType: 'USDA',
  category: 'Fruit',
  calories: 89,
  protein: 1.1,
  carbs: 22.8,
  fat: 0.3,
  sugar: 12.2,
  fiber: 2.6,
  sodium: 1,
);

const _pho = FoodNutritionItem(
  id: 'pho',
  name: 'Pho Bo',
  sourceType: 'USDA',
  category: 'Vietnamese',
  calories: 320,
  protein: 20,
  carbs: 44,
  fat: 8,
  sugar: 3,
  fiber: 3,
  sodium: 820,
);

const _unknown = FoodNutritionItem(
  id: 'unknown',
  name: 'Unknown',
  sourceType: 'USDA',
  category: 'General',
  calories: null,
  protein: null,
  carbs: null,
  fat: null,
  sugar: null,
  fiber: null,
  sodium: null,
);

void main() {
  final service = CoachRecommendationService();

  test('recommends food quantities that stay within remaining calories', () {
    final suggestions = service.recommend(
      diary: _diary(consumed: 900, target: 2000),
      foods: const [_chicken, _banana, _pho],
      now: DateTime(2026, 8, 1, 12),
    );

    expect(suggestions, isNotEmpty);
    expect(suggestions, hasLength(lessThanOrEqualTo(3)));
    expect(suggestions.every((item) => item.calories <= 1100), isTrue);
    expect(suggestions.first.mealType, 'Lunch');
    expect(suggestions.first, isA<MealSuggestion>());
  });

  test('returns no suggestions after the daily target is reached', () {
    expect(
      service.recommend(
        diary: _diary(consumed: 2000, target: 2000),
        foods: const [_chicken],
        now: DateTime(2026, 8, 1, 19),
      ),
      isEmpty,
    );
  });

  test('skips foods without usable calorie values', () {
    final suggestions = service.recommend(
      diary: _diary(consumed: 200, target: 2000),
      foods: const [_unknown, _banana],
      now: DateTime(2026, 8, 1, 8),
    );

    expect(
      suggestions.map((item) => item.food.name),
      isNot(contains('Unknown')),
    );
    expect(suggestions.first.mealType, 'Breakfast');
  });

  test('uses dinner and snack labels for their time windows', () {
    final foods = service.recommend(
      diary: _diary(consumed: 200, target: 2000),
      foods: const [_banana],
      now: DateTime(2026, 8, 1, 22),
    );
    final dinner = service.recommend(
      diary: _diary(consumed: 200, target: 2000),
      foods: const [_banana],
      now: DateTime(2026, 8, 1, 18),
    );

    expect(foods.first.mealType, 'Snack');
    expect(dinner.first.mealType, 'Dinner');
  });
}

DailyDiaryDto _diary({required double consumed, required double target}) {
  return DailyDiaryDto(
    date: DateTime(2026, 8, 1),
    totalCaloriesConsumed: consumed,
    targetCalories: target,
    breakfast: const [],
    lunch: const [],
    dinner: const [],
    snacks: const [],
  );
}
