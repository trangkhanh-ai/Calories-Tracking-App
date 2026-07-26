using CaloriesTracking.Application.Exceptions;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Infrastructure.Data;

/// <summary>
/// Pre-migration data checks.
///
/// The unique indexes added by AddNormalizedIdentityAndSeedHistory are the hard
/// guarantee, but they fail with an opaque provider error. These checks run
/// first so an operator gets an actionable message naming what conflicts.
///
/// Detection only: nothing is merged, renamed, or deleted.
/// </summary>
public static class MigrationPreflight
{
    public static async Task EnsureNoCaseInsensitiveUserConflictsAsync(
        ApplicationDbContext dbContext,
        CancellationToken cancellationToken = default)
    {
        // On a fresh database the table does not exist yet and there is nothing
        // to conflict with.
        var applied = await dbContext.Database.GetAppliedMigrationsAsync(cancellationToken);
        if (!applied.Any())
        {
            return;
        }

        var duplicateUsernames = await dbContext.Users
            .GroupBy(u => u.Username.Trim().ToUpper())
            .Where(g => g.Count() > 1)
            .Select(g => g.Key)
            .Take(10)
            .ToListAsync(cancellationToken);

        if (duplicateUsernames.Count > 0)
        {
            throw new DataIntegrityAppException(
                $"{duplicateUsernames.Count} case-insensitive duplicate username(s) exist in the Users " +
                "table and must be resolved manually before the unique index can be applied. " +
                "No accounts were modified.");
        }

        var duplicateEmails = await dbContext.Users
            .GroupBy(u => u.Email.Trim().ToUpper())
            .Where(g => g.Count() > 1)
            .Select(g => g.Key)
            .Take(10)
            .ToListAsync(cancellationToken);

        if (duplicateEmails.Count > 0)
        {
            // Emails are personal data — report the count, never the values.
            throw new DataIntegrityAppException(
                $"{duplicateEmails.Count} case-insensitive duplicate email address(es) exist in the " +
                "Users table and must be resolved manually before the unique index can be applied. " +
                "No accounts were modified.");
        }
    }
}
