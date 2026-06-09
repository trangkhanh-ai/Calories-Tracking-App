class FoodEntry {
  final String id;
  final String name;
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final DateTime date;
  final String mealType;
  final String? imagePath;

  FoodEntry({
    required this.id,
    required this.name,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.date,
    required this.mealType,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'date': date.toIso8601String(),
        'mealType': mealType,
        'imagePath': imagePath,
      };

  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    return FoodEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      calories: json['calories'] as int,
      proteinG: (json['proteinG'] as num?)?.toDouble() ?? 0,
      carbsG: (json['carbsG'] as num?)?.toDouble() ?? 0,
      fatG: (json['fatG'] as num?)?.toDouble() ?? 0,
      date: DateTime.parse(json['date'] as String),
      mealType: json['mealType'] as String,
      imagePath: json['imagePath'] as String?,
    );
  }
}
