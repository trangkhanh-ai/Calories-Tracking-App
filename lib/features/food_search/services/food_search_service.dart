import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../models/food_nutrition_item.dart';

class FoodSearchService {
  FoodSearchService({String? csvContent}) : _csvContent = csvContent;

  static final instance = FoodSearchService();
  final String? _csvContent;
  List<FoodNutritionItem> _foods = <FoodNutritionItem>[];

  Future<void> loadFoods() async {
    if (_foods.isNotEmpty) return;

    if (_csvContent != null && _csvContent!.trim().isNotEmpty) {
      _foods = _parseCsv(_csvContent!);
      return;
    }

    try {
      final response = await apiClient.get(
        '/food/search',
        queryParameters: {
          'query': '',
          'limit': 50,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data is List ? response.data : <dynamic>[];
        _foods = data.map((json) => FoodNutritionItem.fromJson(json)).toList();
        return;
      }
    } catch (e) {
      // Ignore API failures; the service falls back to the bundled catalog.
    }

    _foods = _fallbackFoods();
  }

  Future<List<FoodNutritionItem>> searchFoods(
    String query, {
    int limit = 15,
    String? category,
    double? maxCalories,
    double? minProtein,
    double? maxProtein,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final baseFoods = _foods.isEmpty ? await _ensureFoodsLoaded() : _foods;
    final filtered = baseFoods.where((food) {
      final matchesQuery = normalizedQuery.isEmpty ||
          food.name.toLowerCase().contains(normalizedQuery) ||
          food.category.toLowerCase().contains(normalizedQuery) ||
          (food.description.isNotEmpty && food.description.toLowerCase().contains(normalizedQuery));
      final matchesCategory = category == null || category.trim().isEmpty ||
          food.category.toLowerCase() == category.toLowerCase();
      final matchesCalories = maxCalories == null || food.calories == null || food.calories! <= maxCalories;
      final matchesProtein = (minProtein == null || food.protein == null || food.protein! >= minProtein) &&
          (maxProtein == null || food.protein == null || food.protein! <= maxProtein);
      return matchesQuery && matchesCategory && matchesCalories && matchesProtein;
    }).toList();

    filtered.sort((a, b) {
      final queryMatchA = a.name.toLowerCase().startsWith(normalizedQuery) ? 0 : 1;
      final queryMatchB = b.name.toLowerCase().startsWith(normalizedQuery) ? 0 : 1;
      if (queryMatchA != queryMatchB) return queryMatchA.compareTo(queryMatchB);
      final categoryA = a.category.toLowerCase();
      final categoryB = b.category.toLowerCase();
      if (categoryA != categoryB) return categoryA.compareTo(categoryB);
      return (a.calories ?? double.infinity).compareTo(b.calories ?? double.infinity);
    });

    return filtered.take(limit).toList();
  }

  Future<List<FoodNutritionItem>> _ensureFoodsLoaded() async {
    await loadFoods();
    return _foods;
  }

  List<FoodNutritionItem> _parseCsv(String csv) {
    final rows = const LineSplitter().convert(csv);
    if (rows.isEmpty) return <FoodNutritionItem>[];

    final header = rows.first.split(',');
    final parsed = <FoodNutritionItem>[];
    for (final row in rows.skip(1)) {
      if (row.trim().isEmpty) continue;
      final values = row.split(',');
      final map = <String, String>{};
      for (var i = 0; i < header.length && i < values.length; i++) {
        map[header[i].trim()] = values[i].trim();
      }
      parsed.add(FoodNutritionItem.fromCsvRow(map));
    }
    return parsed;
  }

  List<FoodNutritionItem> _fallbackFoods() {
    return [
      const FoodNutritionItem(
        id: 'pho',
        name: 'Pho Bo',
        sourceType: 'Branded',
        category: 'Vietnamese',
        imageUrl: 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=400&q=80',
        description: 'Classic Vietnamese beef noodle soup.',
        calories: 320,
        protein: 20,
        carbs: 44,
        fat: 8,
        sugar: 3,
        fiber: 3,
        sodium: 820,
      ),
      const FoodNutritionItem(
        id: 'banh-mi',
        name: 'Banh Mi',
        sourceType: 'Branded',
        category: 'Vietnamese',
        imageUrl: 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=400&q=80',
        description: 'Vietnamese sandwich with pickled vegetables.',
        calories: 410,
        protein: 18,
        carbs: 48,
        fat: 14,
        sugar: 5,
        fiber: 5,
        sodium: 780,
      ),
      const FoodNutritionItem(
        id: 'bun-cha',
        name: 'Bun Cha',
        sourceType: 'Branded',
        category: 'Vietnamese',
        imageUrl: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=400&q=80',
        description: 'Grilled pork with rice noodles.',
        calories: 450,
        protein: 25,
        carbs: 50,
        fat: 16,
        sugar: 4,
        fiber: 4,
        sodium: 760,
      ),
      const FoodNutritionItem(
        id: 'banana',
        name: 'Banana',
        sourceType: 'Branded',
        category: 'Fruit',
        imageUrl: 'https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?auto=format&fit=crop&w=400&q=80',
        description: 'A sweet tropical fruit with natural sugars.',
        calories: 89,
        protein: 1.1,
        carbs: 22.8,
        fat: 0.3,
        sugar: 12.2,
        fiber: 2.6,
        sodium: 1,
      ),
      const FoodNutritionItem(
        id: 'chicken-breast',
        name: 'Chicken Breast',
        sourceType: 'Branded',
        category: 'Proteins',
        imageUrl: 'https://images.unsplash.com/photo-1518492104633-130d0cc84637?auto=format&fit=crop&w=400&q=80',
        description: 'Lean protein source ideal for calorie control.',
        calories: 165,
        protein: 31,
        carbs: 0,
        fat: 3.6,
        sugar: 0,
        fiber: 0,
        sodium: 74,
      ),
    ];
  }
}
