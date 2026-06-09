namespace CaloriesTracking.Domain.Entities;

public class Food
{
    public int Id { get; set; }

    public required string Name { get; set; }

    public decimal CaloriesPer100g { get; set; }

    public decimal Protein { get; set; }

    public decimal Carbs { get; set; }

    public decimal Fat { get; set; }

    public ICollection<MealItem> MealItems { get; set; } = new List<MealItem>();
}
