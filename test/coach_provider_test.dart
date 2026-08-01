import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_1/features/coach/providers/coach_provider.dart';
import 'package:flutter_application_1/features/diary/models/diary_dto.dart';
import 'package:flutter_application_1/features/diary/providers/diary_provider.dart';
import 'package:flutter_application_1/features/food_search/services/food_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _foodCsv =
    '''fdc_id,name,source_type,category,kcal_100g,protein_100g,carbs_100g,fat_100g,sugar_100g,fiber_100g,sodium_mg_100g
1,Chicken Breast,USDA,Proteins,165,31,0,3.6,0,0,74
2,Banana,USDA,Fruit,89,1.1,22.8,0.3,12.2,2.6,1
''';

void main() {
  test('coach provider combines diary state and food catalog', () async {
    final container = ProviderContainer(
      overrides: [
        dailyDiaryProvider.overrideWith(
          (ref) async => DiaryState(
            status: DiaryStatus.success,
            data: _diary(consumed: 600, target: 2000),
          ),
        ),
        coachFoodSearchServiceProvider.overrideWithValue(
          FoodSearchService(csvContent: _foodCsv),
        ),
        coachNowProvider.overrideWithValue(DateTime(2026, 8, 1, 12)),
      ],
    );
    addTearDown(container.dispose);

    final suggestions = await container.read(
      coachRecommendationProvider.future,
    );

    expect(suggestions, isNotEmpty);
    expect(suggestions.first.mealType, 'Lunch');
  });

  test('coach provider returns empty when diary has no display data', () async {
    final container = ProviderContainer(
      overrides: [
        dailyDiaryProvider.overrideWith(
          (ref) async => const DiaryState(status: DiaryStatus.serverError),
        ),
        coachFoodSearchServiceProvider.overrideWithValue(
          FoodSearchService(csvContent: _foodCsv),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(coachRecommendationProvider.future), isEmpty);
  });
}

DailyDiaryDto _diary({required double consumed, required double target}) {
  return DailyDiaryDto(
    date: DateTime(2026, 8, 1),
    totalCaloriesConsumed: consumed,
    targetCalories: target,
    breakfast: const [],
    lunch: const [],
    dinner: const [],
    snacks: const [],
  );
}
