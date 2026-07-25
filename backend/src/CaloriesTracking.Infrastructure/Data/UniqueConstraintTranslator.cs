using CaloriesTracking.Application.Abstractions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace CaloriesTracking.Infrastructure.Data;

/// <summary>
/// Maps provider-specific constraint failures onto a single boolean.
/// Classification uses documented numeric error codes, never message text, so
/// it survives locale changes and provider message rewording.
/// </summary>
public sealed class UniqueConstraintTranslator : IUniqueConstraintTranslator
{
    /// <summary>PostgreSQL <c>unique_violation</c> (class 23 — integrity constraint violation).</summary>
    private const string PostgresUniqueViolation = "23505";

    /// <summary>SQLITE_CONSTRAINT (19) — the primary result code for any constraint failure.</summary>
    private const int SqliteConstraint = 19;

    /// <summary>SQLITE_CONSTRAINT_UNIQUE (2067) — extended code for a UNIQUE index.</summary>
    private const int SqliteConstraintUnique = 2067;

    /// <summary>SQLITE_CONSTRAINT_PRIMARYKEY (1555) — extended code for a PK collision.</summary>
    private const int SqliteConstraintPrimaryKey = 1555;

    public bool IsUniqueViolation(Exception exception)
    {
        ArgumentNullException.ThrowIfNull(exception);

        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            switch (current)
            {
                case PostgresException postgres
                    when postgres.SqlState == PostgresUniqueViolation:
                    return true;

                case SqliteException sqlite
                    when sqlite.SqliteExtendedErrorCode is SqliteConstraintUnique or SqliteConstraintPrimaryKey:
                    return true;

                // Older SQLite builds report only the primary code. Treat a bare
                // SQLITE_CONSTRAINT as a unique violation ONLY when no extended
                // code is available, so FK and CHECK failures are not swallowed.
                case SqliteException sqlite
                    when sqlite.SqliteErrorCode == SqliteConstraint
                         && sqlite.SqliteExtendedErrorCode == SqliteConstraint:
                    return true;

                // A DbUpdateException on its own says nothing — keep unwrapping
                // until a provider exception with a real code appears.
                case DbUpdateException:
                    continue;
            }
        }

        return false;
    }
}
