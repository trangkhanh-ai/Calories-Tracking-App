namespace CaloriesTracking.Application.Dtos.Auth;

public sealed class AuthResponse
{
    public required string Token { get; init; }
    public required int UserId { get; init; }
    public required string Username { get; init; }
    public required string DisplayName { get; init; }
    public string? AvatarUrl { get; init; }
}
