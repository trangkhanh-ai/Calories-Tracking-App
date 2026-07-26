namespace CaloriesTracking.Domain.Entities;

public enum SeedStatus
{
    Pending = 0,
    Running = 1,
    Completed = 2,
    Failed = 3
}

/// <summary>
/// Durable record of a data-seeding run. Lets the USDA import resume from a
/// checkpoint after an interrupted deploy instead of restarting, and lets a
/// second instance detect that a peer already holds the run.
/// </summary>
public class SeedHistory
{
    public int Id { get; set; }

    /// <summary>Logical seed name, e.g. <c>usda-foods</c>.</summary>
    public required string Name { get; set; }

    /// <summary>
    /// Content version. Bumping it re-runs the seed; unique together with
    /// <see cref="Name"/>.
    /// </summary>
    public required string Version { get; set; }

    public SeedStatus Status { get; set; } = SeedStatus.Pending;

    public DateTime StartedAt { get; set; }

    public DateTime UpdatedAt { get; set; }

    public DateTime? CompletedAt { get; set; }

    /// <summary>Rows successfully written so far across all attempts.</summary>
    public int ProcessedRows { get; set; }

    /// <summary>Total CSV rows when known; null while the count is unavailable.</summary>
    public int? TotalRows { get; set; }

    /// <summary>
    /// 1-based index of the last CSV data row durably committed. A resume skips
    /// forward to this position rather than re-reading the whole file into memory.
    /// </summary>
    public int LastProcessedSourceRow { get; set; }

    /// <summary>Sanitized failure summary — never provider text or credentials.</summary>
    public string? ErrorSummary { get; set; }

    /// <summary>
    /// Opaque owner token for the instance currently running the seed. Combined
    /// with <see cref="LockExpiresAt"/> it forms a lease that survives a crash.
    /// </summary>
    public string? LockOwner { get; set; }

    public DateTime? LockExpiresAt { get; set; }
}
