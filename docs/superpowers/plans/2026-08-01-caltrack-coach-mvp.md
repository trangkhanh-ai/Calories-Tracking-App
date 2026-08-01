# CalTrack Coach MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a client-side "Hôm nay nên ăn gì?" card that recommends foods from the existing catalog using the user's daily calorie budget.

**Architecture:** Keep the first release local to Flutter. A pure recommendation service converts `DailyDiaryDto` plus `FoodNutritionItem` candidates into immutable suggestions; a Riverpod provider supplies the service with current diary data and food-search results; a small HomeScreen card renders the result without changing diary writes, camera flows, or backend APIs.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter Test, existing USDA/fallback food catalog.

---

### Task 1: Define the recommendation contract

**Files:**
- Create: `lib/features/coach/models/meal_suggestion.dart`
- Create: `lib/features/coach/services/coach_recommendation_service.dart`
- Test: `test/coach_recommendation_service_test.dart`

- [ ] **Step 1: Write failing tests**

Cover these exact behaviors:

```dart
test('recommends food quantities that stay within remaining calories', () {
  final diary = _diary(consumed: 900, target: 2_000);
  final suggestions = service.recommend(
    diary: diary,
    foods: const [_chicken, _banana, _pho],
    now: DateTime(2026, 8, 1, 12),
  );

  expect(suggestions, isNotEmpty);
  expect(suggestions.every((item) => item.calories <= 1_100), isTrue);
  expect(suggestions.first.mealType, 'Lunch');
});

test('returns no suggestions after the daily target is reached', () {
  expect(
    service.recommend(
      diary: _diary(consumed: 2_000, target: 2_000),
      foods: const [_chicken],
      now: DateTime(2026, 8, 1, 19),
    ),
    isEmpty,
  );
});

test('skips foods without usable calorie values', () {
  final suggestions = service.recommend(
    diary: _diary(consumed: 200, target: 2_000),
    foods: const [_unknown, _banana],
    now: DateTime(2026, 8, 1, 8),
  );

  expect(suggestions.map((item) => item.food.name), isNot(contains('Unknown')));
  expect(suggestions.first.mealType, 'Breakfast');
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
flutter test test/coach_recommendation_service_test.dart
```

Expected: FAIL because `MealSuggestion` and the recommendation service do not exist.

- [ ] **Step 3: Implement the minimal pure service**

Use this contract:

```dart
class CoachRecommendationService {
  List<MealSuggestion> recommend({
    required DailyDiaryDto diary,
    required List<FoodNutritionItem> foods,
    required DateTime now,
  });
}
```

Calculate `remaining = max(0, targetCalories - totalCaloriesConsumed)`. Return an empty list when `remaining == 0`. For other days, set the meal budget to `min(remaining, 550)`, skip foods with missing or non-positive calories, calculate grams that fit that budget, clamp grams to `80..350`, discard any result over the remaining daily budget, then sort by smallest calorie difference and higher protein. Return at most three items. Map time to `Breakfast` for 05:00-10:59, `Lunch` for 11:00-15:59, `Dinner` for 16:00-20:59, and `Snack` otherwise.

- [ ] **Step 4: Run focused tests and format**

Run:

```powershell
dart format lib/features/coach test/coach_recommendation_service_test.dart
flutter test test/coach_recommendation_service_test.dart
```

Expected: all recommendation tests pass.

### Task 2: Connect existing diary and food data through Riverpod

**Files:**
- Create: `lib/features/coach/providers/coach_provider.dart`
- Test: `test/coach_provider_test.dart`

- [ ] **Step 1: Write failing provider tests**

Verify that the provider returns suggestions from a successful diary state, returns an empty list when only the daily target is reached, and does not throw when the diary has no display data.

- [ ] **Step 2: Run provider tests and verify RED**

Run:

```powershell
flutter test test/coach_provider_test.dart
```

Expected: FAIL because the provider does not exist.

- [ ] **Step 3: Implement the provider**

Add an injectable `foodSearchServiceProvider` and `coachNowProvider`. The coach provider should watch `dailyDiaryProvider`, use `displayData`, ask `FoodSearchService` for up to 12 catalog items, and call the pure service. If the diary has no usable data, return an empty list instead of blocking HomeScreen.

- [ ] **Step 4: Run provider tests**

Run `flutter test test/coach_provider_test.dart`; expected: PASS.

### Task 3: Add the HomeScreen recommendation card

**Files:**
- Create: `lib/features/coach/widgets/coach_suggestion_card.dart`
- Modify: `lib/features/home/screens/home_screen.dart`
- Test: `test/coach_suggestion_card_test.dart`

- [ ] **Step 1: Write failing widget tests**

Verify the card renders the title `Hôm nay nên ăn gì?`, displays food name/quantity/calories, shows a loading state, and hides itself for an empty result.

- [ ] **Step 2: Run widget tests and verify RED**

Run `flutter test test/coach_suggestion_card_test.dart`; expected: FAIL because the widget does not exist.

- [ ] **Step 3: Implement the card and HomeScreen integration**

Render the card after the calorie ring and before meal breakdown. Use existing `AppTheme` colors and `GoogleFonts.outfit`. Keep errors non-blocking: a failed coach request should not replace the diary screen. Add a compact `Mở tìm kiếm` action that routes to the existing `food-search` page; do not add a new diary-write path in this MVP.

- [ ] **Step 4: Run widget tests and the existing HomeScreen tests**

Run:

```powershell
flutter test test/coach_suggestion_card_test.dart test/camera_scanner_screen_test.dart
```

Expected: all pass and camera-related behavior remains unchanged.

### Task 4: Document and verify the MVP

**Files:**
- Modify: `README.md`
- Modify: `docs/RELEASE_NOTES_PR15.md`

- [ ] **Step 1: Add the Coach feature to the completed-features table and release notes**

Document the client-side calorie-budget recommendation behavior and explicitly state that it is guidance, not medical advice.

- [ ] **Step 2: Run formatting, focused tests, and the full suite**

Run:

```powershell
dart format lib/features/coach lib/features/home/screens/home_screen.dart test/coach_*_test.dart
flutter test
git diff --check
git status --short
```

Expected: all tests pass, `git diff --check` is clean, and only the planned files are changed.

- [ ] **Step 3: Commit the completed MVP**

```powershell
git add lib/features/coach lib/features/home/screens/home_screen.dart test/coach_*_test.dart README.md docs/RELEASE_NOTES_PR15.md
git commit -m "feat: add calorie budget meal coach"
```
