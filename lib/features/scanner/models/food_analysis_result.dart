class NutritionInfo {
  final String name;
  final String nameEn;
  final String servingSize;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double confidence;

  const NutritionInfo({
    required this.name,
    required this.nameEn,
    required this.servingSize,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.confidence,
  });

  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    return NutritionInfo(
      name: json['name'] as String? ?? 'Món ăn',
      nameEn: json['name_en'] as String? ?? '',
      servingSize: json['serving_size'] as String? ?? '1 khẩu phần',
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
      carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
      fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  NutritionInfo copyWithScale(double scale) {
    return NutritionInfo(
      name: name,
      nameEn: nameEn,
      servingSize: servingSize,
      calories: calories * scale,
      proteinG: proteinG * scale,
      carbsG: carbsG * scale,
      fatG: fatG * scale,
      confidence: confidence,
    );
  }
}

class FoodAnalysisResult {
  final bool foodDetected;
  final List<NutritionInfo> items;
  final String imageQuality; // 'good' | 'low_light' | 'blurry'
  final String notes;
  final String imagePath;

  const FoodAnalysisResult({
    required this.foodDetected,
    required this.items,
    required this.imageQuality,
    required this.notes,
    required this.imagePath,
  });

  factory FoodAnalysisResult.fromJson(Map<String, dynamic> json, String imagePath) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    return FoodAnalysisResult(
      foodDetected: json['food_detected'] as bool? ?? false,
      items: itemsJson
          .map((e) => NutritionInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      imageQuality: json['image_quality'] as String? ?? 'good',
      notes: json['notes'] as String? ?? '',
      imagePath: imagePath,
    );
  }

  /// Returns the primary (first) item, or null if none
  NutritionInfo? get primaryItem => items.isNotEmpty ? items.first : null;
}
