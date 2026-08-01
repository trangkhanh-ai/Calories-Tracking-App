import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/coach/models/meal_suggestion.dart';
import 'package:flutter_application_1/features/coach/widgets/coach_suggestion_card.dart';
import 'package:flutter_application_1/features/food_search/models/food_nutrition_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _suggestion = MealSuggestion(
  food: FoodNutritionItem(
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
  ),
  mealType: 'Lunch',
  quantityGrams: 170,
  calories: 544,
  reason: 'Phu hop voi ngan sach calo con lai',
);

void main() {
  testWidgets('renders suggestion details and search action', (tester) async {
    var searchOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoachSuggestionCard(
            state: const AsyncValue.data([_suggestion]),
            onOpenSearch: () => searchOpened = true,
          ),
        ),
      ),
    );

    expect(find.text('Hôm nay nên ăn gì?'), findsOneWidget);
    expect(find.text('Pho Bo'), findsOneWidget);
    expect(find.text('170 g'), findsOneWidget);
    expect(find.text('544 kcal'), findsOneWidget);

    await tester.tap(find.text('Mở tìm kiếm'));
    expect(searchOpened, isTrue);
  });

  testWidgets('shows a compact loading state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CoachSuggestionCard(
            state: AsyncValue.loading(),
            onOpenSearch: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Đang tính gợi ý...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('hides the card when there are no suggestions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CoachSuggestionCard(
            state: AsyncValue.data([]),
            onOpenSearch: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Hôm nay nên ăn gì?'), findsNothing);
  });
}

void _noop() {}
