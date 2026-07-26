using CaloriesTracking.Api.Tests.Support;
using CaloriesTracking.Application.Exceptions;
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
        await context.Database.ExecuteSqlRawAsync(
            "INSERT INTO \"Foods\" (\"FdcId\", \"Name\", \"NormalizedName\", \"CaloriesPer100g\", \"Protein\", \"Carbs\", \"Fat\") " +
            "VALUES (42, 'One', 'ONE', 1, 0, 0, 0), (42, 'Two', 'TWO', 1, 0, 0, 0)");

        var exception = await Assert.ThrowsAsync<DataIntegrityAppException>(
            () => MigrationPreflight.EnsureNoDuplicateFoodFdcIdsAsync(context));

        Assert.Contains("duplicate non-null FdcId", exception.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("42", exception.Message, StringComparison.Ordinal);
        Assert.Equal(2, await context.Foods.CountAsync());
    }
}
