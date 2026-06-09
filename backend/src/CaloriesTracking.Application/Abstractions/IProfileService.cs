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
}
