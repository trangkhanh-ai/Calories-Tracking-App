using CaloriesTracking.Application.Dtos.Profile;

namespace CaloriesTracking.Application.Abstractions;

public interface IProfileService
{
    Task<ProfileResponse> GetProfileAsync(int userId, CancellationToken cancellationToken = default);

    Task<ProfileResponse> UpdateProfileAsync(
        int userId,
        UpdateProfileRequest request,
        AvatarUploadCandidate? avatarFile = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Tính BMI/BMR/TDEE/calo khuyến nghị từ hồ sơ user.
    /// goal: lose | maintain | gain (mặc định maintain).
    /// </summary>
    Task<CalorieGoalResponse> GetCalorieGoalAsync(int userId, string? goal = null, CancellationToken cancellationToken = default);
}
