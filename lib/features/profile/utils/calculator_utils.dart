enum Gender { male, female }
enum ActivityLevel {
  sedentary, // Ít vận động (1.2)
  lightlyActive, // Vận động nhẹ (1.375)
  moderatelyActive, // Vận động vừa (1.55)
  veryActive, // Vận động nhiều (1.725)
  extraActive, // Rất năng động (1.9)
}
enum WeightGoal { lose, maintain, gain }

class CalculatorUtils {
  /// Tính chỉ số khối cơ thể (BMI)
  static double calculateBMI({required double weight, required double heightCm}) {
    final heightM = heightCm / 100;
    return weight / (heightM * heightM);
  }

  /// Tính BMR (Basal Metabolic Rate) dựa trên công thức Mifflin-St Jeor
  static double calculateBMR({
    required Gender gender,
    required double weight,
    required double heightCm,
    required int age,
  }) {
    if (gender == Gender.male) {
      return (10 * weight) + (6.25 * heightCm) - (5 * age) + 5;
    } else {
      return (10 * weight) + (6.25 * heightCm) - (5 * age) - 161;
    }
  }

  /// Tính TDEE (Tổng năng lượng tiêu hao mỗi ngày)
  static double calculateTDEE({
    required double bmr,
    required ActivityLevel activityLevel,
  }) {
    switch (activityLevel) {
      case ActivityLevel.sedentary:
        return bmr * 1.2;
      case ActivityLevel.lightlyActive:
        return bmr * 1.375;
      case ActivityLevel.moderatelyActive:
        return bmr * 1.55;
      case ActivityLevel.veryActive:
        return bmr * 1.725;
      case ActivityLevel.extraActive:
        return bmr * 1.9;
    }
  }

  /// Gợi ý lượng Calo mục tiêu dựa trên mục tiêu cân nặng
  static int calculateRecommendedCalories({
    required double tdee,
    required WeightGoal goal,
  }) {
    switch (goal) {
      case WeightGoal.lose:
        return (tdee - 500).round(); // Thâm hụt 500 calo
      case WeightGoal.maintain:
        return tdee.round(); // Giữ nguyên
      case WeightGoal.gain:
        return (tdee + 500).round(); // Dư thừa 500 calo
    }
  }
}
