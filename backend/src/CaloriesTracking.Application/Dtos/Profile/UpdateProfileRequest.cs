namespace CaloriesTracking.Application.Dtos.Profile;

public sealed class UpdateProfileRequest
{
    public required string DisplayName { get; init; }

    public string? DefaultAvatarUrl { get; init; }

    public decimal? Height { get; init; }

    public decimal? Weight { get; init; }

    public int? Age { get; init; }

    public string? Gender { get; init; }

    public int? TargetCalories { get; init; }

    /// <summary>sedentary | light | moderate | active | very_active</summary>
    public string? ActivityLevel { get; init; }
}
