using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Repositories;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;
using Polly;

namespace CaloriesTracking.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        string? environmentName)
    {
        if (string.Equals(environmentName, "Production", StringComparison.OrdinalIgnoreCase))
        {
            var connectionString = NeonConnectionStringNormalizer.Normalize(
                configuration.GetConnectionString("DefaultConnection"));

            services.AddDbContext<PostgresApplicationDbContext>(options =>
                options.UseNpgsql(
                    connectionString,
                    npgsql => npgsql.MigrationsAssembly(
                        typeof(PostgresApplicationDbContext).Assembly.GetName().Name)));

            services.AddScoped<ApplicationDbContext>(serviceProvider =>
                serviceProvider.GetRequiredService<PostgresApplicationDbContext>());
        }
        else if (string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase))
        {
            services.AddDbContext<ApplicationDbContext>(options =>
            {
                var connectionString = configuration.GetConnectionString("DefaultConnection")
                    ?? "Data Source=calories.db";

                options.UseSqlite(
                    connectionString,
                    sqlite => sqlite.MigrationsAssembly(
                        typeof(ApplicationDbContext).Assembly.GetName().Name));
            });
        }
        else
        {
            var displayName = string.IsNullOrWhiteSpace(environmentName)
                ? "<empty>"
                : environmentName;

            throw new InvalidOperationException(
                $"The hosting environment '{displayName}' is not supported. " +
                "Only Development (SQLite) and Production (PostgreSQL) are allowed.");
        }

        services.AddScoped<IUserRepository, UserRepository>();
        services.AddScoped<IFoodRepository, FoodRepository>();
        services.AddScoped<IDailyLogRepository, DailyLogRepository>();
        services.AddScoped<IAvatarStorageService, FakeAvatarStorageService>();

        services.AddGeminiClient();

        return services;
    }

    public static IHttpClientBuilder AddGeminiClient(
        this IServiceCollection services,
        TimeSpan? retryDelay = null,
        TimeSpan? timeout = null)
    {
        var delay = retryDelay ?? TimeSpan.FromSeconds(1);
        var timeoutDuration = timeout ?? TimeSpan.FromSeconds(30);

        var builder = services.AddHttpClient<IFoodAnalysisService, GeminiFoodAnalysisService>();
        
        builder.AddResilienceHandler("gemini-retry", resBuilder =>
        {
            resBuilder.AddRetry(new HttpRetryStrategyOptions
            {
                MaxRetryAttempts = 2,
                BackoffType = DelayBackoffType.Exponential,
                Delay = delay,
                UseJitter = delay > TimeSpan.FromMilliseconds(100),
                ShouldHandle = args =>
                {
                    if (args.Outcome.Exception is GeminiUnavailableException || args.Outcome.Exception is HttpRequestException)
                        return new ValueTask<bool>(true);

                    if (args.Outcome.Result is HttpResponseMessage response)
                    {
                        var status = (int)response.StatusCode;
                        if (status == 429 || status == 502 || status == 503 || status == 504)
                            return new ValueTask<bool>(true);
                    }

                    return new ValueTask<bool>(false);
                }
            });
            resBuilder.AddTimeout(timeoutDuration);
        });

        return builder;
    }
}
