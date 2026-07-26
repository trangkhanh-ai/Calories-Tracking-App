namespace CaloriesTracking.Application.Abstractions;

/// <summary>
/// Classifies persistence failures without leaking provider types into the
/// Application layer. Implemented in Infrastructure where the concrete
/// EF Core / Npgsql / SQLite exception types are available.
/// </summary>
public interface IUniqueConstraintTranslator
{
    /// <summary>
    /// True when the exception is a unique/primary-key constraint violation.
    /// False for every other database error, so genuine failures are never
    /// silently reclassified as a conflict.
    /// </summary>
    bool IsUniqueViolation(Exception exception);
}
