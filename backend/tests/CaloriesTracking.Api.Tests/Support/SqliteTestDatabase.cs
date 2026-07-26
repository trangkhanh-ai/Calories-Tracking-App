using CaloriesTracking.Infrastructure.Data;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Api.Tests.Support;

/// <summary>
/// A real SQLite database held open in memory for the lifetime of the test.
///
/// Uses the actual provider rather than the InMemory provider because these
/// tests exist to exercise unique indexes, partial indexes, and constraint
/// violations — none of which the InMemory provider enforces.
/// </summary>
public sealed class SqliteTestDatabase : IAsyncDisposable
{
    private readonly SqliteConnection _connection;

    private SqliteTestDatabase(SqliteConnection connection)
    {
        _connection = connection;
    }

    public static async Task<SqliteTestDatabase> CreateAsync()
    {
        // A shared in-memory database survives only while a connection is open,
        // so this one is held until disposal.
        var connection = new SqliteConnection("DataSource=:memory:");
        await connection.OpenAsync();

        var database = new SqliteTestDatabase(connection);

        await using var context = database.CreateContext();
        await context.Database.MigrateAsync();

        return database;
    }

    /// <summary>
    /// A fresh context over the same connection. Separate contexts are what
    /// make a concurrency test meaningful — two contexts each have their own
    /// change tracker, exactly like two concurrent requests.
    /// </summary>
    public ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseSqlite(_connection)
            .Options;

        return new ApplicationDbContext(options);
    }

    public async ValueTask DisposeAsync()
    {
        await _connection.DisposeAsync();
    }
}
