using CaloriesTracking.Api.Tests.Support;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Api.Tests;

public sealed class MigrationPreflightTests
{
    [Fact]
    public async Task DuplicateNonNullFdcIds_AreRejectedBeforeUniqueIndexEnforcement()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        await context.Database.ExecuteSqlRawAsync("DROP INDEX \"IX_Foods_FdcId\"");
        var foods = Enumerable.Range(1001, 12)
            .SelectMany(id => new[]
            {
                CreateFood(id, $"Food {id} A"),
                CreateFood(id, $"Food {id} B")
            });
        context.Foods.AddRange(foods);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<DataIntegrityAppException>(
            () => MigrationPreflight.EnsureNoDuplicateFoodFdcIdsAsync(context));

        Assert.Contains("duplicate non-null FdcId", exception.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("12 duplicate", exception.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("1001", exception.Message, StringComparison.Ordinal);
        Assert.Contains("1010", exception.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("1011", exception.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("1012", exception.Message, StringComparison.Ordinal);
        var sample = exception.Message.Split("first 10):", StringSplitOptions.None)[1].Trim().TrimEnd('.');
        Assert.Equal(10, sample.Split(", ", StringSplitOptions.RemoveEmptyEntries).Length);
        Assert.Equal(24, await context.Foods.CountAsync());
    }

    private static Food CreateFood(int fdcId, string name) => new()
    {
        FdcId = fdcId,
        Name = name,
        NormalizedName = name.ToUpperInvariant(),
        CaloriesPer100g = 1,
        Protein = 0,
        Carbs = 0,
        Fat = 0
    };
}
