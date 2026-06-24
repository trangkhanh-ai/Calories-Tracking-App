using CaloriesTracking.Domain.Entities;
using CsvHelper;
using CsvHelper.Configuration;
using Microsoft.EntityFrameworkCore;
using System.Globalization;

namespace CaloriesTracking.Infrastructure.Data.Seeders;

public static class DatabaseSeeder
{
    public static async Task SeedUsdaFoodsAsync(ApplicationDbContext dbContext, string seedDataFolderPath)
    {
        if (await dbContext.Foods.AnyAsync())
        {
            return; // Already seeded
        }

        var csvFilePath = Path.Combine(seedDataFolderPath, "usda_calorie_dataset.csv");
        if (!File.Exists(csvFilePath))
        {
            return;
        }

        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            HasHeaderRecord = true,
            MissingFieldFound = null,
            HeaderValidated = null
        };

        using var reader = new StreamReader(csvFilePath);
        using var csv = new CsvReader(reader, config);
        
        var records = new List<Food>();
        await csv.ReadAsync();
        csv.ReadHeader();

        while (await csv.ReadAsync())
        {
            var food = new Food
            {
                FdcId = csv.GetField<int?>("fdc_id"),
                Name = csv.GetField<string>("name") ?? "Unknown",
                SourceType = csv.GetField<string>("source_type"),
                CaloriesPer100g = csv.GetField<decimal>("kcal_100g"),
                Protein = csv.GetField<decimal>("protein_100g"),
                Carbs = csv.GetField<decimal>("carbs_100g"),
                Fat = csv.GetField<decimal>("fat_100g"),
                Sugar = csv.GetField<decimal?>("sugar_100g"),
                Fiber = csv.GetField<decimal?>("fiber_100g"),
                Sodium = csv.GetField<decimal?>("sodium_mg_100g")
            };
            records.Add(food);
        }

        await dbContext.Foods.AddRangeAsync(records);
        await dbContext.SaveChangesAsync();
    }
}
