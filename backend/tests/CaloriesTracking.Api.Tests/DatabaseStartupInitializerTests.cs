using CaloriesTracking.Api.Startup;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Data.Seeders;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CaloriesTracking.Api.Tests;

public sealed class DatabaseStartupInitializerTests : IDisposable
{
    private readonly string _resolverRoot = Path.Combine(
        Path.GetTempPath(),
        $"startup-resolver-{Guid.NewGuid():N}");
    private readonly string _seedFolder = Path.Combine(
        Path.GetTempPath(),
        $"startup-seed-{Guid.NewGuid():N}");

    public DatabaseStartupInitializerTests()
    {
        Directory.CreateDirectory(_seedFolder);
        Directory.CreateDirectory(_resolverRoot);
    }

    public void Dispose()
    {
        if (Directory.Exists(_seedFolder))
        {
            Directory.Delete(_seedFolder, recursive: true);
        }

        if (Directory.Exists(_resolverRoot))
        {
            Directory.Delete(_resolverRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Initialize_WhenSeedingDisabled_StillRunsPreflightsAndMigrations()
    {
        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);
        var initializer = CreateInitializer(
            context,
            BuildConfiguration(("Seeding:Enabled", "false")),
            Environments.Development);

        await initializer.InitializeAsync(_seedFolder);

        Assert.NotEmpty(await context.Database.GetAppliedMigrationsAsync());
        Assert.True(await context.Database.CanConnectAsync());
        Assert.Equal(0, await context.SeedHistories.CountAsync());
    }

    [Fact]
    public async Task Initialize_WhenSeedingEnabled_ImportsAndCompletesTheSeed()
    {
        WriteCsv(rowCount: 3);
        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);
        var initializer = CreateInitializer(
            context,
            BuildConfiguration(("Seeding:Enabled", "true")),
            Environments.Development);

        await initializer.InitializeAsync(_seedFolder);

        Assert.Equal(3, await context.Foods.CountAsync());
        Assert.Equal(SeedStatus.Completed, (await context.SeedHistories.SingleAsync()).Status);
    }

    [Fact]
    public async Task Initialize_WhenEnabledSourceIsMissing_LogsSanitizedWarningAndContinuesStartup()
    {
        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);
        var logger = new RecordingLogger();
        var initializer = CreateInitializer(
            context,
            BuildConfiguration(("Seeding:Enabled", "true")),
            Environments.Development,
            logger);

        await initializer.InitializeAsync(_seedFolder);

        Assert.True(await context.Database.CanConnectAsync());
        Assert.Equal(0, await context.SeedHistories.CountAsync());
        Assert.Contains(logger.Entries, entry =>
            entry.Level == LogLevel.Warning &&
            entry.Message.Contains("dataset is unavailable", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(logger.Entries, entry =>
            entry.Message.Contains(_seedFolder, StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Initialize_WhenSeederHitsARealDatabaseFailure_PropagatesAndFailsStartup()
    {
        WriteCsv(rowCount: 1);
        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);

        await context.Database.MigrateAsync();
        await context.Database.ExecuteSqlRawAsync(
            """CREATE TRIGGER "force_startup_failure" BEFORE INSERT ON "Foods" BEGIN SELECT RAISE(ABORT, 'credential-like-provider-detail'); END;""");

        var logger = new RecordingLogger();
        var initializer = CreateInitializer(
            context,
            BuildConfiguration(("Seeding:Enabled", "true")),
            Environments.Development,
            logger,
            new NeverUniqueTranslator());

        await Assert.ThrowsAnyAsync<DbUpdateException>(
            () => initializer.InitializeAsync(_seedFolder));

        Assert.DoesNotContain(logger.Entries, entry => entry.Exception is not null);
        Assert.DoesNotContain(logger.Entries, entry =>
            entry.Message.Contains("credential-like-provider-detail", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Initialize_InProductionWithoutExplicitSeedingSetting_FailsClearly()
    {
        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);
        var initializer = CreateInitializer(
            context,
            BuildBaseConfiguration(),
            Environments.Production);

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            () => initializer.InitializeAsync(_seedFolder));

        Assert.Contains("Seeding:Enabled", exception.Message, StringComparison.Ordinal);
        Assert.Contains("Production", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Initialize_InProductionWithExplicitSeedingOverride_AcceptsBaseConfiguration()
    {
        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);
        var initializer = CreateInitializer(
            context,
            BuildBaseConfiguration(("Seeding:Enabled", "false")),
            Environments.Production);

        await initializer.InitializeAsync(_seedFolder);

        Assert.NotEmpty(await context.Database.GetAppliedMigrationsAsync());
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public async Task Initialize_InProductionWithBlankExplicitSeedingOverride_FailsClearly(
        string? configuredValue)
    {
        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);
        var initializer = CreateInitializer(
            context,
            BuildBaseConfiguration(("Seeding:Enabled", configuredValue)),
            Environments.Production);

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            () => initializer.InitializeAsync(_seedFolder));

        Assert.Contains("Seeding:Enabled", exception.Message, StringComparison.Ordinal);
        Assert.Contains("Production", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void SeedDataPathResolver_InDevelopment_FallsBackToSourceTree()
    {
        var contentRoot = Path.Combine(_resolverRoot, "CaloriesTracking.Api");
        var sourceSeedFolder = Path.Combine(
            _resolverRoot,
            "CaloriesTracking.Infrastructure",
            "Data",
            "SeedData");
        Directory.CreateDirectory(sourceSeedFolder);
        var resolver = new SeedDataPathResolver(Path.Combine(_resolverRoot, "published"));

        var resolved = resolver.Resolve(new TestHostEnvironment(Environments.Development)
        {
            ContentRootPath = contentRoot
        });

        Assert.Equal(sourceSeedFolder, resolved);
    }

    [Fact]
    public void SeedDataPathResolver_InProduction_DoesNotFallBackToSourceTree()
    {
        var publishedBase = Path.Combine(_resolverRoot, "published");
        var publishedSeedFolder = Path.Combine(publishedBase, "SeedData");
        var sourceSeedFolder = Path.Combine(
            _resolverRoot,
            "CaloriesTracking.Infrastructure",
            "Data",
            "SeedData");
        Directory.CreateDirectory(sourceSeedFolder);
        var resolver = new SeedDataPathResolver(publishedBase);

        var resolved = resolver.Resolve(new TestHostEnvironment(Environments.Production)
        {
            ContentRootPath = Path.Combine(_resolverRoot, "CaloriesTracking.Api")
        });

        Assert.Equal(publishedSeedFolder, resolved);
    }

    [Fact]
    public async Task Initialize_InProductionWithMissingPublishedCsv_WarnsWithoutUsingSourceTree()
    {
        WriteCsv(rowCount: 1);
        var contentRoot = Path.Combine(_resolverRoot, "CaloriesTracking.Api");
        var sourceSeedFolder = Path.Combine(
            _resolverRoot,
            "CaloriesTracking.Infrastructure",
            "Data",
            "SeedData");
        Directory.CreateDirectory(sourceSeedFolder);
        File.Copy(
            Path.Combine(_seedFolder, "usda_calorie_dataset.csv"),
            Path.Combine(sourceSeedFolder, "usda_calorie_dataset.csv"));

        await using var connection = await OpenDatabaseAsync();
        await using var context = CreateContext(connection);
        var logger = new RecordingLogger();
        var environment = new TestHostEnvironment(Environments.Production)
        {
            ContentRootPath = contentRoot
        };
        var seeder = new UsdaFoodSeeder(
            context,
            new UniqueConstraintTranslator(),
            logger,
            TimeProvider.System,
            batchSize: 2);
        var initializer = new DatabaseStartupInitializer(
            context,
            seeder,
            BuildBaseConfiguration(("Seeding:Enabled", "true")),
            environment,
            new SeedDataPathResolver(Path.Combine(_resolverRoot, "published")),
            logger);

        await initializer.InitializeAsync();

        Assert.Equal(0, await context.Foods.CountAsync());
        Assert.Contains(logger.Entries, entry =>
            entry.Level == LogLevel.Warning &&
            entry.Message.Contains("dataset is unavailable", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(logger.Entries, entry =>
            entry.Message.Contains(sourceSeedFolder, StringComparison.OrdinalIgnoreCase));
    }

    private DatabaseStartupInitializer CreateInitializer(
        ApplicationDbContext context,
        IConfiguration configuration,
        string environmentName,
        RecordingLogger? logger = null,
        IUniqueConstraintTranslator? constraintTranslator = null)
    {
        logger ??= new RecordingLogger();
        var seeder = new UsdaFoodSeeder(
            context,
            constraintTranslator ?? new UniqueConstraintTranslator(),
            logger,
            TimeProvider.System,
            batchSize: 2);

        return new DatabaseStartupInitializer(
            context,
            seeder,
            configuration,
            new TestHostEnvironment(environmentName),
            new SeedDataPathResolver(AppContext.BaseDirectory),
            logger);
    }

    private static IConfiguration BuildConfiguration(params (string Key, string Value)[] values) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(values.ToDictionary(value => value.Key, value => (string?)value.Value))
            .Build();

    private static IConfiguration BuildBaseConfiguration(params (string Key, string? Value)[] overrides)
    {
        var appSettingsPath = FindAppSettingsPath();
        return new ConfigurationBuilder()
            .SetBasePath(Path.GetDirectoryName(appSettingsPath)!)
            .AddJsonFile(Path.GetFileName(appSettingsPath), optional: false)
            .AddInMemoryCollection(overrides.ToDictionary(value => value.Key, value => (string?)value.Value))
            .Build();
    }

    private static string FindAppSettingsPath()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
             directory is not null;
             directory = directory.Parent)
        {
            var candidate = Path.Combine(
                directory.FullName,
                "backend",
                "src",
                "CaloriesTracking.Api",
                "appsettings.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException("Could not locate the API appsettings.json test fixture.");
    }

    private static async Task<SqliteConnection> OpenDatabaseAsync()
    {
        var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        return connection;
    }

    private static ApplicationDbContext CreateContext(SqliteConnection connection)
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseSqlite(connection)
            .Options;
        return new ApplicationDbContext(options);
    }

    private void WriteCsv(int rowCount)
    {
        var path = Path.Combine(_seedFolder, "usda_calorie_dataset.csv");
        using var writer = new StreamWriter(path);
        writer.WriteLine("fdc_id,name,source_type,kcal_100g,protein_100g,carbs_100g,fat_100g,sugar_100g,fiber_100g,sodium_mg_100g");
        for (var row = 1; row <= rowCount; row++)
        {
            writer.WriteLine($"{row},Food {row},USDA,{100 + row},{row},{row},{row},{row},{row},{row}");
        }
    }

    private sealed class NeverUniqueTranslator : IUniqueConstraintTranslator
    {
        public bool IsUniqueViolation(Exception exception) => false;
    }

    private sealed class TestHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "CaloriesTracking.Api.Tests";
        public string ContentRootPath { get; set; } = Directory.GetCurrentDirectory();
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class RecordingLogger : ILogger<DatabaseStartupInitializer>, ILogger<UsdaFoodSeeder>
    {
        public List<(LogLevel Level, string Message, Exception? Exception)> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Entries.Add((logLevel, formatter(state, exception), exception));
        }
    }
}
