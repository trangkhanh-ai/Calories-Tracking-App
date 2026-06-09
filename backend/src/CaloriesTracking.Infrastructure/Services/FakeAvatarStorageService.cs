using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Profile;

namespace CaloriesTracking.Infrastructure.Services;

public sealed class FakeAvatarStorageService : IAvatarStorageService
{
    public Task<string> UploadAsync(AvatarUploadCandidate file, CancellationToken cancellationToken = default)
    {
        var extension = Path.GetExtension(file.FileName);
        if (string.IsNullOrWhiteSpace(extension))
        {
            extension = ".png";
        }

        var url = $"https://cdn.calories-tracking.app/uploads/avatars/{Guid.NewGuid():N}{extension.ToLowerInvariant()}";
        return Task.FromResult(url);
    }
}
