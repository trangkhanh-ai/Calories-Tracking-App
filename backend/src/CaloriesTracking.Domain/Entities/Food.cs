namespace CaloriesTracking.Domain.Entities;

public class Food
{
    public int Id { get; set; }

    public int? FdcId { get; set; }

    public required string Name { get; set; }

    public string? SourceType { get; set; }

    public decimal CaloriesPer100g { get; set; }

    public decimal Protein { get; set; }

    public decimal Carbs { get; set; }

    public decimal Fat { get; set; }

    public decimal? Sugar { get; set; }

    public decimal? Fiber { get; set; }

    public decimal? Sodium { get; set; }

    public ICollection<MealItem> MealItems { get; set; } = new List<MealItem>();
}
