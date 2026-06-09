using CaloriesTracking.Application.Dtos.Profile;

namespace CaloriesTracking.Application.Abstractions;

public interface IAvatarStorageService
{
    Task<string> UploadAsync(AvatarUploadCandidate file, CancellationToken cancellationToken = default);
}
