import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../models/food_nutrition_item.dart';

class FoodSearchService {
  FoodSearchService();

  static final instance = FoodSearchService();

  Future<void> loadFoods() async {
    // Không làm gì cả, giữ lại hàm này để code UI cũ không bị lỗi
  }

  Future<List<FoodNutritionItem>> searchFoods(String query, {int limit = 15}) async {
    try {
      final response = await apiClient.get(
        '/food/search',
        queryParameters: {
          'query': query.trim(),
          'limit': limit,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => FoodNutritionItem.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Search API Error: $e');
      return [];
    }
  }
}
