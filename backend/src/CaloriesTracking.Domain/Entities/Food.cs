namespace CaloriesTracking.Domain.Entities;

public class Food
{
    public int Id { get; set; }

    public int? FdcId { get; set; }

    public required string Name { get; set; }

    /// <summary>
    /// Uppercase-invariant copy of <see cref="Name"/>, unique only across
    /// custom foods (rows where <see cref="FdcId"/> is null). USDA rows are
    /// excluded because the dataset legitimately repeats display names.
    /// </summary>
    public string NormalizedName { get; set; } = string.Empty;

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
