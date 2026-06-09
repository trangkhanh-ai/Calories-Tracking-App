class MealItemDto {
  final int id;
  final int foodId;
  final String foodName;
  final double quantity;
  final double calories;
  final String mealType;

  MealItemDto({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.quantity,
    required this.calories,
    required this.mealType,
  });

  factory MealItemDto.fromJson(Map<String, dynamic> json) {
    return MealItemDto(
      id: json['id'],
      foodId: json['foodId'],
      foodName: json['foodName'],
      quantity: (json['quantity'] as num).toDouble(),
      calories: (json['calories'] as num).toDouble(),
      mealType: json['mealType'],
    );
  }
}

class DailyDiaryDto {
  final DateTime date;
  final double totalCaloriesConsumed;
  final double targetCalories;
  final List<MealItemDto> breakfast;
  final List<MealItemDto> lunch;
  final List<MealItemDto> dinner;
  final List<MealItemDto> snacks;

  DailyDiaryDto({
    required this.date,
    required this.totalCaloriesConsumed,
    required this.targetCalories,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.snacks,
  });

  factory DailyDiaryDto.fromJson(Map<String, dynamic> json) {
    return DailyDiaryDto(
      date: DateTime.parse(json['date']),
      totalCaloriesConsumed: (json['totalCaloriesConsumed'] as num).toDouble(),
      targetCalories: (json['targetCalories'] as num).toDouble(),
      breakfast: (json['breakfast'] as List).map((e) => MealItemDto.fromJson(e)).toList(),
      lunch: (json['lunch'] as List).map((e) => MealItemDto.fromJson(e)).toList(),
      dinner: (json['dinner'] as List).map((e) => MealItemDto.fromJson(e)).toList(),
      snacks: (json['snacks'] as List).map((e) => MealItemDto.fromJson(e)).toList(),
    );
  }
}

class LogMealRequest {
  final String foodName;
  final double caloriesPer100g;
  final double quantity;
  final String mealType;
  final DateTime date;

  LogMealRequest({
    required this.foodName,
    required this.caloriesPer100g,
    required this.quantity,
    required this.mealType,
    required this.date,
  });

  Map<String, dynamic> toJson() {
    return {
      'foodName': foodName,
      'caloriesPer100g': caloriesPer100g,
      'quantity': quantity,
      'mealType': mealType,
      'date': date.toIso8601String(),
    };
  }
}

class DailyStatDto {
  final DateTime date;
  final double caloriesConsumed;

  DailyStatDto({
    required this.date,
    required this.caloriesConsumed,
  });

  factory DailyStatDto.fromJson(Map<String, dynamic> json) {
    return DailyStatDto(
      date: DateTime.parse(json['date']),
      caloriesConsumed: (json['caloriesConsumed'] as num).toDouble(),
    );
  }
}
