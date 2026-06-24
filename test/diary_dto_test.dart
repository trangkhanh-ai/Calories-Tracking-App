import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/diary/models/diary_dto.dart';

void main() {
  group('DailyDiaryDto', () {
    test('empty factory creates an empty diary with zero calories', () {
      final date = DateTime(2026, 6, 24);

      final diary = DailyDiaryDto.empty(date: date);

      expect(diary.date, date);
      expect(diary.totalCaloriesConsumed, 0);
      expect(diary.targetCalories, 2000);
      expect(diary.breakfast, isEmpty);
      expect(diary.lunch, isEmpty);
      expect(diary.dinner, isEmpty);
      expect(diary.snacks, isEmpty);
    });
  });
}
