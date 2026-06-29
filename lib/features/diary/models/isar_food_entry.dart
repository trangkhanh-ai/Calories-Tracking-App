import 'package:isar/isar.dart';

part 'isar_food_entry.g.dart';

@collection
class IsarFoodEntry {
  Id id = Isar.autoIncrement;

  late String entryId;

  late String foodName;

  late String mealType;

  late double calories;

  late double protein;

  late double carbs;

  late double fat;

  late DateTime date;

  String? imagePath;
}
