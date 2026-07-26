using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Data.Seeders;
using CaloriesTracking.Postgres.Tests.Support;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;

namespace CaloriesTracking.Postgres.Tests;

public sealed class PostgresUsdaFoodSeederTests
{
    private static readonly string SeedFolder = Path.Combine(AppContext.BaseDirectory, "Fixtures");
    private static readonly DateTimeOffset TestNow = new(2026, 7, 26, 6, 0, 0, TimeSpan.Zero);

    [PostgresFact]
    public async Task Seed_OnFreshDatabase_ImportsFixtureAndMarksCompleted()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await using var context = database.CreateContext();

        var outcome = await CreateSeeder(context, batchSize: 2).SeedAsync(SeedFolder);

        Assert.Equal(SeedOutcome.Completed, outcome);
        await using var verify = database.CreateContext();
        Assert.Equal(5, await verify.Foods.CountAsync());
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(SeedStatus.Completed, history.Status);
        Assert.Equal(5, history.ProcessedRows);
        Assert.Equal(5, history.TotalRows);
        Assert.Equal(5, history.LastProcessedSourceRow);
        Assert.NotNull(history.CompletedAt);
        Assert.Null(history.LockOwner);
        Assert.Null(history.LockExpiresAt);
    }

    [PostgresFact]
    public async Task Seed_AfterCompletedRun_IsIdempotent()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await using (var first = database.CreateContext())
        {
            Assert.Equal(SeedOutcome.Completed, await CreateSeeder(first).SeedAsync(SeedFolder));
        }

        await using (var second = database.CreateContext())
        {
            Assert.Equal(SeedOutcome.AlreadyCompleted, await CreateSeeder(second).SeedAsync(SeedFolder));
        }

        await using var verify = database.CreateContext();
        Assert.Equal(5, await verify.Foods.CountAsync());
        Assert.Single(await verify.SeedHistories.ToListAsync());
    }

    [PostgresFact]
    public async Task Seed_WhenCancelledAfterCommittedBatch_StopsAfterDurableRows()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await using var context = database.CreateContext();
        using var cancellation = new CancellationTokenSource();
        var seeder = CreateSeeder(context, batchSize: 2);
        seeder.AfterBatchCommitted = processedRows =>
        {
            if (processedRows == 2)
            {
                cancellation.Cancel();
            }
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => seeder.SeedAsync(SeedFolder, cancellation.Token));

        await using var verify = database.CreateContext();
        Assert.Equal(2, await verify.Foods.CountAsync());
        Assert.NotEqual(SeedStatus.Completed, (await verify.SeedHistories.SingleAsync()).Status);
    }

    [PostgresFact]
    public async Task Seed_WhenCancelled_PersistsCheckpointAndReleasesLease()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await using var context = database.CreateContext();
        using var cancellation = new CancellationTokenSource();
        var seeder = CreateSeeder(context, batchSize: 2);
        seeder.AfterBatchCommitted = processedRows =>
        {
            if (processedRows == 4)
            {
                cancellation.Cancel();
            }
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => seeder.SeedAsync(SeedFolder, cancellation.Token));

        await using var verify = database.CreateContext();
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(4, history.ProcessedRows);
        Assert.Equal(4, history.LastProcessedSourceRow);
        Assert.Equal(4, await verify.Foods.CountAsync());
        Assert.Null(history.CompletedAt);
        Assert.Null(history.LockOwner);
        Assert.Null(history.LockExpiresAt);
    }

    [PostgresFact]
    public async Task Seed_AfterCancellation_ResumesFromCheckpointWithoutDuplicates()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        using var cancellation = new CancellationTokenSource();
        await using (var interrupted = database.CreateContext())
        {
            var seeder = CreateSeeder(interrupted, batchSize: 2);
            seeder.AfterBatchCommitted = processedRows =>
            {
                if (processedRows == 2)
                {
                    cancellation.Cancel();
                }
            };

            await Assert.ThrowsAnyAsync<OperationCanceledException>(
                () => seeder.SeedAsync(SeedFolder, cancellation.Token));
        }

        await using (var resumed = database.CreateContext())
        {
            Assert.Equal(SeedOutcome.Completed, await CreateSeeder(resumed, batchSize: 2).SeedAsync(SeedFolder));
        }

        await using var verify = database.CreateContext();
        Assert.Equal(5, await verify.Foods.CountAsync());
        Assert.Equal(5, await verify.Foods.Select(food => food.FdcId).Distinct().CountAsync());
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(SeedStatus.Completed, history.Status);
        Assert.Equal(5, history.ProcessedRows);
        Assert.Equal(5, history.LastProcessedSourceRow);
    }

    [PostgresFact]
    public async Task Seed_WhenOneFdcIdAlreadyExists_SkipsOnlyThatRow()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await SeedExistingFoodAsync(database, 910003, "Original duplicate");

        await using (var context = database.CreateContext())
        {
            Assert.Equal(SeedOutcome.Completed, await CreateSeeder(context, batchSize: 5).SeedAsync(SeedFolder));
        }

        await using var verify = database.CreateContext();
        Assert.Equal(5, await verify.Foods.CountAsync());
        Assert.Equal("Original duplicate", (await verify.Foods.SingleAsync(food => food.FdcId == 910003)).Name);
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(4, history.ProcessedRows);
        Assert.Equal(5, history.LastProcessedSourceRow);
    }

    [PostgresFact]
    public async Task Seed_WhenOneRowConflicts_DoesNotDiscardTheRestOfTheBatch()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await SeedExistingFoodAsync(database, 910001, "Existing first row");

        await using (var context = database.CreateContext())
        {
            await CreateSeeder(context, batchSize: 5).SeedAsync(SeedFolder);
        }

        await using var verify = database.CreateContext();
        var fdcIds = await verify.Foods
            .Where(food => food.FdcId != null)
            .Select(food => food.FdcId!.Value)
            .OrderBy(fdcId => fdcId)
            .ToListAsync();
        Assert.Equal(new[] { 910001, 910002, 910003, 910004, 910005 }, fdcIds);
    }

    [PostgresFact]
    public async Task Seed_WhenDatabaseFailureIsNotUnique_PropagatesAndStoresSanitizedFailure()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await using (var setup = database.CreateContext())
        {
            await setup.Database.ExecuteSqlRawAsync(
                """
                ALTER TABLE "Foods"
                ADD CONSTRAINT "CK_Foods_ForcedSeederFailure"
                CHECK ("CaloriesPer100g" < 0);
                """);
        }

        Exception exception;
        await using (var context = database.CreateContext())
        {
            exception = await Assert.ThrowsAsync<DbUpdateException>(
                () => CreateSeeder(context, batchSize: 2).SeedAsync(SeedFolder));
        }

        var postgres = FindPostgresException(exception);
        Assert.NotNull(postgres);
        Assert.Equal("23514", postgres!.SqlState);
        Assert.False(new UniqueConstraintTranslator().IsUniqueViolation(exception));

        await using var verify = database.CreateContext();
        Assert.Equal(0, await verify.Foods.CountAsync());
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(SeedStatus.Failed, history.Status);
        Assert.Contains(nameof(DbUpdateException), history.ErrorSummary, StringComparison.Ordinal);
        Assert.DoesNotContain("CK_Foods_ForcedSeederFailure", history.ErrorSummary!, StringComparison.Ordinal);
        Assert.DoesNotContain("Host=", history.ErrorSummary!, StringComparison.OrdinalIgnoreCase);
    }

    [PostgresFact]
    public async Task Seed_WhenActiveLeaseExists_BlocksPeer()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await using (var setup = database.CreateContext())
        {
            setup.SeedHistories.Add(History(
                owner: "active-peer",
                expiresAt: TestNow.UtcDateTime.AddMinutes(5)));
            await setup.SaveChangesAsync();
        }

        await using (var peer = database.CreateContext())
        {
            var outcome = await CreateSeeder(peer).SeedAsync(SeedFolder);
            Assert.Equal(SeedOutcome.SkippedAlreadyRunning, outcome);
        }

        await using var verify = database.CreateContext();
        Assert.Equal(0, await verify.Foods.CountAsync());
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal("active-peer", history.LockOwner);
        Assert.Equal(SeedStatus.Running, history.Status);
    }

    [PostgresFact]
    public async Task Seed_WhenTwoPeersRaceForExpiredLease_ExactlyOneWins()
    {
        await using var database = await CreateMigratedDatabaseAsync();
        await using (var setup = database.CreateContext())
        {
            setup.SeedHistories.Add(History(
                owner: "expired-peer",
                expiresAt: TestNow.UtcDateTime.AddMinutes(-5)));
            await setup.SaveChangesAsync();
        }

        await using var firstContext = database.CreateContext();
        await using var secondContext = database.CreateContext();
        using var barrier = new Barrier(2);
        var first = CreateSeeder(firstContext, batchSize: 2);
        var second = CreateSeeder(secondContext, batchSize: 2);
        first.BeforeExpiredLeaseClaim = () => PostgresRaceBarrier.Wait(barrier, "expired-lease race");
        second.BeforeExpiredLeaseClaim = () => PostgresRaceBarrier.Wait(barrier, "expired-lease race");

        var outcomes = await Task.WhenAll(
            Task.Run(() => first.SeedAsync(SeedFolder)),
            Task.Run(() => second.SeedAsync(SeedFolder)));

        Assert.Single(outcomes, outcome => outcome == SeedOutcome.Completed);
        Assert.Single(outcomes, outcome => outcome != SeedOutcome.Completed);

        await using var verify = database.CreateContext();
        Assert.Equal(5, await verify.Foods.CountAsync());
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(SeedStatus.Completed, history.Status);
        Assert.Null(history.LockOwner);
    }

    private static async Task<PostgresTestDatabase> CreateMigratedDatabaseAsync()
    {
        var database = await PostgresTestDatabase.CreateAsync();
        try
        {
            await using var context = database.CreateContext();
            await context.Database.MigrateAsync();
            return database;
        }
        catch
        {
            await database.DisposeAsync();
            throw;
        }
    }

    private static UsdaFoodSeeder CreateSeeder(ApplicationDbContext context, int batchSize = 2) => new(
        context,
        new UniqueConstraintTranslator(),
        NullLogger<UsdaFoodSeeder>.Instance,
        new FixedTimeProvider(TestNow),
        batchSize);

    private static async Task SeedExistingFoodAsync(PostgresTestDatabase database, int fdcId, string name)
    {
        await using var context = database.CreateContext();
        context.Foods.Add(new Food
        {
            FdcId = fdcId,
            Name = name,
            NormalizedName = name.ToUpperInvariant(),
            SourceType = "USDA",
            CaloriesPer100g = 1,
            Protein = 0,
            Carbs = 0,
            Fat = 0
        });
        await context.SaveChangesAsync();
    }

    private static SeedHistory History(string owner, DateTime expiresAt) => new()
    {
        Name = UsdaFoodSeeder.SeedName,
        Version = UsdaFoodSeeder.SeedVersion,
        Status = SeedStatus.Running,
        StartedAt = TestNow.UtcDateTime.AddHours(-1),
        UpdatedAt = TestNow.UtcDateTime.AddHours(-1),
        LockOwner = owner,
        LockExpiresAt = expiresAt
    };

    private static PostgresException? FindPostgresException(Exception exception)
    {
        for (var current = exception; current is not null; current = current.InnerException)
        {
            if (current is PostgresException postgres)
            {
                return postgres;
            }
        }

        return null;
    }

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }
}
