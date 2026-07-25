using CaloriesTracking.Api.Configuration;
using CaloriesTracking.Infrastructure;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using System.Text;

namespace CaloriesTracking.Api.Tests;

public sealed class ProductionConfigurationValidatorTests
{
    [Fact]
    public void Validate_WhenEnvironmentIsDevelopment_DoesNotRequireProductionValues()
    {
        var configuration = BuildConfiguration([]);

        ProductionConfigurationValidator.Validate(configuration, Environments.Development);
    }

    [Fact]
    public void Validate_WhenProductionConfigurationIsValid_DoesNotThrow()
    {
        var configuration = BuildValidProductionConfiguration();

        ProductionConfigurationValidator.Validate(configuration, Environments.Production);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Data Source=calories.db")]
    public void Validate_WhenProductionDatabaseIsMissingOrNotPostgres_Throws(string? connectionString)
    {
        var configuration = BuildValidProductionConfiguration(
            ("ConnectionStrings:DefaultConnection", connectionString));

        var exception = Assert.Throws<InvalidOperationException>(
            () => ProductionConfigurationValidator.Validate(configuration, Environments.Production));

        Assert.Contains("PostgreSQL", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("short")]
    public void Validate_WhenProductionJwtKeyIsMissingOrShort_Throws(string? jwtKey)
    {
        var configuration = BuildValidProductionConfiguration(("Jwt:Key", jwtKey));

        var exception = Assert.Throws<InvalidOperationException>(
            () => ProductionConfigurationValidator.Validate(configuration, Environments.Production));

        Assert.Contains("Jwt:Key", exception.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("dev_jwt_secret_key_must_be_at_least_32_bytes_long_1234567890")]
    [InlineData("test_jwt_secret_key_must_be_at_least_32_bytes!")]
    [InlineData("YOUR_RANDOM_DEVELOPMENT_KEY_AT_LEAST_32_CHARACTERS")]
    [InlineData("12345678901234567890123456789012")]
    public void Validate_WhenProductionJwtKeyIsKnownPlaceholder_Throws(string jwtKey)
    {
        var configuration = BuildValidProductionConfiguration(("Jwt:Key", jwtKey));

        var exception = Assert.Throws<InvalidOperationException>(
            () => ProductionConfigurationValidator.Validate(configuration, Environments.Production));

    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Validate_WhenProductionGeminiKeyIsMissing_Throws(string? geminiKey)
    {
        var configuration = BuildValidProductionConfiguration(("Gemini:ApiKey", geminiKey));

        var exception = Assert.Throws<InvalidOperationException>(
            () => ProductionConfigurationValidator.Validate(configuration, Environments.Production));

        Assert.Contains("Gemini:ApiKey", exception.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("*")]
    [InlineData("http://calories.example.com")]
    [InlineData("https://localhost")]
    [InlineData("https://127.0.0.1")]
    [InlineData("https://[::1]")]
    [InlineData("https://example.github.io/")]
    public void Validate_WhenProductionCorsOriginIsUnsafe_Throws(string? origin)
    {
        var configuration = BuildValidProductionConfiguration(("Cors:AllowedOrigins:0", origin));

        var exception = Assert.Throws<InvalidOperationException>(
            () => ProductionConfigurationValidator.Validate(configuration, Environments.Production));

        Assert.Contains("CORS", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    private static IConfiguration BuildValidProductionConfiguration(
        params (string Key, string? Value)[] overrides)
    {
        var values = new Dictionary<string, string?>
        {
            ["ConnectionStrings:DefaultConnection"] =
                "postgresql://cal_user:test@ep-example.neon.tech/calories?sslmode=require&channel_binding=require",
            ["Jwt:Key"] = "0123456789abcdef0123456789abcdef",
            ["Gemini:ApiKey"] = "test-gemini-key",
            ["Cors:AllowedOrigins:0"] = "https://example.github.io"
        };

        foreach (var (key, value) in overrides)
        {
            values[key] = value;
        }

        return BuildConfiguration(values);
    }

    private static IConfiguration BuildConfiguration(
        IEnumerable<KeyValuePair<string, string?>> values) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(values)
            .Build();
}

public sealed class InfrastructureDependencyInjectionTests
{
    [Fact]
    public void AddInfrastructure_WhenDevelopment_RegistersSqliteApplicationDbContext()
    {
        var services = new ServiceCollection();

        services.AddInfrastructure(
            BuildConfiguration("Data Source=:memory:"),
            "Development");

        using var provider = services.BuildServiceProvider();
        using var scope = provider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        Assert.IsType<ApplicationDbContext>(context);
        Assert.Equal("Microsoft.EntityFrameworkCore.Sqlite", context.Database.ProviderName);
    }

    [Fact]
    public void AddInfrastructure_WhenProduction_RegistersPostgreSqlApplicationDbContext()
    {
        var services = new ServiceCollection();

        services.AddInfrastructure(
            BuildConfiguration("postgresql://cal_user:test@ep-example.neon.tech/calories?sslmode=require&channel_binding=require"),
            "Production");

        using var provider = services.BuildServiceProvider();
        using var scope = provider.CreateScope();
        var applicationContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var postgresContext = scope.ServiceProvider.GetRequiredService<PostgresApplicationDbContext>();

        Assert.Same(postgresContext, applicationContext);
        Assert.Equal("Npgsql.EntityFrameworkCore.PostgreSQL", applicationContext.Database.ProviderName);
    }

    [Theory]
    [InlineData("Staging")]
    [InlineData("Test")]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("Prodution")]
    public void AddInfrastructure_WhenEnvironmentIsNotSupported_Throws(string? environmentName)
    {
        var services = new ServiceCollection();

        var exception = Assert.Throws<InvalidOperationException>(
            () => services.AddInfrastructure(
                BuildConfiguration("Data Source=:memory:"),
                environmentName));

        Assert.Contains(string.IsNullOrEmpty(environmentName) ? "environment" : environmentName, exception.Message,
            StringComparison.OrdinalIgnoreCase);
    }

    private static IConfiguration BuildConfiguration(string connectionString)
    {
        return new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = connectionString
            })
            .Build();
    }
}

public sealed class HealthEndpointTests
{
    [Fact]
    public async Task Liveness_Returns200WithoutDatabase()
    {
        var result = HealthEndpoints.Liveness();
        var response = await ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status200OK, response.StatusCode);
        Assert.Contains("\"status\":\"ok\"", response.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Readiness_WhenDatabaseCanConnect_Returns200()
    {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        await using var context = CreateSqliteContext(connection);

        var result = await HealthEndpoints.ReadinessAsync(context, CancellationToken.None);
        var response = await ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status200OK, response.StatusCode);
        Assert.Contains("\"status\":\"ok\"", response.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Readiness_WhenDatabaseCannotConnect_Returns503WithoutSensitiveDetails()
    {
        var connectionString = $"Data Source={Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "missing", "calories.db")}";
        await using var context = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseSqlite(connectionString)
            .Options
            .CreateContext();

        var result = await HealthEndpoints.ReadinessAsync(context, CancellationToken.None);
        var response = await ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status503ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain(connectionString, response.Body, StringComparison.Ordinal);
        Assert.DoesNotContain("Exception", response.Body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SQLite", response.Body, StringComparison.OrdinalIgnoreCase);
    }

    private static ApplicationDbContext CreateSqliteContext(SqliteConnection connection) =>
        new(new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseSqlite(connection)
            .Options);

    private static async Task<(int StatusCode, string Body)> ExecuteAsync(IResult result)
    {
        var httpContext = new DefaultHttpContext();
        using var services = new ServiceCollection()
            .AddLogging()
            .AddOptions()
            .AddRouting()
            .BuildServiceProvider();
        httpContext.RequestServices = services;
        await using var responseBody = new MemoryStream();
        httpContext.Response.Body = responseBody;

        await result.ExecuteAsync(httpContext);
        responseBody.Position = 0;
        using var reader = new StreamReader(responseBody, Encoding.UTF8);

        return (httpContext.Response.StatusCode, await reader.ReadToEndAsync());
    }
}

internal static class DbContextOptionsExtensions
{
    public static ApplicationDbContext CreateContext(this DbContextOptions<ApplicationDbContext> options) =>
        new(options);
}
