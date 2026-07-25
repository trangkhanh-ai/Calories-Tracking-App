import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/diary/models/diary_dto.dart';

void main() {
  group('LogMealRequest & MealType Normalization Tests', () {
    test('normalizeMealType maps Vietnamese meal names correctly', () {
      expect(LogMealRequest.normalizeMealType('Bữa sáng'), equals('Breakfast'));
      expect(LogMealRequest.normalizeMealType('Bữa Trưa'), equals('Lunch'));
      expect(LogMealRequest.normalizeMealType('Bữa tối'), equals('Dinner'));
      expect(LogMealRequest.normalizeMealType('Ăn vặt'), equals('Snack'));
    });

    test('normalizeMealType maps English meal names correctly', () {
      expect(LogMealRequest.normalizeMealType('breakfast'), equals('Breakfast'));
      expect(LogMealRequest.normalizeMealType('LUNCH'), equals('Lunch'));
      expect(LogMealRequest.normalizeMealType('dinner'), equals('Dinner'));
      expect(LogMealRequest.normalizeMealType('snacks'), equals('Snack'));
    });

    test('LogMealRequest.toJson converts mealType using normalizeMealType', () {
      final now = DateTime.now();
      final request = LogMealRequest(
        foodName: 'Phở Bò',
        caloriesPer100g: 150.0,
        quantity: 200.0,
        mealType: 'Bữa sáng',
        date: now,
      );

      final json = request.toJson();
      expect(json['foodName'], equals('Phở Bò'));
      expect(json['caloriesPer100g'], equals(150.0));
      expect(json['quantity'], equals(200.0));
      expect(json['mealType'], equals('Breakfast'));
      expect(json['date'], equals(now.toIso8601String()));
    });
  });
}
