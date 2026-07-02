namespace CaloriesTracking.Application.Services;

/// <summary>
/// Công thức y khoa chuẩn (khớp với lib/features/profile/utils/calculator_utils.dart phía Flutter).
/// BMR: Mifflin-St Jeor. TDEE = BMR × hệ số vận động.
/// </summary>
public static class CalorieCalculator
{
    public static readonly IReadOnlyDictionary<string, decimal> ActivityFactors =
        new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase)
        {
            ["sedentary"] = 1.2m,      // Không tập thể dục / ít vận động
            ["light"] = 1.375m,        // Tập nhẹ (1-3 ngày/tuần)
            ["moderate"] = 1.55m,      // Tập vừa (3-5 ngày/tuần)
            ["active"] = 1.725m,       // Tập nhiều (6-7 ngày/tuần)
            ["very_active"] = 1.9m,    // Rất năng động (lao động chân tay/VĐV)
        };

    public static bool IsValidActivityLevel(string level) => ActivityFactors.ContainsKey(level);

    public static decimal CalculateBmi(decimal weightKg, decimal heightCm)
    {
        var heightM = heightCm / 100m;
        return weightKg / (heightM * heightM);
    }

    public static decimal CalculateBmr(string? gender, decimal weightKg, decimal heightCm, int age)
    {
        var bmr = 10m * weightKg + 6.25m * heightCm - 5m * age;
        return bmr + (string.Equals(gender, "male", StringComparison.OrdinalIgnoreCase) ? 5m : -161m);
    }

    /// <summary>Mặc định sedentary (1.2) khi user chưa chọn mức vận động.</summary>
    public static decimal CalculateTdee(decimal bmr, string? activityLevel)
    {
        var factor = activityLevel != null && ActivityFactors.TryGetValue(activityLevel, out var f)
            ? f
            : 1.2m;
        return bmr * factor;
    }

    /// <summary>goal: lose (-500) | maintain (0) | gain (+500)</summary>
    public static int RecommendCalories(decimal tdee, string? goal) => goal?.ToLowerInvariant() switch
    {
        "lose" => (int)Math.Round(tdee - 500),
        "gain" => (int)Math.Round(tdee + 500),
        _ => (int)Math.Round(tdee),
    };
}
