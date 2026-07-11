using System.Security.Claims;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Constants;
using CaloriesTracking.Application.Dtos.Profile;
using CaloriesTracking.Api.Models.Profile;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Controllers;

[ApiController]
[Route("api/profile")]
[Authorize]
public sealed class ProfileController : ControllerBase
{
    private readonly IProfileService _profileService;

    public ProfileController(IProfileService profileService)
    {
        _profileService = profileService;
    }

    [HttpGet("me")]
    public async Task<ActionResult<ProfileResponse>> GetProfile(CancellationToken cancellationToken)
    {
        var currentUserId = GetCurrentUserId();
        if (currentUserId is null)
        {
            return Unauthorized(new { message = "User id claim is missing or invalid." });
        }

        try
        {
            var response = await _profileService.GetProfileAsync(currentUserId.Value, cancellationToken);
            return Ok(response);
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new { message = ex.Message });
        }
    }

    [HttpPatch("me")]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<ProfileResponse>> UpdateProfile(
        [FromForm] UpdateProfileFormRequest request,
        CancellationToken cancellationToken)
    {
        var currentUserId = GetCurrentUserId();
        if (currentUserId is null)
        {
            return Unauthorized(new { message = "User id claim is missing or invalid." });
        }

        AvatarUploadCandidate? avatarFile = null;
        if (request.AvatarFile is not null && request.AvatarFile.Length > 0)
        {
            avatarFile = new AvatarUploadCandidate(
                request.AvatarFile.FileName,
                request.AvatarFile.ContentType ?? string.Empty,
                request.AvatarFile.Length);
        }

        try
        {
            var response = await _profileService.UpdateProfileAsync(
                currentUserId.Value,
                new UpdateProfileRequest
                {
                    DisplayName = request.DisplayName,
                    DefaultAvatarUrl = request.DefaultAvatarUrl,
                    Height = request.Height,
                    Weight = request.Weight,
                    Age = request.Age,
                    Gender = request.Gender,
                    TargetCalories = request.TargetCalories,
                    ActivityLevel = request.ActivityLevel
                },
                avatarFile,
                cancellationToken);

            return Ok(response);
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    /// <summary>Tính BMI/BMR/TDEE/calo khuyến nghị. ?goal=lose|maintain|gain</summary>
    [HttpGet("calorie-goal")]
    public async Task<ActionResult<CalorieGoalResponse>> GetCalorieGoal(
        [FromQuery] string? goal,
        CancellationToken cancellationToken)
    {
        var currentUserId = GetCurrentUserId();
        if (currentUserId is null)
        {
            return Unauthorized(new { message = "User id claim is missing or invalid." });
        }

        try
        {
            var response = await _profileService.GetCalorieGoalAsync(currentUserId.Value, goal, cancellationToken);
            return Ok(response);
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("default-avatars")]
    [AllowAnonymous]
    public ActionResult<IReadOnlyList<string>> GetDefaultAvatars()
    {
        return Ok(ProfileDefaults.AvatarUrls);
    }

    private int? GetCurrentUserId()
    {
        var rawUserId = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub");
        return int.TryParse(rawUserId, out var userId) ? userId : null;
    }
}
