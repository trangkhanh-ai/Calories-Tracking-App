using System.Globalization;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Domain.Entities;
using CsvHelper;
using CsvHelper.Configuration;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace CaloriesTracking.Infrastructure.Data.Seeders;

/// <summary>
/// Resumable, idempotent USDA import.
///
/// Replaces the previous "catch DbUpdateException and skip the whole batch"
/// behaviour, which could silently discard thousands of valid rows because a
/// single row conflicted. Progress is checkpointed in <see cref="SeedHistory"/>
/// so an interrupted deploy resumes instead of restarting, and a lease prevents
/// two instances from importing concurrently.
/// </summary>
public sealed class UsdaFoodSeeder
{
    public const string SeedName = "usda-foods";
    public const string SeedVersion = "1";

    private const int DefaultBatchSize = 2_000;

    /// <summary>
    /// Lease duration. Long enough to cover a slow batch, short enough that a
    /// crashed instance does not block the next deploy for long.
    /// </summary>
    private static readonly TimeSpan LockDuration = TimeSpan.FromMinutes(10);

    private readonly ApplicationDbContext _dbContext;
    private readonly IUniqueConstraintTranslator _constraintTranslator;
    private readonly ILogger<UsdaFoodSeeder> _logger;
    private readonly TimeProvider _timeProvider;
    private readonly int _batchSize;

    public UsdaFoodSeeder(
        ApplicationDbContext dbContext,
        IUniqueConstraintTranslator constraintTranslator,
        ILogger<UsdaFoodSeeder> logger,
        TimeProvider timeProvider,
        int batchSize = DefaultBatchSize)
    {
        _dbContext = dbContext;
        _constraintTranslator = constraintTranslator;
        _logger = logger;
        _timeProvider = timeProvider;
        _batchSize = batchSize > 0 ? batchSize : DefaultBatchSize;
    }

    /// <summary>
    /// Test seam invoked after each batch is durably committed, receiving the
    /// running processed-row count. Lets interruption tests cancel at a precise
    /// checkpoint instead of racing a real timer. Never set in production.
    /// </summary>
    internal Action<int>? AfterBatchCommitted { get; set; }

    /// <summary>
    /// Imports the USDA CSV. Safe to call on every startup: a completed seed
    /// returns immediately, and an interrupted one resumes from its checkpoint.
    /// </summary>
    public async Task<SeedOutcome> SeedAsync(string seedDataFolderPath, CancellationToken cancellationToken = default)
    {
        var csvFilePath = Path.Combine(seedDataFolderPath, "usda_calorie_dataset.csv");
        if (!File.Exists(csvFilePath))
        {
            _logger.LogInformation(
                "USDA seed skipped: dataset not found in the configured seed folder.");
            return SeedOutcome.SkippedMissingSource;
        }

        var history = await AcquireLeaseAsync(cancellationToken);
        if (history is null)
        {
            return SeedOutcome.SkippedAlreadyRunning;
        }

        if (history.Status == SeedStatus.Completed)
        {
            _logger.LogInformation(
                "USDA seed {SeedName} v{SeedVersion} already completed with {ProcessedRows} rows.",
                SeedName,
                SeedVersion,
                history.ProcessedRows);
            return SeedOutcome.AlreadyCompleted;
        }

        try
        {
            await ImportAsync(history, csvFilePath, cancellationToken);

            history.Status = SeedStatus.Completed;
            history.CompletedAt = _timeProvider.GetUtcNow().UtcDateTime;
            history.ErrorSummary = null;
            await TouchAndSaveAsync(history, releaseLock: true, cancellationToken);

            _logger.LogInformation(
                "USDA seed completed. Rows written across all attempts: {ProcessedRows}.",
                history.ProcessedRows);

            return SeedOutcome.Completed;
        }
        catch (OperationCanceledException)
        {
            // Cancellation is not a failure: keep the checkpoint so the next
            // start resumes, and release the lease so it is not blocked.
            history.Status = SeedStatus.Running;
            await TouchAndSaveAsync(history, releaseLock: true, CancellationToken.None);

            _logger.LogWarning(
                "USDA seed cancelled at source row {LastRow}. Progress checkpointed for resume.",
                history.LastProcessedSourceRow);

            throw;
        }
        catch (Exception exception)
        {
            history.Status = SeedStatus.Failed;
            // Store the exception TYPE only. Provider messages can embed
            // connection details and row payloads.
            history.ErrorSummary = $"Failed at source row {history.LastProcessedSourceRow} ({exception.GetType().Name}).";
            await TouchAndSaveAsync(history, releaseLock: true, CancellationToken.None);

            _logger.LogError(
                exception,
                "USDA seed failed at source row {LastRow}.",
                history.LastProcessedSourceRow);

            throw;
        }
    }

    private async Task ImportAsync(SeedHistory history, string csvFilePath, CancellationToken cancellationToken)
    {
        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            HasHeaderRecord = true,
            MissingFieldFound = null,
            HeaderValidated = null
        };

        using var reader = new StreamReader(csvFilePath);
        using var csv = new CsvReader(reader, config);

        await csv.ReadAsync();
        csv.ReadHeader();

        var resumeFrom = history.LastProcessedSourceRow;
        var sourceRow = 0;
        var batch = new List<Food>(_batchSize);
        var batchStartRow = resumeFrom;

        if (resumeFrom > 0)
        {
            _logger.LogInformation(
                "Resuming USDA seed after source row {ResumeFrom}.",
                resumeFrom);
        }

        while (await csv.ReadAsync())
        {
            cancellationToken.ThrowIfCancellationRequested();
            sourceRow++;

            // Streamed skip. The checkpoint is a row position, so resuming never
            // requires loading previously-imported FdcIds into memory.
            if (sourceRow <= resumeFrom)
            {
                continue;
            }

            if (batch.Count == 0)
            {
                batchStartRow = sourceRow - 1;
            }

            batch.Add(ReadFood(csv));

            if (batch.Count >= _batchSize)
            {
                await FlushBatchAsync(history, batch, batchStartRow, sourceRow, cancellationToken);
                batch.Clear();
            }
        }

        if (batch.Count > 0)
        {
            await FlushBatchAsync(history, batch, batchStartRow, sourceRow, cancellationToken);
        }

        history.TotalRows = sourceRow;
    }

    /// <summary>
    /// Writes one batch. On a unique conflict the batch is retried row by row so
    /// a single duplicate costs one row, not the entire batch. Any non-duplicate
    /// database error propagates untouched.
    /// </summary>
    private async Task FlushBatchAsync(
        SeedHistory history,
        List<Food> batch,
        int batchStartRow,
        int batchEndRow,
        CancellationToken cancellationToken)
    {
        await _dbContext.Foods.AddRangeAsync(batch, cancellationToken);

        try
        {
            await _dbContext.SaveChangesAsync(cancellationToken);
            history.ProcessedRows += batch.Count;
        }
        catch (Exception exception) when (_constraintTranslator.IsUniqueViolation(exception))
        {
            DetachFoods();

            _logger.LogWarning(
                "Duplicate detected in USDA batch covering source rows {Start}-{End}. Falling back to per-row insert.",
                batchStartRow + 1,
                batchEndRow);

            history.ProcessedRows += await InsertIndividuallyAsync(batch, cancellationToken);
        }
        finally
        {
            DetachFoods();
        }

        // Checkpoint only after the rows above are durable, so a crash can
        // never mark progress the database did not accept.
        history.LastProcessedSourceRow = batchEndRow;
        await TouchAndSaveAsync(history, releaseLock: false, cancellationToken);

        AfterBatchCommitted?.Invoke(history.ProcessedRows);
    }

    private async Task<int> InsertIndividuallyAsync(List<Food> batch, CancellationToken cancellationToken)
    {
        var inserted = 0;

        foreach (var food in batch)
        {
            cancellationToken.ThrowIfCancellationRequested();

            _dbContext.Foods.Add(food);

            try
            {
                await _dbContext.SaveChangesAsync(cancellationToken);
                inserted++;
            }
            catch (Exception exception) when (_constraintTranslator.IsUniqueViolation(exception))
            {
                // Already present from an earlier run — idempotent, so skip it.
                // Only this row is skipped; the rest of the batch still lands.
            }
            finally
            {
                DetachFoods();
            }
        }

        return inserted;
    }

    /// <summary>
    /// Releases the imported rows without touching the tracked
    /// <see cref="SeedHistory"/>. A blanket ChangeTracker.Clear() would detach
    /// the history too, silently discarding every checkpoint write.
    /// </summary>
    private void DetachFoods()
    {
        foreach (var entry in _dbContext.ChangeTracker.Entries<Food>().ToList())
        {
            entry.State = EntityState.Detached;
        }
    }

    private static Food ReadFood(CsvReader csv)
    {
        var name = csv.GetField<string>("name") ?? "Unknown";

        return new Food
        {
            FdcId = csv.GetField<int?>("fdc_id"),
            Name = name,
            NormalizedName = name.Trim().ToUpperInvariant(),
            SourceType = csv.GetField<string>("source_type"),
            CaloriesPer100g = csv.GetField<decimal>("kcal_100g"),
            Protein = csv.GetField<decimal>("protein_100g"),
            Carbs = csv.GetField<decimal>("carbs_100g"),
            Fat = csv.GetField<decimal>("fat_100g"),
            Sugar = csv.GetField<decimal?>("sugar_100g"),
            Fiber = csv.GetField<decimal?>("fiber_100g"),
            Sodium = csv.GetField<decimal?>("sodium_mg_100g")
        };
    }

    /// <summary>
    /// Claims the seed for this instance. Returns null when a peer holds an
    /// unexpired lease, which is the signal to skip rather than seed in parallel.
    /// </summary>
    private async Task<SeedHistory?> AcquireLeaseAsync(CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow().UtcDateTime;
        var owner = Guid.NewGuid().ToString("N");

        var history = await _dbContext.SeedHistories
            .FirstOrDefaultAsync(x => x.Name == SeedName && x.Version == SeedVersion, cancellationToken);

        if (history is null)
        {
            history = new SeedHistory
            {
                Name = SeedName,
                Version = SeedVersion,
                Status = SeedStatus.Running,
                StartedAt = now,
                UpdatedAt = now,
                LockOwner = owner,
                LockExpiresAt = now.Add(LockDuration)
            };

            _dbContext.SeedHistories.Add(history);

            try
            {
                await _dbContext.SaveChangesAsync(cancellationToken);
                return history;
            }
            catch (Exception exception) when (_constraintTranslator.IsUniqueViolation(exception))
            {
                // The (Name, Version) unique index rejected us: a peer created
                // the row first. Fall through and evaluate their lease.
                _dbContext.ChangeTracker.Clear();

                history = await _dbContext.SeedHistories
                    .FirstOrDefaultAsync(x => x.Name == SeedName && x.Version == SeedVersion, cancellationToken);

                if (history is null)
                {
                    throw new DataIntegrityAppException(
                        "The seed history row could not be resolved after a concurrent insert.");
                }
            }
        }

        if (history.Status == SeedStatus.Completed)
        {
            return history;
        }

        var leaseHeld = history.LockExpiresAt.HasValue && history.LockExpiresAt.Value > now;
        if (leaseHeld)
        {
            _logger.LogInformation(
                "USDA seed skipped: another instance holds the lease until {LockExpiresAt:o}.",
                history.LockExpiresAt);
            return null;
        }

        history.Status = SeedStatus.Running;
        history.LockOwner = owner;
        history.LockExpiresAt = now.Add(LockDuration);
        history.UpdatedAt = now;
        await _dbContext.SaveChangesAsync(cancellationToken);

        return history;
    }

    private async Task TouchAndSaveAsync(SeedHistory history, bool releaseLock, CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow().UtcDateTime;
        history.UpdatedAt = now;

        if (releaseLock)
        {
            history.LockOwner = null;
            history.LockExpiresAt = null;
        }
        else
        {
            // Extend the lease while work is actively progressing.
            history.LockExpiresAt = now.Add(LockDuration);
        }

        await _dbContext.SaveChangesAsync(cancellationToken);
    }
}

public enum SeedOutcome
{
    Completed,
    AlreadyCompleted,
    SkippedAlreadyRunning,
    SkippedMissingSource
}
