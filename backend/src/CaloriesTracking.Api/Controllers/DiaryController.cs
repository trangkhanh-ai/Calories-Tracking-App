using System.Security.Claims;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Diary;
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

    [HttpPost]
    public async Task<IActionResult> LogMeal([FromBody] LogMealRequest request, CancellationToken cancellationToken)
    {
        var userId = GetCurrentUserId();
        if (userId == 0) return Unauthorized();

        await _diaryService.LogMealAsync(userId, request, cancellationToken);
        return Ok(new { message = "Meal logged successfully." });
    }

    [HttpGet("stats")]
    public async Task<IActionResult> GetStats([FromQuery] DateTime startDate, [FromQuery] DateTime endDate, CancellationToken cancellationToken)
    {
        var userId = GetCurrentUserId();
        if (userId == 0) return Unauthorized();

        var result = await _diaryService.GetStatsAsync(userId, startDate, endDate, cancellationToken);
        return Ok(result);
    }
}
