import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/package_path_provider.dart';
import '../models/food_entry.dart';
import '../models/isar_food_entry.dart';

class LocalStorageService {
  static const String _dailyGoalKey = 'daily_goal';
  Isar? _isar;

  Future<Isar> get isar async {
    if (_isar != null && _isar!.isOpen) return _isar!;
    
    // Check if instance is already open elsewhere
    if (Isar.getInstance() != null) {
      _isar = Isar.getInstance()!;
      return _isar!;
    }
    
    // Web support or path provider
    String? dirPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      dirPath = dir.path;
    } catch (e) {
      // In case of Web, getApplicationDocumentsDirectory might throw, so keep dirPath null
    }

    _isar = await Isar.open(
      [IsarFoodEntrySchema],
      directory: dirPath ?? '',
    );
    return _isar!;
  }

  Future<List<FoodEntry>> loadEntries() async {
    final isarInstance = await isar;
    final isarEntries = await isarInstance.isarFoodEntrys.where().findAll();
    
    return isarEntries.map((e) => FoodEntry(
      id: e.entryId,
      name: e.foodName,
      calories: e.calories.round(),
      proteinG: e.protein,
      carbsG: e.carbs,
      fatG: e.fat,
      date: e.date,
      mealType: e.mealType,
      imagePath: e.imagePath,
    )).toList();
  }

  Future<void> addEntry(FoodEntry entry) async {
    final isarInstance = await isar;
    final isarEntry = IsarFoodEntry()
      ..entryId = entry.id
      ..foodName = entry.name
      ..calories = entry.calories.toDouble()
      ..protein = entry.proteinG
      ..carbs = entry.carbsG
      ..fat = entry.fatG
      ..date = entry.date
      ..mealType = entry.mealType
      ..imagePath = entry.imagePath;

    await isarInstance.writeTxn(() async {
      await isarInstance.isarFoodEntrys.put(isarEntry);
    });
  }

  Future<void> removeEntry(String id) async {
    final isarInstance = await isar;
    await isarInstance.writeTxn(() async {
      await isarInstance.isarFoodEntrys.filter().entryIdEqualTo(id).deleteAll();
    });
  }

  Future<int> getDailyGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_dailyGoalKey) ?? 2000;
  }

  Future<void> setDailyGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyGoalKey, goal);
  }
}
