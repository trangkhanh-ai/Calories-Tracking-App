namespace CaloriesTracking.Domain.Entities;

public class MealItem
{
    public int Id { get; set; }

    public int DailyLogId { get; set; }

    public int FoodId { get; set; }

    public decimal Quantity { get; set; }

    public decimal TotalCalories { get; set; }

    public string MealType { get; set; } = string.Empty;

    public DailyLog DailyLog { get; set; } = default!;

    public Food Food { get; set; } = default!;
}
