using System.Security.Claims;
using CaloriesTracking.Api.Controllers;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Diary;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Tests;

public sealed class DiaryControllerTests
{
    [Fact]
    public async Task LogMeal_WhenQuantityIsZero_ReturnsBadRequestWithoutCallingService()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: 0m);

        var actionResult = await controller.LogMeal(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(actionResult);
        Assert.Equal(StatusCodes.Status400BadRequest, badRequest.StatusCode);
        Assert.Equal("Quantity must be greater than zero.", GetMessage(badRequest.Value));
        Assert.Equal(0, diaryService.LogMealCallCount);
    }

    [Fact]
    public async Task LogMeal_WhenQuantityIsNegative_ReturnsBadRequestWithoutCallingService()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: -0.5m);

        var actionResult = await controller.LogMeal(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(actionResult);
        Assert.Equal(StatusCodes.Status400BadRequest, badRequest.StatusCode);
        Assert.Equal("Quantity must be greater than zero.", GetMessage(badRequest.Value));
        Assert.Equal(0, diaryService.LogMealCallCount);
    }

    [Fact]
    public async Task LogMeal_WhenQuantityIsPositive_ReturnsOkAndCallsServiceWithOriginalRequest()
    {
        var diaryService = new FakeDiaryService();
        var controller = CreateController(diaryService);
        var request = CreateRequest(quantity: 125.75m);

        var actionResult = await controller.LogMeal(request, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(actionResult);
        Assert.Equal(StatusCodes.Status200OK, ok.StatusCode);
        Assert.Equal("Meal logged successfully.", GetMessage(ok.Value));
        Assert.Equal(1, diaryService.LogMealCallCount);
        Assert.Equal(42, diaryService.LoggedUserId);
        Assert.Same(request, diaryService.LoggedRequest);
    }

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

    private static string? GetMessage(object? value) =>
        value?.GetType().GetProperty("message")?.GetValue(value) as string;

    private sealed class FakeDiaryService : IDiaryService
    {
        public int LogMealCallCount { get; private set; }
        public int LoggedUserId { get; private set; }
        public LogMealRequest? LoggedRequest { get; private set; }

        public Task<DailyDiaryDto> GetDailyDiaryAsync(
            int userId,
            DateTime date,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public Task LogMealAsync(
            int userId,
            LogMealRequest request,
            CancellationToken cancellationToken = default)
        {
            LogMealCallCount++;
            LoggedUserId = userId;
            LoggedRequest = request;
            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<DailyStatDto>> GetStatsAsync(
            int userId,
            DateTime startDate,
            DateTime endDate,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }
}
