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
        var csvFilePath = Path.Combine(seedDataFolderPath, "usda_calorie_dataset.csv");
        if (!File.Exists(csvFilePath))
        {
            return;
        }

        var existingFdcIds = new HashSet<int>(
            await dbContext.Foods
                .Where(f => f.FdcId != null)
                .Select(f => f.FdcId!.Value)
                .ToListAsync());

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

        int batchSize = 10000;
        int count = 0;

        while (await csv.ReadAsync())
        {
            var fdcId = csv.GetField<int?>("fdc_id");
            if (fdcId.HasValue && existingFdcIds.Contains(fdcId.Value))
            {
                continue;
            }

            var food = new Food
            {
                FdcId = fdcId,
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
            if (fdcId.HasValue)
            {
                existingFdcIds.Add(fdcId.Value);
            }
            count++;

            if (records.Count >= batchSize)
            {
                await dbContext.Foods.AddRangeAsync(records);
                await dbContext.SaveChangesAsync();
                dbContext.ChangeTracker.Clear();
                records.Clear();
                Console.WriteLine($"Seeded {count} foods...");
            }
        }

        if (records.Count > 0)
        {
            await dbContext.Foods.AddRangeAsync(records);
            await dbContext.SaveChangesAsync();
            dbContext.ChangeTracker.Clear();
            Console.WriteLine($"Finished seeding {count} foods.");
        }
    }
}
