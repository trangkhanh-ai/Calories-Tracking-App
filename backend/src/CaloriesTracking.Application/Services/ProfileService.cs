using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Constants;
using CaloriesTracking.Application.Dtos.Profile;
using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Services;

public sealed class ProfileService : IProfileService
{
    private const long MaxAvatarSizeBytes = 2 * 1024 * 1024;
    private static readonly HashSet<string> AllowedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
        ".gif",
        ".bmp",
        ".tiff",
        ".svg",
        ".ico"
    };

    private readonly IAvatarStorageService _avatarStorageService;
    private readonly IUserRepository _userRepository;

    public ProfileService(IUserRepository userRepository, IAvatarStorageService avatarStorageService)
    {
        _userRepository = userRepository;
        _avatarStorageService = avatarStorageService;
    }
    public async Task<ProfileResponse> GetProfileAsync(int userId, CancellationToken cancellationToken = default)
    {
        var user = await _userRepository.GetByIdAsync(userId, cancellationToken);
        if (user is null)
        {
            throw new KeyNotFoundException($"User with id '{userId}' was not found.");
        }

        return MapToResponse(user);
    }

    public async Task<ProfileResponse> UpdateProfileAsync(
        int userId,
        UpdateProfileRequest request,
        AvatarUploadCandidate? avatarFile = null,
        CancellationToken cancellationToken = default)
    {
        if (request is null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        if (string.IsNullOrWhiteSpace(request.DisplayName))
        {
            throw new ArgumentException("DisplayName is required.", nameof(request.DisplayName));
        }

        var user = await _userRepository.GetByIdAsync(userId, cancellationToken);
        if (user is null)
        {
            throw new KeyNotFoundException($"User with id '{userId}' was not found.");
        }

        user.DisplayName = request.DisplayName.Trim();
                                
        if (request.Height.HasValue)
        {
            if (request.Height.Value <= 0) throw new ArgumentException("Height must be positive.", nameof(request.Height));
            user.Height = request.Height.Value;
        }

        if (request.Weight.HasValue)
        {
            if (request.Weight.Value <= 0) throw new ArgumentException("Weight must be positive.", nameof(request.Weight));
            user.Weight = request.Weight.Value;
        }

        if (request.Age.HasValue)
        {
            if (request.Age.Value <= 0) throw new ArgumentException("Age must be positive.", nameof(request.Age));
            user.Age = request.Age.Value;
        }

        if (!string.IsNullOrWhiteSpace(request.Gender))
        {
            user.Gender = request.Gender.Trim();
        }

        if (request.TargetCalories.HasValue)
        {
            if (request.TargetCalories.Value <= 0) throw new ArgumentException("Target calories must be positive.", nameof(request.TargetCalories));
            user.TargetCalories = request.TargetCalories.Value;
        }

        if (avatarFile is not null)
        {
            ValidateAvatarFile(avatarFile);
            user.AvatarUrl = await _avatarStorageService.UploadAsync(avatarFile, cancellationToken);
        }
        else if (!string.IsNullOrWhiteSpace(request.DefaultAvatarUrl))
        {
            if (!ProfileDefaults.AvatarUrls.Contains(request.DefaultAvatarUrl, StringComparer.OrdinalIgnoreCase))
            {
                throw new ArgumentException("Default avatar URL is not supported.", nameof(request.DefaultAvatarUrl));
            }

            user.AvatarUrl = request.DefaultAvatarUrl;
        }

        await _userRepository.SaveChangesAsync(cancellationToken);

        return MapToResponse(user);
    }

    private static void ValidateAvatarFile(AvatarUploadCandidate avatarFile)
    {
        if (avatarFile.Length <= 0)
        {
            throw new ArgumentException("Avatar file is empty.", nameof(avatarFile));
        }

        if (avatarFile.Length >= MaxAvatarSizeBytes)
        {
            throw new ArgumentException("Avatar file must be smaller than 2MB.", nameof(avatarFile));
        }

        var extension = Path.GetExtension(avatarFile.FileName);
        if (string.IsNullOrWhiteSpace(extension) || !AllowedExtensions.Contains(extension))
        {
            throw new ArgumentException("Only .jpg, .jpeg, and .png files are allowed.", nameof(avatarFile));
        }

        if (!string.IsNullOrWhiteSpace(avatarFile.ContentType) &&
            !avatarFile.ContentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Avatar file must be an image.", nameof(avatarFile));
        }
    }

    private static ProfileResponse MapToResponse(User user)
    {
        return new ProfileResponse
        {
            Id = user.Id,
            Username = user.Username,
            DisplayName = user.DisplayName,
            AvatarUrl = user.AvatarUrl,
            Email = user.Email,
            Height = user.Height,
            Weight = user.Weight,
            Age = user.Age,
            Gender = user.Gender,
            TargetCalories = user.TargetCalories
        };
    }
}
