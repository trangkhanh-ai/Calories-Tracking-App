using CaloriesTracking.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Infrastructure.Data;

public sealed class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();

    public DbSet<Food> Foods => Set<Food>();

    public DbSet<DailyLog> DailyLogs => Set<DailyLog>();

    public DbSet<MealItem> MealItems => Set<MealItem>();

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

            entity.HasIndex(x => x.Username).IsUnique();
            entity.HasIndex(x => x.Email).IsUnique();
        });

        modelBuilder.Entity<Food>(entity =>
        {
            entity.ToTable("Foods");

            entity.HasKey(x => x.Id);

            entity.Property(x => x.Name)
                .IsRequired()
                .HasMaxLength(200);

            entity.Property(x => x.CaloriesPer100g)
                .HasPrecision(10, 2);

            entity.Property(x => x.Protein)
                .HasPrecision(10, 2);

            entity.Property(x => x.Carbs)
                .HasPrecision(10, 2);

            entity.Property(x => x.Fat)
                .HasPrecision(10, 2);
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
    }
}
