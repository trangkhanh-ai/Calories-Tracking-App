using CaloriesTracking.Application.Exceptions;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Infrastructure.Data.Seeders;

public static class DatabaseSeeder
{
    /// <summary>
    /// Fails fast when the data already violates the unique constraints the
    /// migrations are about to create.
    ///
    /// Detection only: conflicting rows are never merged or deleted, because
    /// either action would silently destroy user-visible records. An operator
    /// must resolve the duplicates.
    /// </summary>
    public static async Task EnsureNoDuplicateFoodIdentitiesAsync(
        ApplicationDbContext dbContext,
        CancellationToken cancellationToken = default)
    {
        var duplicateFdcIds = await dbContext.Foods
            .Where(f => f.FdcId != null)
            .GroupBy(f => f.FdcId)
            .Where(g => g.Count() > 1)
            .Select(g => g.Key!.Value)
            .Take(10)
            .ToListAsync(cancellationToken);

        if (duplicateFdcIds.Count > 0)
        {
            // FdcIds are public USDA identifiers, not credentials, so naming
            // them is safe and is what makes the failure actionable.
            throw new DataIntegrityAppException(
                "Duplicate non-null FdcId values exist in the Foods table and must be resolved " +
                "before the unique index can be applied. Affected FdcId values (first 10): " +
                string.Join(", ", duplicateFdcIds) + ".");
        }

        var duplicateCustomNames = await dbContext.Foods
            .Where(f => f.FdcId == null)
            .GroupBy(f => f.NormalizedName)
            .Where(g => g.Count() > 1)
            .Select(g => g.Key)
            .Take(10)
            .ToListAsync(cancellationToken);

        if (duplicateCustomNames.Count > 0)
        {
            throw new DataIntegrityAppException(
                $"{duplicateCustomNames.Count} duplicate custom food name(s) exist and must be " +
                "resolved before the unique index can be applied.");
        }
    }
}
