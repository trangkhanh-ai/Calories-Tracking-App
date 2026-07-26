using CaloriesTracking.Api.Controllers;
using CaloriesTracking.Api.Tests.Support;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Tests;

public sealed class FoodSearchValidationTests
{
    [Fact]
    public async Task Search_WithEmptyQuery_ReturnsPopularFoodsWithoutError()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await SeedFoodsAsync(database, count: 30);

        await using var context = database.CreateContext();

        var results = await SearchAsync(context, query: null, limit: 8);

        Assert.Equal(8, results.Count);
    }

    [Fact]
    public async Task Search_WithWhitespaceQuery_IsTreatedAsEmpty()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await SeedFoodsAsync(database, count: 20);

        await using var context = database.CreateContext();

        var results = await SearchAsync(context, query: "   ", limit: 5);

        Assert.Equal(5, results.Count);
    }

    [Fact]
    public async Task Search_AtMaximumQueryLength_IsAccepted()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await SeedFoodsAsync(database, count: 5);

        await using var context = database.CreateContext();

        var atLimit = new string('a', FoodController.MaxQueryLength);
        var results = await SearchAsync(context, atLimit, limit: 8);

        Assert.Empty(results);
    }

    [Fact]
    public async Task Search_OneCharacterOverMaximum_Throws400()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        var tooLong = new string('a', FoodController.MaxQueryLength + 1);

        var exception = await Assert.ThrowsAsync<ValidationAppException>(
            () => SearchAsync(context, tooLong, limit: 8));

        Assert.Equal("query", exception.Field);
    }

    [Theory]
    [InlineData(-5)]
    [InlineData(0)]
    public async Task Search_WithNonPositiveLimit_ClampsToOne(int limit)
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await SeedFoodsAsync(database, count: 20);

        await using var context = database.CreateContext();

        var results = await SearchAsync(context, query: null, limit: limit);

        Assert.Single(results);
    }

    [Fact]
    public async Task Search_WithLimitAboveMaximum_ClampsTo50()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await SeedFoodsAsync(database, count: 120);

        await using var context = database.CreateContext();

        var results = await SearchAsync(context, query: null, limit: 500);

        Assert.Equal(FoodController.MaxLimit, results.Count);
    }

    [Fact]
    public async Task Search_IsCaseInsensitive()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await SeedNamedFoodsAsync(database, "Phở Bò", "Bún Chả", "Cơm Tấm");

        await using var context = database.CreateContext();

        var lower = await SearchAsync(context, "bún", limit: 8);
        var upper = await SearchAsync(context, "BÚN", limit: 8);

        Assert.Single(lower);
        Assert.Single(upper);
        Assert.Equal(lower[0].Name, upper[0].Name);
    }

    [Fact]
    public async Task Search_DeduplicatesByNormalizedName()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();

        // Same display name twice via distinct FdcIds — legitimate in the USDA
        // dataset, but the search result should show it once.
        await using (var context = database.CreateContext())
        {
            context.Foods.AddRange(
                NewFood(1, "Brown rice"),
                NewFood(2, "Brown rice"),
                NewFood(3, "White rice"));
            await context.SaveChangesAsync();
        }

        await using var searchContext = database.CreateContext();
        var results = await SearchAsync(searchContext, "rice", limit: 10);

        Assert.Equal(2, results.Count);
    }

    [Fact]
    public async Task Search_TreatsWildcardsAsLiteralCharacters()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await SeedNamedFoodsAsync(database, "Apple", "Banana", "Cherry");

        await using var context = database.CreateContext();

        // A bare "%" must not match everything.
        var results = await SearchAsync(context, "%", limit: 10);

        Assert.Empty(results);
    }

    private static async Task<List<FoodNutritionDto>> SearchAsync(
        ApplicationDbContext context,
        string? query,
        int limit)
    {
        var controller = new FoodController(context);
        var result = await controller.SearchFoods(query, limit, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result);
        return Assert.IsType<List<FoodNutritionDto>>(ok.Value);
    }

    private static async Task SeedFoodsAsync(SqliteTestDatabase database, int count)
    {
        await using var context = database.CreateContext();

        for (var i = 1; i <= count; i++)
        {
            context.Foods.Add(NewFood(i, $"Food {i}"));
        }

        await context.SaveChangesAsync();
    }

    private static async Task SeedNamedFoodsAsync(SqliteTestDatabase database, params string[] names)
    {
        await using var context = database.CreateContext();

        for (var i = 0; i < names.Length; i++)
        {
            context.Foods.Add(NewFood(i + 1, names[i]));
        }

        await context.SaveChangesAsync();
    }

    private static Food NewFood(int fdcId, string name) => new()
    {
        FdcId = fdcId,
        Name = name,
        NormalizedName = name.Trim().ToUpperInvariant(),
        SourceType = "USDA",
        CaloriesPer100g = 100,
        Protein = 1,
        Carbs = 2,
        Fat = 3
    };
}
