using CaloriesTracking.Application.Services;

namespace CaloriesTracking.Application.Tests;

/// <summary>
/// Regression tests for pure business formulas in <see cref="CalorieCalculator"/>.
/// Documents current behavior only (including non-male gender treated as female formula).
/// </summary>
public sealed class CalorieCalculatorTests
{
    [Fact]
    public void CalculateBmi_WhenWeight70KgHeight170Cm_ReturnsExpectedValue()
    {
        // BMI = 70 / (1.7^2) = 70 / 2.89
        var bmi = CalorieCalculator.CalculateBmi(weightKg: 70m, heightCm: 170m);

        Assert.Equal(70m / (1.7m * 1.7m), bmi);
    }

    [Fact]
    public void CalculateBmr_WhenMale_UsesMifflinStJeorMaleOffset()
    {
        // 10*70 + 6.25*170 - 5*30 + 5 = 1617.5
        var bmr = CalorieCalculator.CalculateBmr(
            gender: "male",
            weightKg: 70m,
            heightCm: 170m,
            age: 30);

        Assert.Equal(1617.5m, bmr);
    }

    [Fact]
    public void CalculateBmr_WhenGenderIsNull_UsesFemaleOffset()
    {
        // Current behavior: any non-"male" (including null) applies -161.
        // 10*70 + 6.25*170 - 5*30 - 161 = 1451.5
        var bmr = CalorieCalculator.CalculateBmr(
            gender: null,
            weightKg: 70m,
            heightCm: 170m,
            age: 30);

        Assert.Equal(1451.5m, bmr);
    }

    [Theory]
    [InlineData("sedentary", "1.2")]
    [InlineData("LIGHT", "1.375")]
    [InlineData("moderate", "1.55")]
    [InlineData("active", "1.725")]
    [InlineData("very_active", "1.9")]
    public void GetActivityFactor_WhenKnownLevel_ReturnsMappedFactor(string level, string expectedFactor)
    {
        var factor = CalorieCalculator.GetActivityFactor(level);

        Assert.Equal(decimal.Parse(expectedFactor, System.Globalization.CultureInfo.InvariantCulture), factor);
    }

    [Fact]
    public void GetActivityFactor_WhenNull_DefaultsToSedentaryFactor()
    {
        var factor = CalorieCalculator.GetActivityFactor(null);

        Assert.Equal(1.2m, factor);
    }

    [Fact]
    public void CalculateTdee_WhenSedentary_MultipliesBmrByActivityFactor()
    {
        var bmr = 2000m;
        var tdee = CalorieCalculator.CalculateTdee(bmr, "sedentary");

        Assert.Equal(2400m, tdee);
    }

    [Theory]
    [InlineData("lose_slow", 1700)]
    [InlineData("lose_normal", 1500)]
    [InlineData("lose", 1500)]
    [InlineData("gain_slow", 2250)]
    [InlineData("gain_normal", 2500)]
    [InlineData("gain", 2500)]
    [InlineData("maintain", 2000)]
    [InlineData(null, 2000)]
    [InlineData("unknown_goal", 2000)]
    public void RecommendCalories_WhenGoalProvided_ReturnsCurrentExpectedAdjustment(
        string? goal,
        int expectedCalories)
    {
        var recommended = CalorieCalculator.RecommendCalories(tdee: 2000m, goal: goal);

        Assert.Equal(expectedCalories, recommended);
    }

    [Theory]
    [InlineData("sedentary", true)]
    [InlineData("SEDENTARY", true)]
    [InlineData("not_a_level", false)]
    [InlineData("", false)]
    public void IsValidActivityLevel_WhenInputProvided_MatchesDictionaryMembership(
        string level,
        bool expected)
    {
        var isValid = CalorieCalculator.IsValidActivityLevel(level);

        Assert.Equal(expected, isValid);
    }
}
