namespace CaloriesTracking.Application.Dtos.Profile;

public sealed class CalorieGoalResponse
{
    public decimal Bmi { get; init; }

    public decimal Bmr { get; init; }

    public decimal Tdee { get; init; }

    public int RecommendedCalories { get; init; }

    public string ActivityLevel { get; init; } = "sedentary";

    /// <summary>Hệ số vận động đã áp dụng (sedentary = 1.2).</summary>
    public decimal ActivityFactor { get; init; } = 1.2m;
}
