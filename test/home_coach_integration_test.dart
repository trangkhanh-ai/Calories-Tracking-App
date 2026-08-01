import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/coach/models/meal_suggestion.dart';
import 'package:flutter_application_1/features/coach/providers/coach_provider.dart';
import 'package:flutter_application_1/features/diary/models/diary_dto.dart';
import 'package:flutter_application_1/features/diary/providers/diary_provider.dart';
import 'package:flutter_application_1/features/food_search/models/food_nutrition_item.dart';
import 'package:flutter_application_1/features/home/screens/home_screen.dart';
import 'package:flutter_application_1/features/profile/providers/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _suggestion = MealSuggestion(
  food: _food,
  mealType: 'Lunch',
  quantityGrams: 170,
  calories: 544,
  reason: 'Phu hop voi ngan sach calo con lai',
);

const _food = FoodNutritionItem(
  id: 'pho',
  name: 'Pho Bo',
  sourceType: 'USDA',
  category: 'Vietnamese',
  calories: 320,
  protein: 20,
  carbs: 44,
  fat: 8,
  sugar: 3,
  fiber: 3,
  sodium: 820,
);

void main() {
  testWidgets('home screen renders the coach card with diary data', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyDiaryProvider.overrideWith(
            (ref) async => DiaryState(
              status: DiaryStatus.success,
              data: DailyDiaryDto(
                date: DateTime(2026, 8, 1),
                totalCaloriesConsumed: 600,
                targetCalories: 2000,
                breakfast: const [],
                lunch: const [],
                dinner: const [],
                snacks: const [],
              ),
            ),
          ),
          coachRecommendationProvider.overrideWith(
            (ref) async => const [_suggestion],
          ),
          profileProvider.overrideWith(_FakeProfileNotifier.new),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Hôm nay nên ăn gì?'), findsOneWidget);
    expect(find.text('Pho Bo'), findsOneWidget);
  });
}

class _FakeProfileNotifier extends ProfileNotifier {
  @override
  Future<Map<String, dynamic>?> build() async => const <String, dynamic>{};
}
