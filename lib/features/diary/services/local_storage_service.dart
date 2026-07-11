import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_entry.dart';

class LocalStorageService {
  static const String _dailyGoalKey = 'daily_goal';
  static const String _entriesKey = 'diary_entries';

  Future<List<FoodEntry>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final entriesJson = prefs.getStringList(_entriesKey) ?? [];
    
    return entriesJson.map((e) {
      final map = jsonDecode(e);
      return FoodEntry(
        id: map['id'],
        name: map['name'],
        calories: map['calories'],
        proteinG: map['proteinG'],
        carbsG: map['carbsG'],
        fatG: map['fatG'],
        date: DateTime.parse(map['date']),
        mealType: map['mealType'],
        imagePath: map['imagePath'],
      );
    }).toList();
  }

  Future<void> addEntry(FoodEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final entriesJson = prefs.getStringList(_entriesKey) ?? [];
    
    final map = {
      'id': entry.id,
      'name': entry.name,
      'calories': entry.calories,
      'proteinG': entry.proteinG,
      'carbsG': entry.carbsG,
      'fatG': entry.fatG,
      'date': entry.date.toIso8601String(),
      'mealType': entry.mealType,
      'imagePath': entry.imagePath,
    };
    
    entriesJson.add(jsonEncode(map));
    await prefs.setStringList(_entriesKey, entriesJson);
  }

  Future<void> removeEntry(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final entriesJson = prefs.getStringList(_entriesKey) ?? [];
    
    entriesJson.removeWhere((e) {
      final map = jsonDecode(e);
      return map['id'] == id;
    });
    
    await prefs.setStringList(_entriesKey, entriesJson);
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
