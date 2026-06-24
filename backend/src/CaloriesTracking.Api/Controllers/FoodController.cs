using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class FoodController : ControllerBase
{
    private readonly ApplicationDbContext _dbContext;

    public FoodController(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    [HttpGet("search")]
    public async Task<IActionResult> SearchFoods([FromQuery] string? query, [FromQuery] int limit = 8)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            var popularFoods = await _dbContext.Foods
                .Take(limit)
                .Select(f => new FoodNutritionDto
                {
                    FdcId = f.FdcId,
                    Name = f.Name,
                    SourceType = f.SourceType ?? "USDA",
                    Calories = f.CaloriesPer100g,
                    Protein = f.Protein,
                    Carbs = f.Carbs,
                    Fat = f.Fat,
                    Sugar = f.Sugar,
                    Fiber = f.Fiber,
                    Sodium = f.Sodium
                })
                .ToListAsync();

            return Ok(popularFoods);
        }

        var normalizedQuery = query.ToLower().Trim();

        var matchesDb = await _dbContext.Foods
            .Where(f => EF.Functions.Like(f.Name, $"%{normalizedQuery}%"))
            .Take(limit * 3)
            .ToListAsync();

        var matches = matchesDb
            .OrderBy(f => f.Name.ToLower().StartsWith(normalizedQuery) ? 0 : 1)
            .ThenBy(f => f.Name)
            .Take(limit)
            .Select(f => new FoodNutritionDto
            {
                FdcId = f.FdcId,
                Name = f.Name,
                SourceType = f.SourceType ?? "USDA",
                Calories = f.CaloriesPer100g,
                Protein = f.Protein,
                Carbs = f.Carbs,
                Fat = f.Fat,
                Sugar = f.Sugar,
                Fiber = f.Fiber,
                Sodium = f.Sodium
            })
            .ToList();

        return Ok(matches);
    }
}

public class FoodNutritionDto
{
    public int? FdcId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string SourceType { get; set; } = string.Empty;
    public decimal Calories { get; set; }
    public decimal Protein { get; set; }
    public decimal Carbs { get; set; }
    public decimal Fat { get; set; }
    public decimal? Sugar { get; set; }
    public decimal? Fiber { get; set; }
    public decimal? Sodium { get; set; }
}
