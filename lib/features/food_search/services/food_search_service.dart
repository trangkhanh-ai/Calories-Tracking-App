import 'package:flutter/services.dart';

import '../models/food_nutrition_item.dart';

class FoodSearchService {
  FoodSearchService({this.csvContent});

  static final instance = FoodSearchService();

  final String? csvContent;
  final List<FoodNutritionItem> _cache = <FoodNutritionItem>[];
  bool _loaded = false;

  Future<List<FoodNutritionItem>> loadFoods() async {
    if (_loaded) return _cache;

    final content = csvContent ?? await rootBundle.loadString('data/usda/usda_calorie_dataset.csv');
    final rows = _parseCsv(content);
    if (rows.isEmpty) return const <FoodNutritionItem>[];

    final headers = rows.first.map((value) => value.trim()).toList();
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      final values = <String, String>{};
      for (var j = 0; j < headers.length && j < row.length; j++) {
        values[headers[j]] = row[j];
      }

      final food = FoodNutritionItem.fromCsvRow(values);
      if (food.name.isNotEmpty && food.calories != null) {
        _cache.add(food);
      }
    }

    _loaded = true;
    return _cache;
  }

  List<FoodNutritionItem> searchFoods(String query, {int limit = 8}) {
    if (!_loaded) {
      return const <FoodNutritionItem>[];
    }

    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return _cache.take(limit).toList();
    }

    final matches = _cache.where((food) {
      final normalizedName = _normalize(food.name);
      if (normalizedName.contains(normalizedQuery)) return true;

      final tokens = normalizedName.split(RegExp(r'[\s\-_/]+'));
      return tokens.any((token) => token.startsWith(normalizedQuery));
    }).toList();

    matches.sort((a, b) {
      final aName = _normalize(a.name);
      final bName = _normalize(b.name);

      final aStartsWith = aName.startsWith(normalizedQuery);
      final bStartsWith = bName.startsWith(normalizedQuery);
      if (aStartsWith != bStartsWith) return aStartsWith ? -1 : 1;

      final aContains = aName.contains(normalizedQuery);
      final bContains = bName.contains(normalizedQuery);
      if (aContains != bContains) return aContains ? -1 : 1;

      return aName.compareTo(bName);
    });

    return matches.take(limit).toList();
  }

  String _normalize(String input) {
    final value = input.toLowerCase().trim();
    return value
        .replaceAll('đ', 'd')
        .replaceAll('ð', 'd')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ả', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('ạ', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ấ', 'a')
        .replaceAll('ầ', 'a')
        .replaceAll('ẩ', 'a')
        .replaceAll('ẫ', 'a')
        .replaceAll('ậ', 'a')
        .replaceAll('ă', 'a')
        .replaceAll('ắ', 'a')
        .replaceAll('ằ', 'a')
        .replaceAll('ẳ', 'a')
        .replaceAll('ẵ', 'a')
        .replaceAll('ặ', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ẻ', 'e')
        .replaceAll('ẽ', 'e')
        .replaceAll('ẹ', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ế', 'e')
        .replaceAll('ề', 'e')
        .replaceAll('ể', 'e')
        .replaceAll('ễ', 'e')
        .replaceAll('ệ', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ỉ', 'i')
        .replaceAll('ĩ', 'i')
        .replaceAll('ị', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ỏ', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ọ', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ố', 'o')
        .replaceAll('ồ', 'o')
        .replaceAll('ổ', 'o')
        .replaceAll('ỗ', 'o')
        .replaceAll('ộ', 'o')
        .replaceAll('ơ', 'o')
        .replaceAll('ớ', 'o')
        .replaceAll('ờ', 'o')
        .replaceAll('ở', 'o')
        .replaceAll('ỡ', 'o')
        .replaceAll('ợ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ủ', 'u')
        .replaceAll('ũ', 'u')
        .replaceAll('ụ', 'u')
        .replaceAll('ư', 'u')
        .replaceAll('ứ', 'u')
        .replaceAll('ừ', 'u')
        .replaceAll('ử', 'u')
        .replaceAll('ữ', 'u')
        .replaceAll('ự', 'u')
        .replaceAll('ý', 'y')
        .replaceAll('ỳ', 'y')
        .replaceAll('ỷ', 'y')
        .replaceAll('ỹ', 'y')
        .replaceAll('ỵ', 'y');
  }

  List<List<String>> _parseCsv(String content) {
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '"') {
        final next = i + 1 < content.length ? content[i + 1] : null;
        if (inQuotes && next == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (char == ',' && !inQuotes) {
        currentRow.add(buffer.toString());
        buffer.clear();
        continue;
      }

      if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++;
        }
        currentRow.add(buffer.toString());
        buffer.clear();
        if (currentRow.any((value) => value.trim().isNotEmpty)) {
          rows.add(currentRow.toList());
        }
        currentRow.clear();
        continue;
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(buffer.toString());
      if (currentRow.any((value) => value.trim().isNotEmpty)) {
        rows.add(currentRow.toList());
      }
    }

    return rows;
  }
}
