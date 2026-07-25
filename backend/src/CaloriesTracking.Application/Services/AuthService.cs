using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Auth;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Domain.Entities;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

namespace CaloriesTracking.Application.Services;

public sealed class AuthService : IAuthService
{
    private readonly IUserRepository _userRepository;
    private readonly IConfiguration _configuration;

    public AuthService(IUserRepository userRepository, IConfiguration configuration)
    {
        _userRepository = userRepository;
        _configuration = configuration;
    }

    public async Task<AuthResponse> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Username))
        {
            throw new ArgumentException("Username is required.");
        }

        if (!IsValidEmail(request.Email))
        {
            throw new ArgumentException("Email is required and must be a valid email address.");
        }

        if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8)
        {
            throw new ArgumentException("Password must be at least 8 characters long.");
        }

        if (string.IsNullOrWhiteSpace(request.DisplayName))
        {
            throw new ArgumentException("DisplayName is required.");
        }

        var trimmedUsername = request.Username.Trim();
        var normalizedEmail = request.Email.Trim().ToLowerInvariant();

        if (await _userRepository.GetByUsernameAsync(trimmedUsername, cancellationToken) != null)
        {
            throw new DuplicateUserException("Username is already taken.");
        }

        if (await _userRepository.GetByEmailAsync(normalizedEmail, cancellationToken) != null)
        {
            throw new DuplicateUserException("Email is already registered.");
        }

        var user = new User
        {
            Username = trimmedUsername,
            Email = normalizedEmail,
            DisplayName = request.DisplayName.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password)
        };

        await _userRepository.AddAsync(user, cancellationToken);
        await _userRepository.SaveChangesAsync(cancellationToken);

        var token = GenerateJwtToken(user);

        return new AuthResponse
        {
            Token = token,
            UserId = user.Id,
            Username = user.Username,
            DisplayName = user.DisplayName,
            AvatarUrl = user.AvatarUrl
        };
    }

    public async Task<AuthResponse> LoginAsync(LoginRequest request, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Username))
        {
            throw new ArgumentException("Username or Email is required.");
        }

        if (string.IsNullOrWhiteSpace(request.Password))
        {
            throw new ArgumentException("Password is required.");
        }

        var input = request.Username.Trim();
        var user = await _userRepository.GetByUsernameAsync(input, cancellationToken)
            ?? (input.Contains('@') ? await _userRepository.GetByEmailAsync(input.ToLowerInvariant(), cancellationToken) : null);

        if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
        {
            throw new UnauthorizedAccessException("Invalid username or password.");
        }

        var token = GenerateJwtToken(user);

        return new AuthResponse
        {
            Token = token,
            UserId = user.Id,
            Username = user.Username,
            DisplayName = user.DisplayName,
            AvatarUrl = user.AvatarUrl
        };
    }

    private static bool IsValidEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(email)) return false;
        var trimmed = email.Trim();
        return System.Net.Mail.MailAddress.TryCreate(trimmed, out var address)
            && address.Address == trimmed
            && trimmed.Contains('@')
            && trimmed.Split('@')[1].Contains('.');
    }

    private string GenerateJwtToken(User user)
    {
        var jwtSection = _configuration.GetSection("Jwt");
        var signingKey = jwtSection["Key"]
            ?? throw new InvalidOperationException("Jwt:Key is not configured.");

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Username),
            new Claim("DisplayName", user.DisplayName)
        };

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: jwtSection["Issuer"],
            audience: jwtSection["Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddDays(7),
            signingCredentials: creds
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
