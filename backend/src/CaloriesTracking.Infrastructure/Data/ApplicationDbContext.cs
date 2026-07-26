using CaloriesTracking.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Infrastructure.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions options)
        : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();

    public DbSet<Food> Foods => Set<Food>();

    public DbSet<DailyLog> DailyLogs => Set<DailyLog>();

    public DbSet<MealItem> MealItems => Set<MealItem>();

    public DbSet<SeedHistory> SeedHistories => Set<SeedHistory>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("Users");

            entity.HasKey(x => x.Id);

            entity.Property(x => x.Username)
                .IsRequired()
                .HasMaxLength(100);

            entity.Property(x => x.PasswordHash)
                .IsRequired()
                .HasMaxLength(512);

            entity.Property(x => x.Email)
                .IsRequired()
                .HasMaxLength(254);

            entity.Property(x => x.DisplayName)
                .IsRequired()
                .HasMaxLength(150);

            entity.Property(x => x.AvatarUrl)
                .HasMaxLength(1024);

            entity.Property(x => x.Height)
                .HasPrecision(5, 2);

            entity.Property(x => x.Weight)
                .HasPrecision(5, 2);

            entity.Property(x => x.Gender)
                .HasMaxLength(20);

            entity.Property(x => x.NormalizedUsername)
                .IsRequired()
                .HasMaxLength(100);

            entity.Property(x => x.NormalizedEmail)
                .IsRequired()
                .HasMaxLength(254);

            entity.HasIndex(x => x.Username).IsUnique();
            entity.HasIndex(x => x.Email).IsUnique();

            // The normalized indexes are what actually make uniqueness
            // case-insensitive; the raw-column indexes above stay for the
            // exact-value lookups the response contract still uses.
            entity.HasIndex(x => x.NormalizedUsername)
                .IsUnique()
                .HasDatabaseName("IX_Users_NormalizedUsername");

            entity.HasIndex(x => x.NormalizedEmail)
                .IsUnique()
                .HasDatabaseName("IX_Users_NormalizedEmail");
        });

        modelBuilder.Entity<Food>(entity =>
        {
            entity.ToTable("Foods");

            entity.HasKey(x => x.Id);

            entity.Property(x => x.Name)
                .IsRequired()
                .HasMaxLength(200);

            entity.Property(x => x.SourceType)
                .HasMaxLength(50);

            entity.Property(x => x.CaloriesPer100g)
                .HasPrecision(10, 2);

            entity.Property(x => x.Protein)
                .HasPrecision(10, 2);

            entity.Property(x => x.Carbs)
                .HasPrecision(10, 2);

            entity.Property(x => x.Fat)
                .HasPrecision(10, 2);

            entity.Property(x => x.Sugar)
                .HasPrecision(10, 2);

            entity.Property(x => x.Fiber)
                .HasPrecision(10, 2);

            entity.Property(x => x.Sodium)
                .HasPrecision(10, 2);

            entity.Property(x => x.NormalizedName)
                .IsRequired()
                .HasMaxLength(200);

            // Partial unique indexes. Double-quoted identifiers and the WHERE
            // clause are valid CREATE INDEX syntax on both SQLite (>= 3.8.0)
            // and PostgreSQL, so one definition covers both providers.

            // USDA rows: FdcId identifies the row, but NULL FdcId (custom food)
            // must not collide, hence the filter.
            entity.HasIndex(x => x.FdcId)
                .IsUnique()
                .HasFilter("\"FdcId\" IS NOT NULL")
                .HasDatabaseName("IX_Foods_FdcId");

            // Custom foods: name identity applies only where there is no FdcId,
            // because the USDA dataset legitimately repeats display names.
            entity.HasIndex(x => x.NormalizedName)
                .IsUnique()
                .HasFilter("\"FdcId\" IS NULL")
                .HasDatabaseName("IX_Foods_NormalizedName_Custom");
        });

        modelBuilder.Entity<DailyLog>(entity =>
        {
            entity.ToTable("DailyLogs");

            entity.HasKey(x => x.Id);

            entity.Property(x => x.Date)
                .IsRequired()
                .HasColumnType("date");

            entity.Property(x => x.TotalCaloriesConsumed)
                .HasPrecision(10, 2);

            entity.HasOne(x => x.User)
                .WithMany(x => x.DailyLogs)
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(x => new { x.UserId, x.Date }).IsUnique();
        });

        modelBuilder.Entity<MealItem>(entity =>
        {
            entity.ToTable("MealItems");

            entity.HasKey(x => x.Id);

            entity.Property(x => x.Quantity)
                .HasPrecision(10, 2);

            entity.Property(x => x.TotalCalories)
                .HasPrecision(10, 2);

            entity.Property(x => x.MealType)
                .IsRequired()
                .HasMaxLength(50);

            entity.HasOne(x => x.DailyLog)
                .WithMany(x => x.MealItems)
                .HasForeignKey(x => x.DailyLogId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(x => x.Food)
                .WithMany(x => x.MealItems)
                .HasForeignKey(x => x.FoodId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<SeedHistory>(entity =>
        {
            entity.ToTable("SeedHistories");

            entity.HasKey(x => x.Id);

            entity.Property(x => x.Name)
                .IsRequired()
                .HasMaxLength(100);

            entity.Property(x => x.Version)
                .IsRequired()
                .HasMaxLength(50);

            entity.Property(x => x.Status)
                .IsRequired()
                .HasConversion<int>();

            entity.Property(x => x.ErrorSummary)
                .HasMaxLength(1024);

            entity.Property(x => x.LockOwner)
                .HasMaxLength(100);

            // One row per logical seed version — this is also what makes the
            // "another instance already claimed this seed" insert fail fast.
            entity.HasIndex(x => new { x.Name, x.Version })
                .IsUnique()
                .HasDatabaseName("IX_SeedHistories_Name_Version");
        });
    }
}
