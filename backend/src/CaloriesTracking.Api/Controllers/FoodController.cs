using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class FoodController : ControllerBase
{
    public const int MaxQueryLength = 100;
    public const int MinLimit = 1;
    public const int MaxLimit = 50;
    private const int DefaultLimit = 8;

    private readonly ApplicationDbContext _dbContext;

    public FoodController(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    [HttpGet("search")]
    [EnableRateLimiting("FoodSearch")]
    public async Task<IActionResult> SearchFoods(
        [FromQuery] string? query,
        [FromQuery] int limit = DefaultLimit,
        CancellationToken cancellationToken = default)
    {
        var trimmedQuery = query?.Trim();

        if (trimmedQuery is { Length: > MaxQueryLength })
        {
            throw new ValidationAppException(
                "query",
                $"query must not exceed {MaxQueryLength} characters.");
        }

        // Clamp rather than reject: a bad limit is a client bug, not a reason
        // to fail a read-only search.
        var effectiveLimit = Math.Clamp(limit, MinLimit, MaxLimit);

        var results = await BuildQuery(trimmedQuery)
            // Projection happens in SQL — only the DTO columns cross the wire.
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
            .Take(effectiveLimit)
            .ToListAsync(cancellationToken);

        return Ok(results);
    }

    /// <summary>
    /// Deduplication uses the persisted NormalizedName column so the database
    /// can group without materializing every candidate row in memory. All
    /// filters are EF-parameterized — no string concatenation reaches SQL.
    /// </summary>
    private IQueryable<Food> BuildQuery(string? trimmedQuery)
    {
        var foods = _dbContext.Foods.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(trimmedQuery))
        {
            // Match against the persisted NormalizedName column rather than
            // relying on the provider's LIKE collation. SQLite's LIKE folds case
            // for ASCII only, so "bún" would not match "BÚN" — unacceptable for a
            // Vietnamese-first dataset. Comparing pre-uppercased values gives
            // identical behaviour on SQLite and PostgreSQL.
            var pattern = $"%{EscapeLikePattern(trimmedQuery).ToUpperInvariant()}%";

            foods = foods.Where(f => EF.Functions.Like(f.NormalizedName, pattern, "\\"));
        }

        // One representative row per normalized name, chosen deterministically.
        // Expressed as "id IN (SELECT MIN(id) ... GROUP BY normalized_name)"
        // because EF Core translates the aggregate, whereas selecting a whole
        // entity out of a group would fall back to client evaluation.
        var representativeIds = foods
            .GroupBy(f => f.NormalizedName)
            .Select(g => g.Min(f => f.Id));

        return _dbContext.Foods
            .AsNoTracking()
            .Where(f => representativeIds.Contains(f.Id))
            .OrderBy(f => f.Name);
    }

    /// <summary>
    /// Neutralizes LIKE wildcards in user input so a query of "%" cannot turn
    /// into a full-table scan match.
    /// </summary>
    private static string EscapeLikePattern(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("%", "\\%", StringComparison.Ordinal)
        .Replace("_", "\\_", StringComparison.Ordinal);
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
