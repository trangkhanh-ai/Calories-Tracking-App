using System.Security.Claims;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Application.Validation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class DiaryController : ControllerBase
{
    private readonly IDiaryService _diaryService;

    public DiaryController(IDiaryService diaryService)
    {
        _diaryService = diaryService;
    }

    private int GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return int.TryParse(userIdClaim, out var userId) ? userId : 0;
    }

    [HttpGet("daily")]
    public async Task<IActionResult> GetDailyDiary([FromQuery] DateTime date, CancellationToken cancellationToken)
    {
        var userId = GetCurrentUserId();
        if (userId == 0) return Unauthorized();

        if (date == default) date = DateTime.UtcNow.Date;

        var result = await _diaryService.GetDailyDiaryAsync(userId, date, cancellationToken);
        return Ok(result);
    }

    /// <summary>
    /// Logs a meal. Validation lives in <see cref="DiaryValidationRules"/> and
    /// surfaces as RFC 7807 ProblemDetails through the global handler, so this
    /// endpoint never returns an ad-hoc anonymous error shape.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> LogMeal([FromBody] LogMealRequest request, CancellationToken cancellationToken)
    {
        var userId = GetCurrentUserId();
        if (userId == 0) return Unauthorized();

        // Fail fast at the edge so an invalid request never reaches the service
        // or opens a transaction. The service re-validates independently.
        DiaryValidationRules.ValidateLogMeal(request, DateTime.UtcNow);

        var diary = await _diaryService.LogMealAsync(userId, request, cancellationToken);

        // `message` is retained so already-deployed clients that only read it
        // keep working; `diary` is the new authoritative payload.
        return Ok(new LogMealResponse("Meal logged successfully.", diary));
    }

    [HttpGet("stats")]
    public async Task<IActionResult> GetStats(
        [FromQuery] DateTime startDate,
        [FromQuery] DateTime endDate,
        CancellationToken cancellationToken)
    {
        var userId = GetCurrentUserId();
        if (userId == 0) return Unauthorized();

        DiaryValidationRules.ValidateStatsRange(startDate, endDate);

        var result = await _diaryService.GetStatsAsync(userId, startDate, endDate, cancellationToken);
        return Ok(result);
    }
}

/// <summary>Additive response: existing clients read <c>message</c>, new clients read <c>diary</c>.</summary>
public sealed record LogMealResponse(string Message, DailyDiaryDto Diary);
