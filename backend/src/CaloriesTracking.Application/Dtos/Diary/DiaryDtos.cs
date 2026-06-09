namespace CaloriesTracking.Application.Dtos.Diary;

public sealed record LogMealRequest(
    string FoodName,
    decimal CaloriesPer100g,
    decimal Quantity,
    string MealType,
    DateTime Date);

public sealed record MealItemDto(
    int Id,
    int FoodId,
    string FoodName,
    decimal Quantity,
    decimal Calories,
    string MealType);

public sealed record DailyDiaryDto(
    DateTime Date,
    decimal TotalCaloriesConsumed,
    decimal TargetCalories,
    IReadOnlyList<MealItemDto> Breakfast,
    IReadOnlyList<MealItemDto> Lunch,
    IReadOnlyList<MealItemDto> Dinner,
    IReadOnlyList<MealItemDto> Snacks);

public sealed record DailyStatDto(
    DateTime Date,
    decimal CaloriesConsumed);
