namespace CaloriesTracking.Application.Dtos.Profile;

public sealed class ProfileResponse
{
    public int Id { get; init; }

    public required string Username { get; init; }

    public required string DisplayName { get; init; }

    public string? AvatarUrl { get; init; }

    public required string Email { get; init; }

    public decimal? Height { get; init; }

    public decimal? Weight { get; init; }

    public int? Age { get; init; }

    public string? Gender { get; init; }

    public int? TargetCalories { get; init; }
}
