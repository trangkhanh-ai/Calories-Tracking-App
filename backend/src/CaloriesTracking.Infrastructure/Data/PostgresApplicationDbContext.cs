using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Infrastructure.Data;

public sealed class PostgresApplicationDbContext : ApplicationDbContext
{
    public PostgresApplicationDbContext(DbContextOptions<PostgresApplicationDbContext> options)
        : base(options)
    {
    }
}
