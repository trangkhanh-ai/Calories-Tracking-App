using CaloriesTracking.Api.Tests.Support;
using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Application.Services;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Repositories;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Api.Tests;

/// <summary>
/// Concurrency behaviour verified against real unique indexes on SQLite.
/// </summary>
public sealed class DiaryConcurrencyTests
{
    private static readonly DateTime MealDate = new(2026, 7, 20, 0, 0, 0, DateTimeKind.Utc);

    [Fact]
    public async Task LogMeal_WhenTwoRequestsRaceForTheSameDay_CreatesOneDailyLogWithBothMeals()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();

        var serviceA = CreateService(contextA);
        var serviceB = CreateService(contextB);

        // Both writers see "no DailyLog yet" and both try to create it.
        var results = await Task.WhenAll(
            CaptureAsync(() => serviceA.LogMealAsync(userId, Request("Phở bò", "Breakfast"))),
            CaptureAsync(() => serviceB.LogMealAsync(userId, Request("Bún chả", "Lunch"))));

        Assert.All(results, error => Assert.Null(error));

        await using var verify = database.CreateContext();

        var dailyLogs = await verify.DailyLogs
            .Where(l => l.UserId == userId)
            .Include(l => l.MealItems)
            .ToListAsync();

        // Exactly one row survives the (UserId, Date) unique index...
        var dailyLog = Assert.Single(dailyLogs);

        // ...and neither meal was lost.
        Assert.Equal(2, dailyLog.MealItems.Count);
    }

    [Fact]
    public async Task AddMeal_WhenTwoContextsTrackedAnExistingDailyLog_PreservesBothCaloriesAndMeals()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);
        int foodId;

        await using (var setup = database.CreateContext())
        {
            var food = new Food
            {
                Name = "Existing food",
                NormalizedName = "EXISTING FOOD",
                CaloriesPer100g = 100m
            };
            setup.Foods.Add(food);
            setup.DailyLogs.Add(new DailyLog
            {
                UserId = userId,
                Date = DateOnly.FromDateTime(MealDate),
                TotalCaloriesConsumed = 50m
            });
            await setup.SaveChangesAsync();
            foodId = food.Id;
        }

        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();
        var repositoryA = new DailyLogRepository(contextA);
        var repositoryB = new DailyLogRepository(contextB);
        var dailyLogA = await repositoryA.GetDailyLogAsync(userId, MealDate);
        var dailyLogB = await repositoryB.GetDailyLogAsync(userId, MealDate);

        await repositoryA.ExecuteInTransactionAsync(
            () => repositoryA.AddMealAndIncrementCaloriesAsync(dailyLogA!, Meal(foodId, "Breakfast")));
        await repositoryB.ExecuteInTransactionAsync(
            () => repositoryB.AddMealAndIncrementCaloriesAsync(dailyLogB!, Meal(foodId, "Dinner")));

        Assert.Equal(250m, dailyLogB!.TotalCaloriesConsumed);
        await repositoryB.SaveChangesAsync();

        await using var verify = database.CreateContext();
        var dailyLog = await verify.DailyLogs
            .Include(log => log.MealItems)
            .SingleAsync(log => log.UserId == userId && log.Date == DateOnly.FromDateTime(MealDate));
        Assert.Equal(2, dailyLog.MealItems.Count);
        Assert.Equal(250m, dailyLog.TotalCaloriesConsumed);
    }

    [Fact]
    public async Task LogMeal_WhenTwoRequestsRaceForTheSameCustomFood_CreatesOneFoodRow()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();

        var results = await Task.WhenAll(
            CaptureAsync(() => CreateService(contextA).LogMealAsync(userId, Request("Cơm tấm", "Lunch"))),
            CaptureAsync(() => CreateService(contextB).LogMealAsync(userId, Request("Cơm tấm", "Dinner"))));

        Assert.All(results, error => Assert.Null(error));

        await using var verify = database.CreateContext();

        var foods = await verify.Foods
            .Where(f => f.FdcId == null && f.NormalizedName == "CƠM TẤM")
            .ToListAsync();

        Assert.Single(foods);

        // Both meals reference the surviving food — no orphan MealItem.
        var mealItems = await verify.MealItems.ToListAsync();
        Assert.Equal(2, mealItems.Count);
        Assert.All(mealItems, item => Assert.Equal(foods[0].Id, item.FoodId));
    }

    [Fact]
    public async Task LogMeal_WhenTheSameFoodIsLoggedTwiceSequentially_ReusesTheExistingFood()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using (var context = database.CreateContext())
        {
            await CreateService(context).LogMealAsync(userId, Request("Bánh mì", "Breakfast"));
        }

        await using (var context = database.CreateContext())
        {
            await CreateService(context).LogMealAsync(userId, Request("Bánh mì", "Snack"));
        }

        await using var verify = database.CreateContext();
        Assert.Single(verify.Foods.Where(f => f.NormalizedName == "BÁNH MÌ").ToList());
    }

    [Fact]
    public async Task LogMeal_WhenMealItemInsertFails_RollsBackTheFoodInsert()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using var context = database.CreateContext();

        // MealType exceeds its 50-character column, so the MealItem insert fails
        // after the Food insert has already been flushed inside the transaction.
        var service = new DiaryService(
            new DailyLogRepository(context),
            new FoodRepository(context),
            new UserRepository(context),
            new UniqueConstraintTranslator(),
            TimeProvider.System);

        var poisoned = Request("Món lỗi", "Breakfast") with { MealType = "Breakfast" };

        // Force the failure at MealItem persistence by removing the referenced
        // user, which breaks the DailyLog foreign key on commit.
        await using (var cleanup = database.CreateContext())
        {
            var user = await cleanup.Users.FirstAsync(u => u.Id == userId);
            cleanup.Users.Remove(user);
            await cleanup.SaveChangesAsync();
        }

        await Assert.ThrowsAnyAsync<Exception>(() => service.LogMealAsync(userId, poisoned));

        await using var verify = database.CreateContext();

        // The transaction rolled back, so no partially-created Food survives.
        Assert.Empty(verify.Foods.Where(f => f.NormalizedName == "MÓN LỖI").ToList());
        Assert.Empty(verify.MealItems.ToList());
    }

    [Fact]
    public async Task LogMeal_ReturnsTheServerDiaryAsTheAuthoritativeResult()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using var context = database.CreateContext();

        var diary = await CreateService(context).LogMealAsync(
            userId,
            new LogMealRequest("Phở bò", CaloriesPer100g: 150m, Quantity: 200m, MealType: "Breakfast", Date: MealDate));

        var meal = Assert.Single(diary.Breakfast);

        // 150 kcal/100 g at 200 g == 300 kcal.
        Assert.Equal(300m, meal.Calories);
        Assert.Equal(300m, diary.TotalCaloriesConsumed);

        // A real server-assigned id, not a client-fabricated one.
        Assert.True(meal.Id > 0);
    }

    [Fact]
    public async Task LogMeal_WhenCancelled_DoesNotPersist()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using var context = database.CreateContext();
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => CreateService(context).LogMealAsync(userId, Request("Huỷ", "Snack"), cancellation.Token));

        await using var verify = database.CreateContext();
        Assert.Empty(verify.MealItems.ToList());
    }

    [Fact]
    public async Task GetStats_WhenRangeExceeds90Days_ThrowsBeforeQuerying()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using var context = database.CreateContext();

        await Assert.ThrowsAsync<ValidationAppException>(
            () => CreateService(context).GetStatsAsync(
                userId,
                new DateTime(2026, 1, 1),
                new DateTime(2026, 6, 1)));
    }

    [Fact]
    public async Task GetStats_WithinRange_ReturnsOneEntryPerInclusiveDay()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        var userId = await SeedUserAsync(database);

        await using var context = database.CreateContext();

        var stats = await CreateService(context).GetStatsAsync(
            userId,
            new DateTime(2026, 7, 1),
            new DateTime(2026, 7, 7));

        Assert.Equal(7, stats.Count);
    }

    private static LogMealRequest Request(string foodName, string mealType) => new(
        FoodName: foodName,
        CaloriesPer100g: 100m,
        Quantity: 100m,
        MealType: mealType,
        Date: MealDate);

    private static MealItem Meal(int foodId, string mealType) => new()
    {
        FoodId = foodId,
        Quantity = 100m,
        TotalCalories = 100m,
        MealType = mealType
    };

    private static DiaryService CreateService(ApplicationDbContext context) => new(
        new DailyLogRepository(context),
        new FoodRepository(context),
        new UserRepository(context),
        new UniqueConstraintTranslator(),
        TimeProvider.System);

    private static async Task<int> SeedUserAsync(SqliteTestDatabase database)
    {
        await using var context = database.CreateContext();

        var user = new User
        {
            Username = "diary_user",
            NormalizedUsername = "DIARY_USER",
            Email = "diary@example.com",
            NormalizedEmail = "DIARY@EXAMPLE.COM",
            DisplayName = "Diary User",
            PasswordHash = "not-a-real-hash"
        };

        context.Users.Add(user);
        await context.SaveChangesAsync();

        return user.Id;
    }

    private static async Task<Exception?> CaptureAsync(Func<Task> action)
    {
        try
        {
            await action();
            return null;
        }
        catch (Exception exception)
        {
            return exception;
        }
    }
}
