using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Repositories;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

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

        services.AddHttpClient<IFoodAnalysisService, GeminiFoodAnalysisService>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(60);
        });

        return services;
    }
}
