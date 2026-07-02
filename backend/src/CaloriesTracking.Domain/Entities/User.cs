namespace CaloriesTracking.Domain.Entities;

public class User
{
    public int Id { get; set; }

    public required string Username { get; set; }

    public required string PasswordHash { get; set; }

    public required string Email { get; set; }

    public required string DisplayName { get; set; }

    public string? AvatarUrl { get; set; }

    public decimal? Height { get; set; }

    public decimal? Weight { get; set; }

    public int? Age { get; set; }

    public string? Gender { get; set; }

    public int? TargetCalories { get; set; }

    /// <summary>sedentary | light | moderate | active | very_active</summary>
    public string? ActivityLevel { get; set; }

    public ICollection<DailyLog> DailyLogs { get; set; } = new List<DailyLog>();
}
