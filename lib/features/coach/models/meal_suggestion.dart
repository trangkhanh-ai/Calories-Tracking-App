import '../../food_search/models/food_nutrition_item.dart';

class MealSuggestion {
  const MealSuggestion({
    required this.food,
    required this.mealType,
    required this.quantityGrams,
    required this.calories,
    required this.reason,
  });

  final FoodNutritionItem food;
  final String mealType;
  final double quantityGrams;
  final double calories;
  final String reason;

  String get quantityLabel => '${quantityGrams.round()} g';

  String get caloriesLabel => '${calories.round()} kcal';
}
