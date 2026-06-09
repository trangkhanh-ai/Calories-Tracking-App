import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/diary_api_service.dart';
import '../models/diary_dto.dart';

final diaryApiServiceProvider = Provider<DiaryApiService>((ref) {
  return DiaryApiService();
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final dailyDiaryProvider = FutureProvider<DailyDiaryDto>((ref) async {
  final api = ref.watch(diaryApiServiceProvider);
  final date = ref.watch(selectedDateProvider);
  return api.getDailyDiary(date);
});

class DailyGoalNotifier extends Notifier<int> {
  @override
  int build() {
    return 2000;
  }

  void updateGoal(int goal) {
    state = goal;
  }
}

final dailyGoalProvider = NotifierProvider<DailyGoalNotifier, int>(() => DailyGoalNotifier());
