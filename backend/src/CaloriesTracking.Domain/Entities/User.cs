namespace CaloriesTracking.Domain.Entities;

public class User
{
    public int Id { get; set; }

    public required string Username { get; set; }

    /// <summary>
    /// Uppercase-invariant copy of <see cref="Username"/>. Carries the unique
    /// index so case-insensitive uniqueness is enforced by the database on both
    /// SQLite and PostgreSQL rather than by a racy application pre-check.
    /// </summary>
    public string NormalizedUsername { get; set; } = string.Empty;

    public required string PasswordHash { get; set; }

    public required string Email { get; set; }

    /// <summary>Uppercase-invariant copy of <see cref="Email"/>. See <see cref="NormalizedUsername"/>.</summary>
    public string NormalizedEmail { get; set; } = string.Empty;

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
