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

  factory DailyDiaryDto.empty({required DateTime date, double targetCalories = 2000}) {
    return DailyDiaryDto(
      date: date,
      totalCaloriesConsumed: 0,
      targetCalories: targetCalories,
      breakfast: const [],
      lunch: const [],
      dinner: const [],
      snacks: const [],
    );
  }

  factory DailyDiaryDto.fromJson(Map<String, dynamic>? json, {DateTime? date}) {
    if (json == null || json.isEmpty) {
      return DailyDiaryDto.empty(date: date ?? DateTime.now());
    }

    final parsedDate = date ?? DateTime.tryParse(json['date']?.toString() ?? '');

    return DailyDiaryDto(
      date: parsedDate ?? DateTime.now(),
      totalCaloriesConsumed: _readDouble(json['totalCaloriesConsumed']),
      targetCalories: _readDouble(json['targetCalories'], fallback: 2000),
      breakfast: _readMealList(json['breakfast']),
      lunch: _readMealList(json['lunch']),
      dinner: _readMealList(json['dinner']),
      snacks: _readMealList(json['snacks']),
    );
  }

  static double _readDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static List<MealItemDto> _readMealList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().map((e) => MealItemDto.fromJson(e)).toList();
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
