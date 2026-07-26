using System.Text;
using System.Net.Http.Json;
using CaloriesTracking.Api.Controllers;
using CaloriesTracking.Api.Middleware;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Auth;
using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Application.Services;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Repositories;
using CaloriesTracking.Postgres.Tests.Support;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Npgsql;

namespace CaloriesTracking.Postgres.Tests;

public sealed class PostgresRuntimeTests
{
    private const string JwtKey = "postgres_runtime_test_signing_key_long_enough_123456";
    private static readonly DateTime MealDate = new(2026, 7, 26, 0, 0, 0, DateTimeKind.Utc);

    [PostgresFact]
    public async Task Register_WhenUsernameDiffersOnlyByCase_ReturnsConflict()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using (var context = database.CreateContext())
        {
            await context.Database.MigrateAsync();
            await CreateAuthService(context).RegisterAsync(Request("DuyNguyen", "duy@example.com"));
        }

        await using var conflictContext = database.CreateContext();
        var conflict = await Assert.ThrowsAsync<ConflictAppException>(
            () => CreateAuthService(conflictContext).RegisterAsync(Request("dUYnGUYEN", "other@example.com")));

        Assert.Equal(StatusCodes.Status409Conflict, await ToStatusCodeAsync(conflict));
        Assert.Equal("Username is already taken.", conflict.Message);
    }

    [PostgresFact]
    public async Task Register_WhenEmailDiffersOnlyByCase_ReturnsConflict()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using (var context = database.CreateContext())
        {
            await context.Database.MigrateAsync();
            await CreateAuthService(context).RegisterAsync(Request("first", "duy@example.com"));
        }

        await using var conflictContext = database.CreateContext();
        var conflict = await Assert.ThrowsAsync<ConflictAppException>(
            () => CreateAuthService(conflictContext).RegisterAsync(Request("second", "DUY@EXAMPLE.COM")));

        Assert.Equal(StatusCodes.Status409Conflict, await ToStatusCodeAsync(conflict));
        Assert.Equal("Email is already registered.", conflict.Message);
    }

    [PostgresFact]
    public async Task Register_WhenTwoRequestsRaceForTheSameUsername_OneSucceedsAndOneIsTranslatedTo409()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using (var setup = database.CreateContext())
        {
            await setup.Database.MigrateAsync();
        }

        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();
        using var barrier = new Barrier(2);
        var serviceA = CreateAuthService(new BarrierUserRepository(new UserRepository(contextA), barrier));
        var serviceB = CreateAuthService(new BarrierUserRepository(new UserRepository(contextB), barrier));

        var results = await Task.WhenAll(
            CaptureResultAsync(() => serviceA.RegisterAsync(Request("racer", "one@example.com"))),
            CaptureResultAsync(() => serviceB.RegisterAsync(Request("RACER", "two@example.com"))));

        Assert.Equal(1, results.Count(result => result is AuthResponse));
        var conflict = Assert.IsType<ConflictAppException>(results.Single(result => result is ConflictAppException));
        Assert.Equal(StatusCodes.Status409Conflict, await ToStatusCodeAsync(conflict));
        Assert.DoesNotContain("Postgres", conflict.Message, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("IX_", conflict.Message, StringComparison.OrdinalIgnoreCase);

        await using var verify = database.CreateContext();
        Assert.Single(await verify.Users.Where(u => u.NormalizedUsername == "RACER").ToListAsync());
    }

    [PostgresFact]
    public async Task RegisterHttp_WhenTwoRequestsRaceForTheSameUsername_ReturnsOneSuccessAndOne409()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using var factory = new ProductionApiFactory(database.ConnectionString);
        using var client = factory.CreateClient();

        var responses = await Task.WhenAll(
            client.PostAsJsonAsync(
                "/api/auth/register",
                Request("http-racer", "http-one@example.com")),
            client.PostAsJsonAsync(
                "/api/auth/register",
                Request("HTTP-RACER", "http-two@example.com")));

        Assert.Equal(1, responses.Count(response => response.StatusCode == System.Net.HttpStatusCode.OK));
        var conflict = Assert.Single(
            responses,
            response => response.StatusCode == System.Net.HttpStatusCode.Conflict);
        var conflictBody = await conflict.Content.ReadAsStringAsync();
        Assert.DoesNotContain("Postgres", conflictBody, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("IX_", conflictBody, StringComparison.OrdinalIgnoreCase);
    }

    [PostgresFact]
    public async Task LogMeal_WhenTwoRequestsRaceToCreateANewDailyLog_PreservesBothMeals()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        int userId;
        await using (var setup = database.CreateContext())
        {
            await setup.Database.MigrateAsync();
            userId = await AddUserAsync(setup, "new-daily-user");
            await AddFoodAsync(setup, 7101, "Breakfast food");
            await AddFoodAsync(setup, 7102, "Lunch food");
        }

        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();
        using var barrier = new Barrier(2);
        var serviceA = CreateDiaryService(
            contextA,
            dailyLogs: new BarrierDailyLogRepository(new DailyLogRepository(contextA), barrier, expectExisting: false));
        var serviceB = CreateDiaryService(
            contextB,
            dailyLogs: new BarrierDailyLogRepository(new DailyLogRepository(contextB), barrier, expectExisting: false));

        var results = await Task.WhenAll(
            CaptureAsync(() => serviceA.LogMealAsync(userId, Meal("Breakfast food", "Breakfast"))),
            CaptureAsync(() => serviceB.LogMealAsync(userId, Meal("Lunch food", "Lunch"))));

        Assert.All(results, result => Assert.Null(result));

        await using var verify = database.CreateContext();
        var dailyLog = await verify.DailyLogs
            .Include(log => log.MealItems)
            .SingleAsync(log => log.UserId == userId && log.Date == DateOnly.FromDateTime(MealDate));
        Assert.Equal(2, dailyLog.MealItems.Count);
        Assert.Equal(200m, dailyLog.TotalCaloriesConsumed);
    }

    [PostgresFact]
    public async Task LogMeal_WhenTwoRequestsRaceOnAnExistingDailyLog_PreservesBothMeals()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        int userId;
        await using (var setup = database.CreateContext())
        {
            await setup.Database.MigrateAsync();
            userId = await AddUserAsync(setup, "existing-daily-user");
            await AddFoodAsync(setup, 7201, "Existing breakfast");
            setup.DailyLogs.Add(new DailyLog
            {
                UserId = userId,
                Date = DateOnly.FromDateTime(MealDate),
                TotalCaloriesConsumed = 0
            });
            await setup.SaveChangesAsync();
        }

        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();
        using var barrier = new Barrier(2);
        var serviceA = CreateDiaryService(
            contextA,
            dailyLogs: new BarrierDailyLogRepository(new DailyLogRepository(contextA), barrier, expectExisting: true));
        var serviceB = CreateDiaryService(
            contextB,
            dailyLogs: new BarrierDailyLogRepository(new DailyLogRepository(contextB), barrier, expectExisting: true));

        var results = await Task.WhenAll(
            CaptureAsync(() => serviceA.LogMealAsync(userId, Meal("Existing breakfast", "Breakfast"))),
            CaptureAsync(() => serviceB.LogMealAsync(userId, Meal("Existing breakfast", "Dinner"))));

        Assert.All(results, result => Assert.Null(result));

        await using var verify = database.CreateContext();
        var dailyLog = await verify.DailyLogs
            .Include(log => log.MealItems)
            .SingleAsync(log => log.UserId == userId && log.Date == DateOnly.FromDateTime(MealDate));
        Assert.Equal(2, dailyLog.MealItems.Count);
        Assert.Equal(200m, dailyLog.TotalCaloriesConsumed);
    }

    [PostgresFact]
    public async Task LogMeal_WhenTwoRequestsRaceOnCustomFood_CreatesOneFoodAndTwoMealItems()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        int firstUserId;
        int secondUserId;
        await using (var setup = database.CreateContext())
        {
            await setup.Database.MigrateAsync();
            firstUserId = await AddUserAsync(setup, "custom-food-one");
            secondUserId = await AddUserAsync(setup, "custom-food-two");
        }

        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();
        using var barrier = new Barrier(2);
        var serviceA = CreateDiaryService(
            contextA,
            foods: new BarrierFoodRepository(new FoodRepository(contextA), barrier));
        var serviceB = CreateDiaryService(
            contextB,
            foods: new BarrierFoodRepository(new FoodRepository(contextB), barrier));

        var results = await Task.WhenAll(
            CaptureAsync(() => serviceA.LogMealAsync(firstUserId, Meal("Cơm tấm nhà", "Lunch"))),
            CaptureAsync(() => serviceB.LogMealAsync(secondUserId, Meal("CƠM TẤM NHÀ", "Dinner"))));

        Assert.All(results, result => Assert.Null(result));

        await using var verify = database.CreateContext();
        var foods = await verify.Foods.Where(food => food.FdcId == null).ToListAsync();
        Assert.Single(foods);
        Assert.Equal("CƠM TẤM NHÀ", foods[0].NormalizedName);
        Assert.Equal(2, await verify.MealItems.CountAsync());
    }

    [PostgresFact]
    public async Task FoodSearch_MatchesVietnameseTextAndEscapesLikeWildcards()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using var context = database.CreateContext();
        await context.Database.MigrateAsync();
        await AddFoodAsync(context, 7301, "Bún bò Huế");
        await AddFoodAsync(context, 7302, "BÚN CHẢ");
        await AddFoodAsync(context, 7303, "Sauce 100%");
        await AddFoodAsync(context, 7304, "A_B snack");
        await context.SaveChangesAsync();

        var controller = new FoodController(context);
        var vietnamese = await SearchAsync(controller, "bún");
        Assert.Equal(2, vietnamese.Count);
        Assert.Contains(vietnamese, food => food.Name == "Bún bò Huế");
        Assert.Contains(vietnamese, food => food.Name == "BÚN CHẢ");

        var percent = await SearchAsync(controller, "%");
        Assert.Equal(new[] { "Sauce 100%" }, percent.Select(food => food.Name));

        var underscore = await SearchAsync(controller, "_");
        Assert.Equal(new[] { "A_B snack" }, underscore.Select(food => food.Name));
    }

    [PostgresFact]
    public async Task UniqueConstraintTranslator_RecognizesRealPostgres23505()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using var context = database.CreateContext();
        await context.Database.MigrateAsync();
        await AddUserAsync(context, "translator-user");
        await context.SaveChangesAsync();

        await using var duplicate = database.CreateContext();
        duplicate.Users.Add(new User
        {
            Username = "TRANSLATOR-USER",
            NormalizedUsername = "TRANSLATOR-USER",
            Email = "different@example.com",
            NormalizedEmail = "DIFFERENT@EXAMPLE.COM",
            PasswordHash = "hash",
            DisplayName = "Duplicate"
        });

        var exception = await Assert.ThrowsAsync<DbUpdateException>(() => duplicate.SaveChangesAsync());
        var postgres = FindPostgresException(exception);
        Assert.NotNull(postgres);
        Assert.Equal("23505", postgres!.SqlState);
        Assert.True(new UniqueConstraintTranslator().IsUniqueViolation(exception));
    }

    [PostgresFact]
    public async Task UniqueConstraintTranslator_DoesNotTranslateForeignKeyViolation()
    {
        await using var database = await PostgresTestDatabase.CreateAsync();
        await using var context = database.CreateContext();
        await context.Database.MigrateAsync();
        context.DailyLogs.Add(new DailyLog
        {
            UserId = int.MaxValue,
            Date = DateOnly.FromDateTime(MealDate),
            TotalCaloriesConsumed = 0
        });

        var exception = await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync());
        var postgres = FindPostgresException(exception);
        Assert.NotNull(postgres);
        Assert.Equal("23503", postgres!.SqlState);
        Assert.False(new UniqueConstraintTranslator().IsUniqueViolation(exception));
    }

    private static RegisterRequest Request(string username, string email) => new()
    {
        Username = username,
        Email = email,
        Password = "Password123!",
        DisplayName = "Runtime User"
    };

    private static LogMealRequest Meal(string foodName, string mealType) => new(
        foodName,
        CaloriesPer100g: 100,
        Quantity: 100,
        mealType,
        MealDate);

    private static AuthService CreateAuthService(ApplicationDbContext context) => CreateAuthService(new UserRepository(context));

    private static AuthService CreateAuthService(IUserRepository users) => new(
        users,
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Key"] = JwtKey,
                ["Jwt:Issuer"] = "CaloriesTracking.Postgres.Tests",
                ["Jwt:Audience"] = "CaloriesTracking.Postgres.Tests"
            })
            .Build(),
        new UniqueConstraintTranslator());

    private static DiaryService CreateDiaryService(
        ApplicationDbContext context,
        IDailyLogRepository? dailyLogs = null,
        IFoodRepository? foods = null) => new(
        dailyLogs ?? new DailyLogRepository(context),
        foods ?? new FoodRepository(context),
        new UserRepository(context),
        new UniqueConstraintTranslator(),
        TimeProvider.System);

    private static async Task<int> AddUserAsync(ApplicationDbContext context, string username)
    {
        var user = new User
        {
            Username = username,
            NormalizedUsername = username.ToUpperInvariant(),
            Email = $"{username}@example.com",
            NormalizedEmail = $"{username}@EXAMPLE.COM".ToUpperInvariant(),
            PasswordHash = "hash",
            DisplayName = username
        };
        context.Users.Add(user);
        await context.SaveChangesAsync();
        return user.Id;
    }

    private static async Task AddFoodAsync(ApplicationDbContext context, int fdcId, string name)
    {
        context.Foods.Add(new Food
        {
            FdcId = fdcId,
            Name = name,
            NormalizedName = name.ToUpperInvariant(),
            SourceType = "USDA",
            CaloriesPer100g = 100,
            Protein = 1,
            Carbs = 2,
            Fat = 3
        });
        await context.SaveChangesAsync();
    }

    private static async Task<IReadOnlyList<FoodNutritionDto>> SearchAsync(FoodController controller, string query)
    {
        var result = await controller.SearchFoods(query, limit: 50);
        var ok = Assert.IsType<OkObjectResult>(result);
        return Assert.IsAssignableFrom<IReadOnlyList<FoodNutritionDto>>(ok.Value);
    }

    private static async Task<int> ToStatusCodeAsync(ConflictAppException exception)
    {
        var context = new DefaultHttpContext { TraceIdentifier = "postgres-runtime-test" };
        await using var body = new MemoryStream();
        context.Response.Body = body;
        var environment = new TestHostEnvironment { EnvironmentName = "Production" };
        var handler = new GlobalExceptionHandler(environment, NullLogger<GlobalExceptionHandler>.Instance);
        await handler.TryHandleAsync(context, exception, CancellationToken.None);
        return context.Response.StatusCode;
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

    private static async Task<object> CaptureResultAsync<T>(Func<Task<T>> action)
        where T : notnull
    {
        try
        {
            return await action();
        }
        catch (Exception exception)
        {
            return exception;
        }
    }

    private static PostgresException? FindPostgresException(Exception exception)
    {
        for (var current = exception; current is not null; current = current.InnerException)
        {
            if (current is PostgresException postgres)
            {
                return postgres;
            }
        }

        return null;
    }

    private sealed class BarrierUserRepository(IUserRepository inner, Barrier barrier) : IUserRepository
    {
        private int _waited;

        public Task<User?> GetByIdAsync(int userId, CancellationToken cancellationToken = default) => inner.GetByIdAsync(userId, cancellationToken);
        public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default) => inner.SaveChangesAsync(cancellationToken);
        public Task<User?> GetByUsernameAsync(string username, CancellationToken cancellationToken = default) => inner.GetByUsernameAsync(username, cancellationToken);
        public Task<User?> GetByEmailAsync(string email, CancellationToken cancellationToken = default) => inner.GetByEmailAsync(email, cancellationToken);

        public async Task<User?> GetByNormalizedUsernameAsync(string normalizedUsername, CancellationToken cancellationToken = default) =>
            await inner.GetByNormalizedUsernameAsync(normalizedUsername, cancellationToken);

        public async Task<User?> GetByNormalizedEmailAsync(string normalizedEmail, CancellationToken cancellationToken = default)
        {
            var result = await inner.GetByNormalizedEmailAsync(normalizedEmail, cancellationToken);
            if (result is null && Interlocked.Exchange(ref _waited, 1) == 0)
            {
                barrier.SignalAndWait(TimeSpan.FromSeconds(15));
            }

            return result;
        }

        public Task AddAsync(User user, CancellationToken cancellationToken = default) => inner.AddAsync(user, cancellationToken);
        public void Detach(User user) => inner.Detach(user);
    }

    private sealed class BarrierDailyLogRepository(IDailyLogRepository inner, Barrier barrier, bool expectExisting) : IDailyLogRepository
    {
        private int _waited;

        public async Task<DailyLog?> GetDailyLogAsync(int userId, DateTime date, CancellationToken cancellationToken = default)
        {
            var result = await inner.GetDailyLogAsync(userId, date, cancellationToken);
            if ((result is not null) == expectExisting && Interlocked.Exchange(ref _waited, 1) == 0)
            {
                barrier.SignalAndWait(TimeSpan.FromSeconds(15));
            }

            return result;
        }

        public Task<IReadOnlyList<DailyLog>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default) => inner.GetStatsAsync(userId, startDate, endDate, cancellationToken);
        public void Add(DailyLog dailyLog) => inner.Add(dailyLog);
        public void Detach(DailyLog dailyLog) => inner.Detach(dailyLog);
        public void ClearChangeTracker() => inner.ClearChangeTracker();
        public Task AddMealAndIncrementCaloriesAsync(DailyLog dailyLog, MealItem mealItem, CancellationToken cancellationToken = default) => inner.AddMealAndIncrementCaloriesAsync(dailyLog, mealItem, cancellationToken);
        public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default) => inner.SaveChangesAsync(cancellationToken);
        public Task ExecuteInTransactionAsync(Func<Task> action, CancellationToken cancellationToken = default) => inner.ExecuteInTransactionAsync(action, cancellationToken);
    }

    private sealed class BarrierFoodRepository(IFoodRepository inner, Barrier barrier) : IFoodRepository
    {
        private int _waited;

        public Task<Food?> GetByIdAsync(int id, CancellationToken cancellationToken = default) => inner.GetByIdAsync(id, cancellationToken);

        public Task<Food?> GetByNameAsync(string name, CancellationToken cancellationToken = default) => inner.GetByNameAsync(name, cancellationToken);

        public async Task<Food?> GetCustomByNormalizedNameAsync(string normalizedName, CancellationToken cancellationToken = default)
        {
            var result = await inner.GetCustomByNormalizedNameAsync(normalizedName, cancellationToken);
            if (result is null && Interlocked.Exchange(ref _waited, 1) == 0)
            {
                barrier.SignalAndWait(TimeSpan.FromSeconds(15));
            }

            return result;
        }
        public void Add(Food food) => inner.Add(food);
        public void Detach(Food food) => inner.Detach(food);
    }

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = string.Empty;
        public string ApplicationName { get; set; } = "CaloriesTracking.Postgres.Tests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class ProductionApiFactory(string connectionString) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Production");
            builder.ConfigureAppConfiguration((_, configuration) =>
            {
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["ConnectionStrings:DefaultConnection"] = connectionString,
                    ["Jwt:Key"] = "runtime-integration-signing-key-with-32-plus-bytes",
                    ["Jwt:Issuer"] = "CaloriesTracking.Postgres.Tests",
                    ["Jwt:Audience"] = "CaloriesTracking.Postgres.Tests",
                    ["Gemini:ApiKey"] = "runtime-integration-api-key",
                    ["Cors:AllowedOrigins:0"] = "https://example.com",
                    ["Hosting:BehindTlsTerminatingProxy"] = "true",
                    ["Seeding:Enabled"] = "false",
                    ["RateLimiting:AuthRegisterPermitLimit"] = "1000"
                });
            });
        }
    }
}
