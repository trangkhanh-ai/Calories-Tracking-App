import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diary/providers/diary_provider.dart';
import '../../food_search/services/food_search_service.dart';
import '../models/meal_suggestion.dart';
import '../services/coach_recommendation_service.dart';

final coachRecommendationServiceProvider = Provider<CoachRecommendationService>(
  (ref) {
    return CoachRecommendationService();
  },
);

final coachFoodSearchServiceProvider = Provider<FoodSearchService>((ref) {
  return FoodSearchService.instance;
});

final coachNowProvider = Provider<DateTime>((ref) => DateTime.now());

final coachRecommendationProvider = FutureProvider<List<MealSuggestion>>((
  ref,
) async {
  final diaryState = await ref.watch(dailyDiaryProvider.future);
  final diary = diaryState.displayData;
  if (diary == null) return const [];

  final foods = await ref
      .watch(coachFoodSearchServiceProvider)
      .searchFoods('', limit: 12);

  return ref
      .watch(coachRecommendationServiceProvider)
      .recommend(diary: diary, foods: foods, now: ref.watch(coachNowProvider));
});
