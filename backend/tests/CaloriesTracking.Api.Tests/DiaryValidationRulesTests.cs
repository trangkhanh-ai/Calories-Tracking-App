using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Application.Validation;

namespace CaloriesTracking.Api.Tests;

public sealed class DiaryValidationRulesTests
{
    private static readonly DateTime UtcNow = new(2026, 7, 26, 12, 0, 0, DateTimeKind.Utc);

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void FoodName_WhenMissing_Throws(string? foodName)
    {
        var exception = Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateFoodName(foodName));

        Assert.Equal("foodName", exception.Field);
    }

    [Fact]
    public void FoodName_AtMaximumBoundary_IsAccepted()
    {
        var maxLength = new string('f', DiaryValidationRules.FoodNameMaxLength);
        Assert.Equal(maxLength, DiaryValidationRules.ValidateFoodName(maxLength));
    }

    [Fact]
    public void FoodName_OneAboveMaximum_Throws()
    {
        var tooLong = new string('f', DiaryValidationRules.FoodNameMaxLength + 1);
        Assert.Throws<ValidationAppException>(() => DiaryValidationRules.ValidateFoodName(tooLong));
    }

    [Fact]
    public void FoodName_IsTrimmed()
    {
        Assert.Equal("Phở bò", DiaryValidationRules.ValidateFoodName("  Phở bò  "));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-0.01)]
    public void Calories_WhenNotPositive_Throws(decimal calories)
    {
        Assert.Throws<ValidationAppException>(() => DiaryValidationRules.ValidateCaloriesPer100g(calories));
    }

    [Fact]
    public void Calories_AtMaximumBoundary_IsAccepted()
    {
        DiaryValidationRules.ValidateCaloriesPer100g(DiaryValidationRules.MaxCaloriesPer100g);
    }

    [Fact]
    public void Calories_OneAboveMaximum_Throws()
    {
        Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateCaloriesPer100g(DiaryValidationRules.MaxCaloriesPer100g + 1));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-0.5)]
    public void Quantity_WhenNotPositive_Throws(decimal quantity)
    {
        Assert.Throws<ValidationAppException>(() => DiaryValidationRules.ValidateQuantity(quantity));
    }

    [Fact]
    public void Quantity_AtMaximumBoundary_IsAccepted()
    {
        DiaryValidationRules.ValidateQuantity(DiaryValidationRules.MaxQuantity);
    }

    [Fact]
    public void Quantity_OneAboveMaximum_Throws()
    {
        Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateQuantity(DiaryValidationRules.MaxQuantity + 1));
    }

    [Theory]
    [InlineData("Breakfast")]
    [InlineData("Lunch")]
    [InlineData("Dinner")]
    [InlineData("Snack")]
    public void MealType_WhenCanonical_IsAccepted(string mealType)
    {
        Assert.Equal(mealType, DiaryValidationRules.ValidateMealType(mealType));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("breakfast")]
    [InlineData("BREAKFAST")]
    [InlineData("Brunch")]
    [InlineData(" Breakfast")]
    public void MealType_WhenNotCanonical_Throws(string? mealType)
    {
        Assert.Throws<ValidationAppException>(() => DiaryValidationRules.ValidateMealType(mealType));
    }

    [Fact]
    public void Date_WhenDefault_Throws()
    {
        var exception = Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateDate(default, UtcNow));

        Assert.Equal("date", exception.Field);
    }

    [Fact]
    public void Date_WhenWithinFutureTolerance_IsAccepted()
    {
        // Exactly one day ahead sits on the documented tolerance boundary.
        DiaryValidationRules.ValidateDate(UtcNow.AddDays(1), UtcNow);
    }

    [Fact]
    public void Date_WhenTooFarInTheFuture_Throws()
    {
        Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateDate(UtcNow.AddDays(3), UtcNow));
    }

    [Fact]
    public void Date_InThePast_IsAccepted()
    {
        DiaryValidationRules.ValidateDate(UtcNow.AddYears(-2), UtcNow);
    }

    [Fact]
    public void ValidateLogMeal_ReturnsNormalizedCopy()
    {
        var request = new LogMealRequest(
            FoodName: "  Phở bò  ",
            CaloriesPer100g: 150m,
            Quantity: 200m,
            MealType: "Breakfast",
            Date: UtcNow);

        var validated = DiaryValidationRules.ValidateLogMeal(request, UtcNow);

        Assert.Equal("Phở bò", validated.FoodName);
        Assert.Equal("Breakfast", validated.MealType);
    }

    [Fact]
    public void StatsRange_WhenReversed_Throws()
    {
        var exception = Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateStatsRange(
                new DateTime(2026, 7, 20),
                new DateTime(2026, 7, 10)));

        Assert.Equal("startDate must be on or before endDate.", exception.Message);
    }

    [Fact]
    public void StatsRange_WhenExactly90Days_IsAccepted()
    {
        var start = new DateTime(2026, 1, 1);

        // Inclusive: 1 Jan plus 89 days is the 90th day.
        DiaryValidationRules.ValidateStatsRange(start, start.AddDays(89));
    }

    [Fact]
    public void StatsRange_WhenOver90Days_Throws()
    {
        var start = new DateTime(2026, 1, 1);

        var exception = Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateStatsRange(start, start.AddDays(90)));

        Assert.Contains("90 days", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void StatsRange_WhenSameDay_IsAcceptedAsOneDay()
    {
        var day = new DateTime(2026, 3, 15);
        DiaryValidationRules.ValidateStatsRange(day, day);
    }

    [Fact]
    public void StatsRange_WhenStartIsDefault_Throws()
    {
        var exception = Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateStatsRange(default, new DateTime(2026, 7, 10)));

        Assert.Equal("startDate", exception.Field);
    }

    [Fact]
    public void StatsRange_WhenEndIsDefault_Throws()
    {
        var exception = Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateStatsRange(new DateTime(2026, 7, 10), default));

        Assert.Equal("endDate", exception.Field);
    }

    [Fact]
    public void StatsRange_WhenBothAreDefault_Throws()
    {
        // Guards the pathological case: MinValue..MinValue previously produced a
        // multi-hundred-thousand iteration day loop.
        Assert.Throws<ValidationAppException>(
            () => DiaryValidationRules.ValidateStatsRange(default, default));
    }
}
