class FoodNutritionItem {
  final String id;
  final String name;
  final String sourceType;
  final String category;
  final String imageUrl;
  final String description;
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
    required this.category,
    this.imageUrl = '',
    this.description = '',
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

    final name = row['name']?.trim() ?? '';
    final category = row['category']?.trim().isNotEmpty == true
        ? row['category']!.trim()
        : _inferCategory(name);

    return FoodNutritionItem(
      id: row['fdc_id'] ?? '',
      name: name,
      sourceType: row['source_type']?.trim() ?? 'Unknown',
      category: category,
      imageUrl: row['image_url']?.trim() ?? '',
      description: row['description']?.trim() ?? '',
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
    final name = json['name']?.toString() ?? '';
    final resolvedCategory = json['category']?.toString() ?? _inferCategory(name);

    return FoodNutritionItem(
      id: json['fdcId']?.toString() ?? json['id']?.toString() ?? '',
      name: name,
      sourceType: json['sourceType']?.toString() ?? 'Unknown',
      category: resolvedCategory,
      imageUrl: json['imageUrl']?.toString() ?? json['image_url']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      calories: (json['calories'] as num?)?.toDouble(),
      protein: (json['protein'] as num?)?.toDouble(),
      carbs: (json['carbs'] as num?)?.toDouble(),
      fat: (json['fat'] as num?)?.toDouble(),
      sugar: (json['sugar'] as num?)?.toDouble(),
      fiber: (json['fiber'] as num?)?.toDouble(),
      sodium: (json['sodium'] as num?)?.toDouble(),
    );
  }

  static String _inferCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('pho') ||
        lower.contains('banh') ||
        lower.contains('goi') ||
        lower.contains('bun') ||
        lower.contains('com') ||
        lower.contains('nem')) {
      return 'Vietnamese';
    }
    if (lower.contains('chicken') ||
        lower.contains('salmon') ||
        lower.contains('beef') ||
        lower.contains('egg') ||
        lower.contains('tofu')) {
      return 'Proteins';
    }
    if (lower.contains('rice') ||
        lower.contains('pasta') ||
        lower.contains('bread') ||
        lower.contains('oat')) {
      return 'Grains';
    }
    if (lower.contains('banana') ||
        lower.contains('apple') ||
        lower.contains('orange') ||
        lower.contains('berry') ||
        lower.contains('avocado')) {
      return 'Fruit';
    }
    return 'General';
  }

  String get caloriesLabel => calories == null ? 'N/A' : '${calories!.toStringAsFixed(0)} kcal';
}
