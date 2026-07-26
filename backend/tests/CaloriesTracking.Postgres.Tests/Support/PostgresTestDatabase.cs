using CaloriesTracking.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Xunit.Sdk;

namespace CaloriesTracking.Postgres.Tests.Support;

public sealed class PostgresFactAttribute : FactAttribute
{
    public PostgresFactAttribute()
    {
        var configured = Environment.GetEnvironmentVariable("POSTGRES_TEST_ADMIN_CONNECTION_STRING");
        var required = string.Equals(
            Environment.GetEnvironmentVariable("POSTGRES_TESTS_REQUIRED"),
            "true",
            StringComparison.OrdinalIgnoreCase);

        if (string.IsNullOrWhiteSpace(configured) && !required)
        {
            Skip = "POSTGRES_TEST_ADMIN_CONNECTION_STRING is not configured; PostgreSQL integration tests were skipped.";
        }
    }
}

public sealed class PostgresTestDatabase : IAsyncDisposable
{
    private const string AdminConnectionVariable = "POSTGRES_TEST_ADMIN_CONNECTION_STRING";
    private const string RequiredVariable = "POSTGRES_TESTS_REQUIRED";

    private readonly string _adminConnectionString;
    private readonly string _databaseName;
    private readonly string _testConnectionString;
    private bool _disposed;

    private PostgresTestDatabase(
        string adminConnectionString,
        string databaseName,
        string testConnectionString)
    {
        _adminConnectionString = adminConnectionString;
        _databaseName = databaseName;
        _testConnectionString = testConnectionString;
    }

    public static async Task<PostgresTestDatabase> CreateAsync()
    {
        var configured = Environment.GetEnvironmentVariable(AdminConnectionVariable);
        if (string.IsNullOrWhiteSpace(configured))
        {
            var required = string.Equals(
                Environment.GetEnvironmentVariable(RequiredVariable),
                "true",
                StringComparison.OrdinalIgnoreCase);

            if (required)
            {
                throw new InvalidOperationException(
                    $"{AdminConnectionVariable} is required when {RequiredVariable}=true.");
            }

            throw SkipException.ForSkip(
                $"{AdminConnectionVariable} is not configured; PostgreSQL integration tests were skipped.");
        }

        var adminBuilder = SecureBuilder(configured);
        adminBuilder.Pooling = false;

        var databaseName = $"ct_postgres_tests_{Guid.NewGuid():N}";
        var testBuilder = new NpgsqlConnectionStringBuilder(adminBuilder.ConnectionString)
        {
            Database = databaseName,
            Pooling = true,
            ApplicationName = "calories-tracking-postgres-tests"
        };

        var database = new PostgresTestDatabase(
            adminBuilder.ConnectionString,
            databaseName,
            testBuilder.ConnectionString);

        try
        {
            await using var admin = new NpgsqlConnection(database._adminConnectionString);
            await admin.OpenAsync();

            await using var command = admin.CreateCommand();
            command.CommandText = $"CREATE DATABASE {QuoteIdentifier(databaseName)}";
            command.CommandTimeout = 30;
            await command.ExecuteNonQueryAsync();

            return database;
        }
        catch
        {
            await database.DisposeAsync();
            throw;
        }
    }

    public PostgresApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<PostgresApplicationDbContext>()
            .UseNpgsql(
                _testConnectionString,
                npgsql => npgsql.MigrationsAssembly(typeof(PostgresApplicationDbContext).Assembly.GetName().Name))
            .Options;

        return new PostgresApplicationDbContext(options);
    }

    internal string ConnectionString => _testConnectionString;

    public async Task<NpgsqlConnection> OpenConnectionAsync(CancellationToken cancellationToken = default)
    {
        var connection = new NpgsqlConnection(_testConnectionString);
        try
        {
            await connection.OpenAsync(cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    public async Task<bool> IsSslEnabledAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT ssl FROM pg_catalog.pg_stat_ssl WHERE pid = pg_backend_pid();";

        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is true;
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        NpgsqlConnection.ClearAllPools();

        try
        {
            await using var admin = new NpgsqlConnection(_adminConnectionString);
            await admin.OpenAsync();

            await using var command = admin.CreateCommand();
            command.CommandText = $"DROP DATABASE IF EXISTS {QuoteIdentifier(_databaseName)} WITH (FORCE)";
            command.CommandTimeout = 30;
            await command.ExecuteNonQueryAsync();
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
        }
    }

    private static NpgsqlConnectionStringBuilder SecureBuilder(string connectionString)
    {
        var builder = new NpgsqlConnectionStringBuilder(connectionString)
        {
            SslMode = SslMode.Require,
            ChannelBinding = ChannelBinding.Require,
            IncludeErrorDetail = false,
            LogParameters = false,
            PersistSecurityInfo = false
        };

        return builder;
    }

    private static string QuoteIdentifier(string identifier) =>
        $"\"{identifier.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
}
