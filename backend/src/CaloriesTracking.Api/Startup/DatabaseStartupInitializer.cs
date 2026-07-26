using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Data.Seeders;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Api.Startup;

public sealed class DatabaseStartupInitializer
{
    private readonly ApplicationDbContext _dbContext;
    private readonly UsdaFoodSeeder _seeder;
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;
    private readonly ILogger<DatabaseStartupInitializer> _logger;

    public DatabaseStartupInitializer(
        ApplicationDbContext dbContext,
        UsdaFoodSeeder seeder,
        IConfiguration configuration,
        IHostEnvironment environment,
        ILogger<DatabaseStartupInitializer> logger)
    {
        _dbContext = dbContext;
        _seeder = seeder;
        _configuration = configuration;
        _environment = environment;
        _logger = logger;
    }

    public async Task InitializeAsync(
        string? seedDataFolderPath = null,
        CancellationToken cancellationToken = default)
    {
        var seedingEnabled = GetSeedingEnabled();

        await MigrationPreflight.EnsureNoDuplicateFoodFdcIdsAsync(
            _dbContext,
            cancellationToken);
        await MigrationPreflight.EnsureNoCaseInsensitiveUserConflictsAsync(
            _dbContext,
            cancellationToken);

        await _dbContext.Database.MigrateAsync(cancellationToken);
        await DatabaseSeeder.EnsureNoDuplicateFoodIdentitiesAsync(
            _dbContext,
            cancellationToken);

        if (!seedingEnabled)
        {
            _logger.LogInformation("Database migrations completed; USDA startup seeding is disabled.");
            return;
        }

        var outcome = await _seeder.SeedAsync(
            seedDataFolderPath ?? ResolveSeedDataFolder(),
            cancellationToken);

        if (outcome == SeedOutcome.SkippedMissingSource)
        {
            throw new InvalidOperationException(
                "USDA seed source is unavailable while startup seeding is enabled.");
        }
    }

    private bool GetSeedingEnabled()
    {
        var configuredValue = _configuration["Seeding:Enabled"];
        if (string.IsNullOrWhiteSpace(configuredValue))
        {
            if (_environment.IsProduction())
            {
                throw new InvalidOperationException(
                    "Seeding:Enabled must be explicitly configured in Production.");
            }

            return false;
        }

        if (!bool.TryParse(configuredValue, out var enabled))
        {
            throw new InvalidOperationException("Seeding:Enabled must be either true or false.");
        }

        return enabled;
    }

    private string ResolveSeedDataFolder()
    {
        var publishedSeedFolder = Path.Combine(AppContext.BaseDirectory, "SeedData");
        if (Directory.Exists(publishedSeedFolder))
        {
            return publishedSeedFolder;
        }

        return Path.Combine(
            _environment.ContentRootPath,
            "..",
            "CaloriesTracking.Infrastructure",
            "Data",
            "SeedData");
    }
}
