using CaloriesTracking.Api.Tests.Support;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Data.Seeders;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace CaloriesTracking.Api.Tests;

/// <summary>
/// Covers the resumable seeder that replaced the previous "skip the whole batch
/// on any DbUpdateException" behaviour.
/// </summary>
public sealed class UsdaFoodSeederTests : IDisposable
{
    private readonly string _seedFolder;
    private readonly List<string> _databaseFiles = [];

    public UsdaFoodSeederTests()
    {
        _seedFolder = Path.Combine(Path.GetTempPath(), $"usda-seed-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_seedFolder);
    }

    public void Dispose()
    {
        if (Directory.Exists(_seedFolder))
        {
            Directory.Delete(_seedFolder, recursive: true);
        }

        foreach (var databaseFile in _databaseFiles)
        {
            SqliteConnection.ClearAllPools();
            if (File.Exists(databaseFile))
            {
                File.Delete(databaseFile);
            }
        }
    }

    [Fact]
    public async Task Seed_OnAFreshDatabase_ImportsEveryRowAndMarksCompleted()
    {
        WriteCsv(rowCount: 25);

        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        var outcome = await CreateSeeder(context).SeedAsync(_seedFolder);

        Assert.Equal(SeedOutcome.Completed, outcome);

        await using var verify = database.CreateContext();
        Assert.Equal(25, await verify.Foods.CountAsync());

        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(SeedStatus.Completed, history.Status);
        Assert.Equal(25, history.ProcessedRows);
        Assert.Equal(25, history.LastProcessedSourceRow);
        Assert.NotNull(history.CompletedAt);
    }

    [Fact]
    public async Task Seed_WhenInterrupted_CheckpointsProgressAndDoesNotMarkCompleted()
    {
        WriteCsv(rowCount: 50);

        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        // Cancel once the first batch has been committed.
        using var cancellation = new CancellationTokenSource();
        var seeder = CreateSeeder(context, batchSize: 10, onBatchCommitted: rows =>
        {
            if (rows >= 10)
            {
                cancellation.Cancel();
            }
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => seeder.SeedAsync(_seedFolder, cancellation.Token));

        await using var verify = database.CreateContext();

        var history = await verify.SeedHistories.SingleAsync();

        // Never Completed — an interrupted import must not look finished.
        Assert.NotEqual(SeedStatus.Completed, history.Status);
        Assert.Null(history.CompletedAt);

        // The checkpoint is durable and the committed rows survived.
        Assert.True(history.LastProcessedSourceRow > 0);
        Assert.Equal(history.LastProcessedSourceRow, await verify.Foods.CountAsync());

        // The lease was released so the next instance can resume.
        Assert.Null(history.LockOwner);
    }

    [Fact]
    public async Task Seed_AfterInterruption_ResumesFromTheCheckpointWithoutDuplicating()
    {
        WriteCsv(rowCount: 50);

        await using var database = await SqliteTestDatabase.CreateAsync();

        using var cancellation = new CancellationTokenSource();

        await using (var context = database.CreateContext())
        {
            var seeder = CreateSeeder(context, batchSize: 10, onBatchCommitted: rows =>
            {
                if (rows >= 10)
                {
                    cancellation.Cancel();
                }
            });

            await Assert.ThrowsAnyAsync<OperationCanceledException>(
                () => seeder.SeedAsync(_seedFolder, cancellation.Token));
        }

        int afterInterruption;
        await using (var verify = database.CreateContext())
        {
            afterInterruption = await verify.Foods.CountAsync();
        }

        Assert.InRange(afterInterruption, 1, 49);

        // Resume with a fresh context, exactly like a restarted instance.
        await using (var context = database.CreateContext())
        {
            var outcome = await CreateSeeder(context, batchSize: 10).SeedAsync(_seedFolder);
            Assert.Equal(SeedOutcome.Completed, outcome);
        }

        await using var final = database.CreateContext();

        // All 50 rows exist exactly once — no gap and no duplication.
        Assert.Equal(50, await final.Foods.CountAsync());
        Assert.Equal(50, await final.Foods.Select(f => f.FdcId).Distinct().CountAsync());

        var history = await final.SeedHistories.SingleAsync();
        Assert.Equal(SeedStatus.Completed, history.Status);
    }

    [Fact]
    public async Task Seed_WhenAlreadyCompleted_IsANoOp()
    {
        WriteCsv(rowCount: 15);

        await using var database = await SqliteTestDatabase.CreateAsync();

        await using (var context = database.CreateContext())
        {
            Assert.Equal(SeedOutcome.Completed, await CreateSeeder(context).SeedAsync(_seedFolder));
        }

        await using (var context = database.CreateContext())
        {
            Assert.Equal(SeedOutcome.AlreadyCompleted, await CreateSeeder(context).SeedAsync(_seedFolder));
        }

        await using var verify = database.CreateContext();

        // Idempotent: re-running does not re-import.
        Assert.Equal(15, await verify.Foods.CountAsync());
    }

    [Fact]
    public async Task Seed_WhenAnotherInstanceHoldsTheLease_Skips()
    {
        WriteCsv(rowCount: 10);

        await using var database = await SqliteTestDatabase.CreateAsync();

        // Simulate a peer that claimed the seed and is still working.
        await using (var context = database.CreateContext())
        {
            context.SeedHistories.Add(new SeedHistory
            {
                Name = UsdaFoodSeeder.SeedName,
                Version = UsdaFoodSeeder.SeedVersion,
                Status = SeedStatus.Running,
                StartedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
                LockOwner = "peer-instance",
                LockExpiresAt = DateTime.UtcNow.AddMinutes(5)
            });
            await context.SaveChangesAsync();
        }

        await using (var context = database.CreateContext())
        {
            var outcome = await CreateSeeder(context).SeedAsync(_seedFolder);
            Assert.Equal(SeedOutcome.SkippedAlreadyRunning, outcome);
        }

        await using var verify = database.CreateContext();

        // No concurrent import happened.
        Assert.Equal(0, await verify.Foods.CountAsync());
    }

    [Fact]
    public async Task Seed_WhenAPeerLeaseHasExpired_TakesOverAndCompletes()
    {
        WriteCsv(rowCount: 10);

        await using var database = await SqliteTestDatabase.CreateAsync();

        await using (var context = database.CreateContext())
        {
            context.SeedHistories.Add(new SeedHistory
            {
                Name = UsdaFoodSeeder.SeedName,
                Version = UsdaFoodSeeder.SeedVersion,
                Status = SeedStatus.Running,
                StartedAt = DateTime.UtcNow.AddHours(-2),
                UpdatedAt = DateTime.UtcNow.AddHours(-2),
                LockOwner = "crashed-instance",
                LockExpiresAt = DateTime.UtcNow.AddHours(-1)
            });
            await context.SaveChangesAsync();
        }

        await using (var context = database.CreateContext())
        {
            Assert.Equal(SeedOutcome.Completed, await CreateSeeder(context).SeedAsync(_seedFolder));
        }

        await using var verify = database.CreateContext();
        Assert.Equal(10, await verify.Foods.CountAsync());
    }

    [Fact]
    public async Task Seed_WhenTwoInstancesRaceForAnExpiredLease_OnlyOneTakesOwnership()
    {
        WriteCsv(rowCount: 10);
        var databaseFile = Path.Combine(Path.GetTempPath(), $"usda-lease-{Guid.NewGuid():N}.db");
        _databaseFiles.Add(databaseFile);
        var connectionString = $"Data Source={databaseFile};Default Timeout=10";

        await using (var setup = CreateFileContext(connectionString))
        {
            await setup.Database.MigrateAsync();
            setup.SeedHistories.Add(new SeedHistory
            {
                Name = UsdaFoodSeeder.SeedName,
                Version = UsdaFoodSeeder.SeedVersion,
                Status = SeedStatus.Running,
                StartedAt = DateTime.UtcNow.AddHours(-2),
                UpdatedAt = DateTime.UtcNow.AddHours(-2),
                LockOwner = "expired-owner",
                LockExpiresAt = DateTime.UtcNow.AddHours(-1)
            });
            await setup.SaveChangesAsync();
        }

        await using var firstContext = CreateFileContext(connectionString);
        await using var secondContext = CreateFileContext(connectionString);
        using var claimBarrier = new Barrier(participantCount: 2);
        var firstSeeder = CreateSeeder(firstContext);
        var secondSeeder = CreateSeeder(secondContext);
        firstSeeder.BeforeExpiredLeaseClaim = () => claimBarrier.SignalAndWait(TimeSpan.FromSeconds(10));
        secondSeeder.BeforeExpiredLeaseClaim = () => claimBarrier.SignalAndWait(TimeSpan.FromSeconds(10));

        var outcomes = await Task.WhenAll(
            Task.Run(() => firstSeeder.SeedAsync(_seedFolder)),
            Task.Run(() => secondSeeder.SeedAsync(_seedFolder)));

        Assert.Single(outcomes, outcome => outcome == SeedOutcome.Completed);
        Assert.Single(outcomes, outcome => outcome != SeedOutcome.Completed);

        await using var verify = CreateFileContext(connectionString);
        Assert.Equal(10, await verify.Foods.CountAsync());
        Assert.Equal(SeedStatus.Completed, (await verify.SeedHistories.SingleAsync()).Status);
    }

    [Fact]
    public async Task Seed_WhenLeaseOwnerChangesBeforeCheckpoint_StaleOwnerCannotMutateHistory()
    {
        WriteCsv(rowCount: 10);
        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();
        var seeder = CreateSeeder(context, batchSize: 5);
        var leaseStolen = false;
        seeder.BeforeLeaseMutation = releaseLock =>
        {
            if (releaseLock || leaseStolen)
            {
                return;
            }

            leaseStolen = true;
            using var takeover = database.CreateContext();
            takeover.Database.ExecuteSqlRaw(
                "UPDATE \"SeedHistories\" SET \"LockOwner\" = 'new-owner', \"LockExpiresAt\" = {0}",
                DateTime.UtcNow.AddMinutes(10));
        };

        var exception = await Assert.ThrowsAsync<DataIntegrityAppException>(
            () => seeder.SeedAsync(_seedFolder));

        Assert.Contains("lease", exception.Message, StringComparison.OrdinalIgnoreCase);
        await using var verify = database.CreateContext();
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal("new-owner", history.LockOwner);
        Assert.Equal(0, history.LastProcessedSourceRow);
        Assert.Equal(SeedStatus.Running, history.Status);
    }

    [Fact]
    public async Task Seed_WhenLeaseOwnerChangesBeforeCancellationRelease_StaleOwnerCannotReleaseNewLease()
    {
        WriteCsv(rowCount: 10);
        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();
        using var cancellation = new CancellationTokenSource();
        var seeder = CreateSeeder(
            context,
            batchSize: 5,
            onBatchCommitted: _ => cancellation.Cancel());
        seeder.BeforeLeaseMutation = releaseLock =>
        {
            if (!releaseLock)
            {
                return;
            }

            using var takeover = database.CreateContext();
            takeover.Database.ExecuteSqlRaw(
                "UPDATE \"SeedHistories\" SET \"LockOwner\" = 'new-owner', \"LockExpiresAt\" = {0}",
                DateTime.UtcNow.AddMinutes(10));
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => seeder.SeedAsync(_seedFolder, cancellation.Token));

        await using var verify = database.CreateContext();
        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal("new-owner", history.LockOwner);
        Assert.True(history.LastProcessedSourceRow > 0);
        Assert.Equal(SeedStatus.Running, history.Status);
    }

    [Fact]
    public async Task Seed_WhenOneRowDuplicatesAnExistingFdcId_ImportsEveryOtherRowInTheBatch()
    {
        WriteCsv(rowCount: 20);

        await using var database = await SqliteTestDatabase.CreateAsync();

        // Pre-insert a single row that the CSV will collide with.
        await using (var context = database.CreateContext())
        {
            context.Foods.Add(new Food
            {
                FdcId = 5,
                Name = "Pre-existing food 5",
                NormalizedName = "PRE-EXISTING FOOD 5",
                CaloriesPer100g = 1,
                Protein = 0,
                Carbs = 0,
                Fat = 0
            });
            await context.SaveChangesAsync();
        }

        await using (var context = database.CreateContext())
        {
            // One batch covers all 20 rows, so the old implementation would have
            // discarded all of them because of the single conflict.
            Assert.Equal(SeedOutcome.Completed, await CreateSeeder(context, batchSize: 100).SeedAsync(_seedFolder));
        }

        await using var verify = database.CreateContext();

        // 20 CSV rows, one of which was already present: 20 distinct FdcIds.
        Assert.Equal(20, await verify.Foods.CountAsync());
        Assert.Equal(20, await verify.Foods.Select(f => f.FdcId).Distinct().CountAsync());
    }

    [Fact]
    public async Task Seed_WhenADatabaseErrorIsNotADuplicate_IsNotSwallowed()
    {
        WriteCsv(rowCount: 10);

        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        // A translator that never reports a unique violation forces the seeder
        // down the "genuine failure" path, which must propagate.
        var seeder = new UsdaFoodSeeder(
            context,
            new NeverUniqueTranslator(),
            NullLogger<UsdaFoodSeeder>.Instance,
            TimeProvider.System,
            batchSize: 5);

        // Break the insert: a NOT NULL column violated by a row the CSV produces.
        await context.Database.ExecuteSqlRawAsync(
            """CREATE TRIGGER "force_failure" BEFORE INSERT ON "Foods" BEGIN SELECT RAISE(ABORT, 'forced failure'); END;""");

        await Assert.ThrowsAnyAsync<DbUpdateException>(() => seeder.SeedAsync(_seedFolder));

        await using var verify = database.CreateContext();

        var history = await verify.SeedHistories.SingleAsync();
        Assert.Equal(SeedStatus.Failed, history.Status);

        // The sanitized summary records the type only — never provider text.
        Assert.NotNull(history.ErrorSummary);
        Assert.DoesNotContain("forced failure", history.ErrorSummary!, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("RAISE", history.ErrorSummary!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Seed_WhenTheDatasetIsMissing_SkipsWithoutCreatingHistory()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        var outcome = await CreateSeeder(context).SeedAsync(_seedFolder);

        Assert.Equal(SeedOutcome.SkippedMissingSource, outcome);
        Assert.Equal(0, await context.SeedHistories.CountAsync());
    }

    [Fact]
    public async Task Seed_PopulatesNormalizedNameForCustomFoodLookups()
    {
        WriteCsv(rowCount: 3);

        await using var database = await SqliteTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        await CreateSeeder(context).SeedAsync(_seedFolder);

        await using var verify = database.CreateContext();
        var food = await verify.Foods.FirstAsync();

        Assert.Equal(food.Name.Trim().ToUpperInvariant(), food.NormalizedName);
    }

    private UsdaFoodSeeder CreateSeeder(
        ApplicationDbContext context,
        int batchSize = 1000,
        Action<int>? onBatchCommitted = null)
    {
        return new UsdaFoodSeeder(
            context,
            new UniqueConstraintTranslator(),
            NullLogger<UsdaFoodSeeder>.Instance,
            TimeProvider.System,
            batchSize)
        {
            AfterBatchCommitted = onBatchCommitted
        };
    }

    private static ApplicationDbContext CreateFileContext(string connectionString)
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseSqlite(connectionString)
            .Options;
        return new ApplicationDbContext(options);
    }

    private void WriteCsv(int rowCount)
    {
        var path = Path.Combine(_seedFolder, "usda_calorie_dataset.csv");

        using var writer = new StreamWriter(path);
        writer.WriteLine("fdc_id,name,source_type,kcal_100g,protein_100g,carbs_100g,fat_100g,sugar_100g,fiber_100g,sodium_mg_100g");

        for (var i = 1; i <= rowCount; i++)
        {
            writer.WriteLine($"{i},Food {i},USDA,{100 + i},{i},{i * 2},{i * 3},{i},{i},{i * 10}");
        }
    }

    /// <summary>Reports every failure as non-unique, forcing the propagate path.</summary>
    private sealed class NeverUniqueTranslator : IUniqueConstraintTranslator
    {
        public bool IsUniqueViolation(Exception exception) => false;
    }
}
