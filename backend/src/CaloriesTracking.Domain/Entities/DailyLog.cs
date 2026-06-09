namespace CaloriesTracking.Domain.Entities;

public class DailyLog
{
    public int Id { get; set; }

    public int UserId { get; set; }

    public DateOnly Date { get; set; }

    public decimal TotalCaloriesConsumed { get; set; }

    public User User { get; set; } = default!;

    public ICollection<MealItem> MealItems { get; set; } = new List<MealItem>();
}
