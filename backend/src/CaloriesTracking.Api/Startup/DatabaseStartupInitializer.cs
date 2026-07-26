using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Data.Seeders;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration.Json;

namespace CaloriesTracking.Api.Startup;

public sealed class DatabaseStartupInitializer
{
    private readonly ApplicationDbContext _dbContext;
    private readonly UsdaFoodSeeder _seeder;
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;
    private readonly ISeedDataPathResolver _seedDataPathResolver;
    private readonly ILogger<DatabaseStartupInitializer> _logger;

    public DatabaseStartupInitializer(
        ApplicationDbContext dbContext,
        UsdaFoodSeeder seeder,
        IConfiguration configuration,
        IHostEnvironment environment,
        ISeedDataPathResolver seedDataPathResolver,
        ILogger<DatabaseStartupInitializer> logger)
    {
        _dbContext = dbContext;
        _seeder = seeder;
        _configuration = configuration;
        _environment = environment;
        _seedDataPathResolver = seedDataPathResolver;
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

        await _seeder.SeedAsync(
            seedDataFolderPath ?? _seedDataPathResolver.Resolve(_environment),
            cancellationToken);
    }

    private bool GetSeedingEnabled()
    {
        var configuredValue = _configuration["Seeding:Enabled"];
        if (_environment.IsProduction() && !HasValidExplicitProductionSetting())
        {
            throw new InvalidOperationException(
                "Seeding:Enabled must be explicitly configured in Production.");
        }

        if (string.IsNullOrWhiteSpace(configuredValue))
        {
            return false;
        }

        if (!bool.TryParse(configuredValue, out var enabled))
        {
            throw new InvalidOperationException("Seeding:Enabled must be either true or false.");
        }

        return enabled;
    }

    private bool HasValidExplicitProductionSetting()
    {
        if (_configuration is not IConfigurationRoot configurationRoot)
        {
            return false;
        }

        foreach (var provider in configurationRoot.Providers.Reverse())
        {
            if (!provider.TryGet("Seeding:Enabled", out var providerValue))
            {
                continue;
            }

            // appsettings.json supplies the safe false default. Production must
            // choose through a higher-priority deployment-specific provider.
            var isBaseAppSettings = provider is JsonConfigurationProvider jsonProvider &&
                                    string.Equals(
                                        Path.GetFileName(jsonProvider.Source.Path),
                                        "appsettings.json",
                                        StringComparison.OrdinalIgnoreCase);
            return !isBaseAppSettings && !string.IsNullOrWhiteSpace(providerValue);
        }

        return false;
    }
}

public interface ISeedDataPathResolver
{
    string Resolve(IHostEnvironment environment);
}

public sealed class SeedDataPathResolver : ISeedDataPathResolver
{
    private readonly string _applicationBaseDirectory;

    public SeedDataPathResolver()
        : this(AppContext.BaseDirectory)
    {
    }

    public SeedDataPathResolver(string applicationBaseDirectory)
    {
        _applicationBaseDirectory = applicationBaseDirectory;
    }

    public string Resolve(IHostEnvironment environment)
    {
        var publishedSeedFolder = Path.Combine(_applicationBaseDirectory, "SeedData");
        // Source-tree fallback is a local-development convenience only. A
        // production image with a missing copied dataset must warn, not escape
        // the published application directory.
        if (Directory.Exists(publishedSeedFolder) || !environment.IsDevelopment())
        {
            return publishedSeedFolder;
        }

        return Path.GetFullPath(Path.Combine(
            environment.ContentRootPath,
            "..",
            "CaloriesTracking.Infrastructure",
            "Data",
            "SeedData"));
    }
}
