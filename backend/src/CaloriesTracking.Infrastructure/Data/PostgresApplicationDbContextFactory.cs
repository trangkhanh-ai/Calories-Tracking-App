using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace CaloriesTracking.Infrastructure.Data;

public sealed class ApplicationDbContextFactory
    : IDesignTimeDbContextFactory<ApplicationDbContext>
{
    public ApplicationDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseSqlite(
                "Data Source=calories-tracking-development.db",
                sqlite => sqlite.MigrationsAssembly(typeof(ApplicationDbContext).Assembly.GetName().Name))
            .Options;

        return new ApplicationDbContext(options);
    }
}

public sealed class PostgresApplicationDbContextFactory
    : IDesignTimeDbContextFactory<PostgresApplicationDbContext>
{
    public PostgresApplicationDbContext CreateDbContext(string[] args)
    {
        var configuredConnectionString =
            Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection");
        var connectionString = configuredConnectionString is null
            ? "Host=example.invalid;Database=calories_tracking;Username=migration;Password=<DESIGN_TIME_PLACEHOLDER>"
            : NeonConnectionStringNormalizer.Normalize(configuredConnectionString);

        var options = new DbContextOptionsBuilder<PostgresApplicationDbContext>()
            .UseNpgsql(
                connectionString,
                npgsql => npgsql.MigrationsAssembly(typeof(PostgresApplicationDbContext).Assembly.GetName().Name))
            .Options;

        return new PostgresApplicationDbContext(options);
    }
}
