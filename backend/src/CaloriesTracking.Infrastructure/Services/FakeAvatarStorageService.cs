using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Profile;

namespace CaloriesTracking.Infrastructure.Services;

public sealed class FakeAvatarStorageService : IAvatarStorageService
{
    public Task<string> UploadAsync(AvatarUploadCandidate file, CancellationToken cancellationToken = default)
    {
        var seed = Guid.NewGuid().ToString("N").Substring(0, 6);
        var url = $"https://api.dicebear.com/9.x/avataaars/png?seed=Upload{seed}";
        return Task.FromResult(url);
    }
}
