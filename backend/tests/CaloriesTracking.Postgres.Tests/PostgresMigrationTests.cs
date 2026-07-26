using CaloriesTracking.Postgres.Tests.Support;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace CaloriesTracking.Postgres.Tests;

public sealed class PostgresMigrationTests
{
    [PostgresFact]
    public async Task FreshDatabaseAppliesMigrationsAndCreatesExpectedCatalog()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using var context = database.CreateContext();

        await context.Database.MigrateAsync();

        Assert.True(await database.IsSslEnabledAsync());

        await using var connection = await database.OpenConnectionAsync();
        var tables = await ReadSetAsync(
            connection,
            "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = 'public';");

        Assert.Contains("Users", tables);
        Assert.Contains("Foods", tables);
        Assert.Contains("DailyLogs", tables);
        Assert.Contains("MealItems", tables);
        Assert.Contains("SeedHistories", tables);

        var columns = await ReadSetAsync(
            connection,
            """
            SELECT table_name || '.' || column_name
            FROM information_schema.columns
            WHERE table_schema = 'public';
            """);

        Assert.Contains("Users.NormalizedUsername", columns);
        Assert.Contains("Users.NormalizedEmail", columns);
        Assert.Contains("Foods.FdcId", columns);
        Assert.Contains("Foods.NormalizedName", columns);
        Assert.Contains("SeedHistories.Name", columns);
        Assert.Contains("SeedHistories.Version", columns);
        Assert.Contains("SeedHistories.Status", columns);
        Assert.Contains("DailyLogs.UserId", columns);
        Assert.Contains("DailyLogs.Date", columns);

        var indexes = await ReadIndexDefinitionsAsync(connection);
        AssertUniqueIndex(indexes, "IX_Users_NormalizedUsername", "NormalizedUsername");
        AssertUniqueIndex(indexes, "IX_Users_NormalizedEmail", "NormalizedEmail");
        AssertUniqueIndex(indexes, "IX_SeedHistories_Name_Version", "Name", "Version");
        AssertUniqueIndex(indexes, "IX_DailyLogs_UserId_Date", "UserId", "Date");

        AssertUniqueIndex(indexes, "IX_Foods_FdcId", "FdcId");
        Assert.Contains(
            "\"FdcId\" IS NOT NULL",
            indexes["IX_Foods_FdcId"].Predicate,
            StringComparison.OrdinalIgnoreCase);

        AssertUniqueIndex(indexes, "IX_Foods_NormalizedName_Custom", "NormalizedName");
        Assert.Contains(
            "\"FdcId\" IS NULL",
            indexes["IX_Foods_NormalizedName_Custom"].Predicate,
            StringComparison.OrdinalIgnoreCase);

        var appliedMigrations = await ReadSetAsync(
            connection,
            "SELECT \"MigrationId\" FROM \"__EFMigrationsHistory\";");
        Assert.Contains("20260725173840_AddNormalizedIdentityAndSeedHistory", appliedMigrations);

        var expectedMigrations = context.Database.GetMigrations();
        Assert.Equal(
            expectedMigrations.OrderBy(migration => migration, StringComparer.Ordinal),
            appliedMigrations.OrderBy(migration => migration, StringComparer.Ordinal));
    }

    [PostgresFact]
    public async Task LegacyRowsAtUniqueFdcIdBoundaryAreNormalizedAndPreserved()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using (var legacy = database.CreateContext())
        {
            await legacy.Database.MigrateAsync("20260725162650_AddUniqueFdcId");
            await legacy.Database.ExecuteSqlRawAsync(
                """
                INSERT INTO "Users" ("Username", "Email", "PasswordHash", "DisplayName")
                VALUES ({0}, {1}, {2}, {3});
                """,
                "LegacyUser",
                "legacy@example.com",
                "legacy-hash",
                "Legacy User");
            await legacy.Database.ExecuteSqlRawAsync(
                """
                INSERT INTO "Foods"
                    ("FdcId", "Name", "SourceType", "CaloriesPer100g", "Protein", "Carbs", "Fat")
                VALUES
                    ({0}, {1}, {2}, {3}, {4}, {5}, {6}),
                    (NULL, {7}, {8}, {9}, {10}, {11}, {12});
                """,
                4411,
                "Legacy USDA",
                "USDA",
                100m,
                1m,
                2m,
                3m,
                "Legacy Custom",
                "Custom",
                200m,
                4m,
                5m,
                6m);
        }

        await using (var upgraded = database.CreateContext())
        {
            await upgraded.Database.MigrateAsync();
        }

        await using var verify = database.CreateContext();
        var user = await verify.Users.SingleAsync();
        Assert.Equal("LEGACYUSER", user.NormalizedUsername);
        Assert.Equal("LEGACY@EXAMPLE.COM", user.NormalizedEmail);

        var foods = await verify.Foods.OrderBy(f => f.Id).ToListAsync();
        Assert.Equal(2, foods.Count);
        Assert.Equal("LEGACY USDA", foods[0].NormalizedName);
        Assert.Equal("LEGACY CUSTOM", foods[1].NormalizedName);
        Assert.Equal(4411, foods[0].FdcId);
    }

    [PostgresFact]
    public async Task LegacyCaseInsensitiveIdentityConflictStopsWithoutDeletingRows()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using (var legacy = database.CreateContext())
        {
            await legacy.Database.MigrateAsync("20260725162650_AddUniqueFdcId");
            await legacy.Database.ExecuteSqlRawAsync(
                """
                INSERT INTO "Users" ("Username", "Email", "PasswordHash", "DisplayName")
                VALUES
                    ({0}, {1}, {2}, {3}),
                    ({4}, {5}, {6}, {7});
                """,
                "LegacyUser",
                "one@example.com",
                "legacy-hash",
                "Legacy User",
                "legacyuser",
                "two@example.com",
                "legacy-hash",
                "Legacy user duplicate");
        }

        Exception exception;
        await using (var upgrading = database.CreateContext())
        {
            exception = await Assert.ThrowsAnyAsync<Exception>(() => upgrading.Database.MigrateAsync());
        }

        var postgres = FindPostgresException(exception);
        Assert.NotNull(postgres);
        Assert.Contains("case-insensitive duplicate username", postgres!.MessageText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Password=", exception.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Host=", exception.ToString(), StringComparison.OrdinalIgnoreCase);

        await using var verify = database.CreateContext();
        Assert.Equal(2, await verify.Users.CountAsync());
        await using var connection = await database.OpenConnectionAsync();
        var applied = await ReadSetAsync(
            connection,
            "SELECT \"MigrationId\" FROM \"__EFMigrationsHistory\";");
        Assert.DoesNotContain("20260725173840_AddNormalizedIdentityAndSeedHistory", applied);
    }

    [PostgresFact]
    public async Task DuplicateFdcIdAtTheTruePreEnforcementBoundaryStopsSafely()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using (var legacy = database.CreateContext())
        {
            await legacy.Database.MigrateAsync("20260723072218_InitialPostgres");
            await legacy.Database.ExecuteSqlRawAsync(
                """
                INSERT INTO "Foods"
                    ("FdcId", "Name", "SourceType", "CaloriesPer100g", "Protein", "Carbs", "Fat")
                VALUES
                    ({0}, {1}, {2}, {3}, {4}, {5}, {6}),
                    ({7}, {8}, {9}, {10}, {11}, {12}, {13});
                """,
                9001,
                "Duplicate one",
                "USDA",
                100m,
                1m,
                2m,
                3m,
                9001,
                "Duplicate two",
                "USDA",
                101m,
                1m,
                2m,
                3m);
        }

        Exception exception;
        await using (var upgrading = database.CreateContext())
        {
            exception = await Assert.ThrowsAnyAsync<Exception>(
                () => upgrading.Database.MigrateAsync("20260725162650_AddUniqueFdcId"));
        }

        var postgres = FindPostgresException(exception);
        Assert.NotNull(postgres);
        Assert.Contains("duplicate non-null FdcId", postgres!.MessageText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Password=", exception.ToString(), StringComparison.OrdinalIgnoreCase);

        await using var verify = database.CreateContext();
        Assert.Equal(2, await verify.Foods.CountAsync());
        await using var connection = await database.OpenConnectionAsync();
        var applied = await ReadSetAsync(
            connection,
            "SELECT \"MigrationId\" FROM \"__EFMigrationsHistory\";");
        Assert.Contains("20260723072218_InitialPostgres", applied);
        Assert.DoesNotContain("20260725162650_AddUniqueFdcId", applied);
    }

    private static async Task<HashSet<string>> ReadSetAsync(NpgsqlConnection connection, string sql)
    {
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync();
        var values = new HashSet<string>(StringComparer.Ordinal);
        while (await reader.ReadAsync())
        {
            values.Add(reader.GetString(0));
        }

        return values;
    }

    private static async Task<Dictionary<string, IndexDefinition>> ReadIndexDefinitionsAsync(
        NpgsqlConnection connection)
    {
        const string sql =
            """
            SELECT
                p.indexname,
                i.indisunique,
                pg_get_expr(i.indpred, i.indrelid),
                keys.key_columns
            FROM pg_catalog.pg_indexes p
            JOIN pg_catalog.pg_namespace index_namespace
                ON index_namespace.nspname = p.schemaname
            JOIN pg_catalog.pg_class index_class
                ON index_class.relnamespace = index_namespace.oid
                AND index_class.relname = p.indexname
            JOIN pg_catalog.pg_index i
                ON i.indexrelid = index_class.oid
            JOIN pg_catalog.pg_class table_class
                ON table_class.oid = i.indrelid
                AND table_class.relname = p.tablename
            JOIN pg_catalog.pg_namespace table_namespace
                ON table_namespace.oid = table_class.relnamespace
                AND table_namespace.nspname = p.schemaname
            LEFT JOIN LATERAL (
                SELECT array_agg(
                    COALESCE(attribute.attname::text, '<expression>')
                    ORDER BY key.ordinality) AS key_columns
                FROM unnest(i.indkey::smallint[]) WITH ORDINALITY AS key(attnum, ordinality)
                LEFT JOIN pg_catalog.pg_attribute attribute
                    ON attribute.attrelid = i.indrelid
                    AND attribute.attnum = key.attnum
                WHERE key.ordinality <= i.indnkeyatts
            ) keys ON true
            WHERE p.schemaname = 'public';
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync();
        var indexes = new Dictionary<string, IndexDefinition>(StringComparer.Ordinal);
        while (await reader.ReadAsync())
        {
            indexes[reader.GetString(0)] = new IndexDefinition(
                reader.GetBoolean(1),
                reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                reader.GetFieldValue<string[]>(3));
        }

        return indexes;
    }

    private static void AssertUniqueIndex(
        IReadOnlyDictionary<string, IndexDefinition> indexes,
        string name,
        params string[] columns)
    {
        Assert.True(indexes.TryGetValue(name, out var index), $"Expected index {name} to exist.");
        Assert.True(index.Unique, $"Expected index {name} to be unique.");
        Assert.Equal(columns, index.KeyColumns);
    }

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

    private sealed record IndexDefinition(bool Unique, string Predicate, string[] KeyColumns);
}

public sealed class PostgresTestDatabaseTests
{
    [Theory]
    [InlineData(SslMode.Disable, SslMode.Require)]
    [InlineData(SslMode.Allow, SslMode.Require)]
    [InlineData(SslMode.Prefer, SslMode.Require)]
    [InlineData(SslMode.Require, SslMode.Require)]
    [InlineData(SslMode.VerifyCA, SslMode.VerifyCA)]
    [InlineData(SslMode.VerifyFull, SslMode.VerifyFull)]
    public void SecureBuilder_PreservesOrRaisesTlsVerification(
        SslMode configuredMode,
        SslMode expectedMode)
    {
        var builder = PostgresTestDatabase.SecureBuilder(
            $"Host=localhost;Database=postgres;Username=user;Password=secret;Ssl Mode={configuredMode}");

        Assert.Equal(expectedMode, builder.SslMode);
        Assert.Equal(ChannelBinding.Require, builder.ChannelBinding);
        Assert.False(builder.IncludeErrorDetail);
        Assert.False(builder.LogParameters);
        Assert.False(builder.PersistSecurityInfo);
    }

    [Fact]
    public void SecureBuilder_WhenSslModeIsOmitted_RequiresTls()
    {
        var builder = PostgresTestDatabase.SecureBuilder(
            "Host=localhost;Database=postgres;Username=user;Password=secret");

        Assert.Equal(SslMode.Require, builder.SslMode);
        Assert.Equal(ChannelBinding.Require, builder.ChannelBinding);
    }
}
