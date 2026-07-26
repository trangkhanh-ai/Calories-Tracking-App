using System.Security.Claims;
using CaloriesTracking.Api.Controllers;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Application.Exceptions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Tests;

/// <summary>
/// Diary validation now throws typed exceptions that the global handler renders
/// as RFC 7807 ProblemDetails, replacing the previous ad-hoc anonymous
/// <c>{ message }</c> results. Each case still asserts the same rejection
/// reason and that the service was never reached.
/// </summary>
public sealed class DiaryControllerTests
{
    [Fact]
    public async Task LogMeal_WhenQuantityIsZero_ThrowsValidationWithoutCallingService()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: 0m);

        var exception = await Assert.ThrowsAsync<ValidationAppException>(
            () => controller.LogMeal(request, CancellationToken.None));

        Assert.Equal("Quantity must be greater than zero.", exception.Message);
        Assert.Equal("quantity", exception.Field);
        Assert.Equal(0, diaryService.LogMealCallCount);
    }

    [Fact]
    public async Task LogMeal_WhenQuantityIsNegative_ThrowsValidationWithoutCallingService()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: -0.5m);

        var exception = await Assert.ThrowsAsync<ValidationAppException>(
            () => controller.LogMeal(request, CancellationToken.None));

        Assert.Equal("Quantity must be greater than zero.", exception.Message);
        Assert.Equal(0, diaryService.LogMealCallCount);
    }

    [Theory]
    [InlineData("Breakfast")]
    [InlineData("Lunch")]
    [InlineData("Dinner")]
    [InlineData("Snack")]
    public async Task LogMeal_WhenMealTypeIsCanonical_ReturnsOkAndCallsService(string mealType)
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: 125.75m) with { MealType = mealType };

        var actionResult = await controller.LogMeal(request, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(actionResult);
        Assert.Equal(StatusCodes.Status200OK, ok.StatusCode);

        var response = Assert.IsType<LogMealResponse>(ok.Value);
        Assert.Equal("Meal logged successfully.", response.Message);

        // The response now also carries the authoritative server diary so the
        // client can adopt it instead of fabricating a local row.
        Assert.NotNull(response.Diary);

        Assert.Equal(1, diaryService.LogMealCallCount);
        Assert.Equal(42, diaryService.LoggedUserId);
        Assert.Same(request, diaryService.LoggedRequest);
    }

    [Theory]
    [MemberData(nameof(InvalidMealTypes))]
    public async Task LogMeal_WhenMealTypeIsNotCanonical_ThrowsValidationWithoutCallingService(
        string mealType)
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: 125.75m) with { MealType = mealType };

        var exception = await Assert.ThrowsAsync<ValidationAppException>(
            () => controller.LogMeal(request, CancellationToken.None));

        Assert.Equal(
            "MealType must be one of: Breakfast, Lunch, Dinner, Snack.",
            exception.Message);
        Assert.Equal(0, diaryService.LogMealCallCount);
        Assert.Null(diaryService.LoggedRequest);
    }

    [Fact]
    public async Task LogMeal_WhenQuantityAndMealTypeAreInvalid_PreservesQuantityValidationPrecedence()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: 0m) with { MealType = "Brunch" };

        var exception = await Assert.ThrowsAsync<ValidationAppException>(
            () => controller.LogMeal(request, CancellationToken.None));

        Assert.Equal("Quantity must be greater than zero.", exception.Message);
        Assert.Equal(0, diaryService.LogMealCallCount);
    }

    [Fact]
    public async Task GetStats_WhenRangeIsReversed_ThrowsValidationWithoutCallingService()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);

        var exception = await Assert.ThrowsAsync<ValidationAppException>(
            () => controller.GetStats(
                new DateTime(2026, 7, 20),
                new DateTime(2026, 7, 10),
                CancellationToken.None));

        Assert.Equal("startDate must be on or before endDate.", exception.Message);
        Assert.Equal(0, diaryService.GetStatsCallCount);
    }

    [Fact]
    public async Task GetStats_WhenDatesAreDefault_ThrowsValidationWithoutCallingService()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);

        // A defaulted DateTime.MinValue start would otherwise drive the day loop
        // in the service for roughly 740,000 iterations.
        await Assert.ThrowsAsync<ValidationAppException>(
            () => controller.GetStats(default, default, CancellationToken.None));

        Assert.Equal(0, diaryService.GetStatsCallCount);
    }

    public static IEnumerable<object[]> InvalidMealTypes() =>
    [
        [""],
        ["   "],
        ["breakfast"],
        ["BREAKFAST"],
        ["BreakFast"],
        [" Breakfast"],
        ["Breakfast "],
        ["Break fast"],
        ["Brunch"],
        [new string('X', 51)],
        ["Breakfаst"]
    ];

    private static DiaryController CreateController(IDiaryService diaryService)
    {
        var identity = new ClaimsIdentity(
            [new Claim(ClaimTypes.NameIdentifier, "42")],
            authenticationType: "Test");

        return new DiaryController(diaryService)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(identity)
                }
            }
        };
    }

    private static LogMealRequest CreateRequest(decimal quantity) => new(
        FoodName: "Brown rice",
        CaloriesPer100g: 123.45m,
        Quantity: quantity,
        MealType: "Lunch",
        Date: new DateTime(2026, 7, 19));

    private sealed class FakeDiaryService : IDiaryService
    {
        public int LogMealCallCount { get; private set; }
        public int GetStatsCallCount { get; private set; }
        public int LoggedUserId { get; private set; }
        public LogMealRequest? LoggedRequest { get; private set; }

        public Task<DailyDiaryDto> GetDailyDiaryAsync(
            int userId,
            DateTime date,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public Task<DailyDiaryDto> LogMealAsync(
            int userId,
            LogMealRequest request,
            CancellationToken cancellationToken = default)
        {
            LogMealCallCount++;
            LoggedUserId = userId;
            LoggedRequest = request;

            return Task.FromResult(new DailyDiaryDto(
                request.Date,
                TotalCaloriesConsumed: 0,
                TargetCalories: 2000,
                Breakfast: Array.Empty<MealItemDto>(),
                Lunch: Array.Empty<MealItemDto>(),
                Dinner: Array.Empty<MealItemDto>(),
                Snacks: Array.Empty<MealItemDto>()));
        }

        public Task<IReadOnlyList<DailyStatDto>> GetStatsAsync(
            int userId,
            DateTime startDate,
            DateTime endDate,
            CancellationToken cancellationToken = default)
        {
            GetStatsCallCount++;
            return Task.FromResult<IReadOnlyList<DailyStatDto>>(Array.Empty<DailyStatDto>());
        }
    }
}
