using Microsoft.AspNetCore.Http;

namespace CaloriesTracking.Api.Models.Profile;

public sealed class UpdateProfileFormRequest
{
    public required string DisplayName { get; init; }

    public IFormFile? AvatarFile { get; init; }

    public string? DefaultAvatarUrl { get; init; }

    public decimal? Height { get; init; }

    public decimal? Weight { get; init; }

    public int? Age { get; init; }

    public string? Gender { get; init; }

    public int? TargetCalories { get; init; }

    public string? ActivityLevel { get; init; }
}
