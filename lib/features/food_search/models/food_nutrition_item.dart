class FoodNutritionItem {
  final String id;
  final String name;
  final String sourceType;
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? sugar;
  final double? fiber;
  final double? sodium;

  const FoodNutritionItem({
    required this.id,
    required this.name,
    required this.sourceType,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sugar,
    required this.fiber,
    required this.sodium,
  });

  factory FoodNutritionItem.fromCsvRow(Map<String, String> row) {
    double? parseDouble(String? value) {
      if (value == null || value.trim().isEmpty) return null;
      return double.tryParse(value.trim());
    }

    return FoodNutritionItem(
      id: row['fdc_id'] ?? '',
      name: row['name']?.trim() ?? '',
      sourceType: row['source_type']?.trim() ?? 'Unknown',
      calories: parseDouble(row['kcal_100g']),
      protein: parseDouble(row['protein_100g']),
      carbs: parseDouble(row['carbs_100g']),
      fat: parseDouble(row['fat_100g']),
      sugar: parseDouble(row['sugar_100g']),
      fiber: parseDouble(row['fiber_100g']),
      sodium: parseDouble(row['sodium_mg_100g']),
    );
  }

  factory FoodNutritionItem.fromJson(Map<String, dynamic> json) {
    return FoodNutritionItem(
      id: json['fdcId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sourceType: json['sourceType']?.toString() ?? 'Unknown',
      calories: (json['calories'] as num?)?.toDouble(),
      protein: (json['protein'] as num?)?.toDouble(),
      carbs: (json['carbs'] as num?)?.toDouble(),
      fat: (json['fat'] as num?)?.toDouble(),
      sugar: (json['sugar'] as num?)?.toDouble(),
      fiber: (json['fiber'] as num?)?.toDouble(),
      sodium: (json['sodium'] as num?)?.toDouble(),
    );
  }

  String get caloriesLabel => calories == null ? 'N/A' : '${calories!.toStringAsFixed(0)} kcal';
}
