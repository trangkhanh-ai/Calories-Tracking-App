import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/network/api_client.dart';
import 'package:flutter_application_1/features/food_search/services/food_search_service.dart';

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('FoodSearchService', () {
    test('returns partial-name suggestions for short queries', () async {
      const csv =
          '''fdc_id,name,source_type,kcal_100g,protein_100g,carbs_100g,fat_100g,sugar_100g,fiber_100g,sodium_mg_100g
1,Banana,Branded,89,1.1,22.8,0.3,12.2,2.6,1
2,Apple,Branded,52,0.3,14.0,0.2,10.4,2.4,1
3,Chicken Breast,Branded,165,31.0,0.0,3.6,0.0,0.0,74
''';

      final service = FoodSearchService(csvContent: csv);
      await service.loadFoods();

      final results = await service.searchFoods('ban');

      expect(results, hasLength(1));
      expect(results.first.name, 'Banana');
    });

    test(
      'supports category and calorie filtering for Vietnamese dishes',
      () async {
        const csv =
            '''fdc_id,name,source_type,category,kcal_100g,protein_100g,carbs_100g,fat_100g,sugar_100g,fiber_100g,sodium_mg_100g
1,Pho Bo,Branded,Vietnamese,320,20,44,8,3,3,820
2,Pho Dac Biet,Branded,Vietnamese,650,35,70,25,4,4,1200
3,Pho Chicken,Branded,Proteins,280,30,35,5,2,2,600
''';

        final service = FoodSearchService(csvContent: csv);
        await service.loadFoods();

        final results = await service.searchFoods(
          'pho',
          category: 'Vietnamese',
          maxCalories: 500,
        );

        expect(results, hasLength(1));
        expect(results.first.name, 'Pho Bo');
        expect(results.first.category, 'Vietnamese');
        expect(results.first.calories, lessThanOrEqualTo(500));
      },
    );

    test('falls back when the API returns an empty catalog', () async {
      final previousAdapter = apiClient.httpClientAdapter;
      apiClient.httpClientAdapter = _JsonAdapter('[]');
      addTearDown(() => apiClient.httpClientAdapter = previousAdapter);
      final service = FoodSearchService();

      final results = await service.searchFoods('');

      expect(results, isNotEmpty);
      expect(results.any((food) => food.name == 'Pho Bo'), isTrue);
    });
  });
}
