import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/food_search/services/food_search_service.dart';

void main() {
  group('FoodSearchService', () {
    test('returns partial-name suggestions for short queries', () async {
      const csv = '''fdc_id,name,source_type,kcal_100g,protein_100g,carbs_100g,fat_100g,sugar_100g,fiber_100g,sodium_mg_100g
1,Banana,Branded,89,1.1,22.8,0.3,12.2,2.6,1
2,Apple,Branded,52,0.3,14.0,0.2,10.4,2.4,1
3,Chicken Breast,Branded,165,31.0,0.0,3.6,0.0,0.0,74
''';

      final service = FoodSearchService(csvContent: csv);
      await service.loadFoods();

      final results = service.searchFoods('ban');

      expect(results, hasLength(1));
      expect(results.first.name, 'Banana');
    });
  });
}
