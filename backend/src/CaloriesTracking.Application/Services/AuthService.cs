using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Auth;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Application.Validation;
using CaloriesTracking.Domain.Entities;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

namespace CaloriesTracking.Application.Services;

public sealed class AuthService : IAuthService
{
    private readonly IUserRepository _userRepository;
    private readonly IConfiguration _configuration;
    private readonly IUniqueConstraintTranslator _constraintTranslator;

    public AuthService(
        IUserRepository userRepository,
        IConfiguration configuration,
        IUniqueConstraintTranslator constraintTranslator)
    {
        _userRepository = userRepository;
        _configuration = configuration;
        _constraintTranslator = constraintTranslator;
    }

    public async Task<AuthResponse> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Validate everything before hashing: BCrypt is deliberately expensive,
        // so a malformed request must never reach it.
        var username = AuthValidationRules.ValidateUsername(request.Username);
        var email = AuthValidationRules.ValidateEmail(request.Email);
        AuthValidationRules.ValidatePassword(request.Password);
        var displayName = AuthValidationRules.ValidateDisplayName(request.DisplayName);

        var normalizedUsername = AuthValidationRules.Normalize(username);
        var normalizedEmail = AuthValidationRules.Normalize(email);

        // Friendly pre-check. It is advisory only — two concurrent registrations
        // can both pass it, so the unique index below is the real guarantee.
        if (await _userRepository.GetByNormalizedUsernameAsync(normalizedUsername, cancellationToken) != null)
        {
            throw new ConflictAppException("Username is already taken.");
        }

        if (await _userRepository.GetByNormalizedEmailAsync(normalizedEmail, cancellationToken) != null)
        {
            throw new ConflictAppException("Email is already registered.");
        }

        var user = new User
        {
            Username = username,
            NormalizedUsername = normalizedUsername,
            Email = email,
            NormalizedEmail = normalizedEmail,
            DisplayName = displayName,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password)
        };

        await _userRepository.AddAsync(user, cancellationToken);

        try
        {
            await _userRepository.SaveChangesAsync(cancellationToken);
        }
        catch (Exception exception) when (_constraintTranslator.IsUniqueViolation(exception))
        {
            // Lost the race against a concurrent registration. Surface a clean
            // 409 — never the provider message, SQL, or constraint name.
            _userRepository.Detach(user);
            throw new ConflictAppException("Username or email is already registered.");
        }

        return BuildResponse(user);
    }

    public async Task<AuthResponse> LoginAsync(LoginRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var identifier = AuthValidationRules.ValidateLoginIdentifier(request.Username);
        AuthValidationRules.ValidateLoginPassword(request.Password);

        var normalizedIdentifier = AuthValidationRules.Normalize(identifier);

        var user = await _userRepository.GetByNormalizedUsernameAsync(normalizedIdentifier, cancellationToken)
            ?? await _userRepository.GetByNormalizedEmailAsync(normalizedIdentifier, cancellationToken);

        // Single generic failure for "no such user" and "wrong password" so the
        // endpoint cannot be used to enumerate accounts.
        if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
        {
            throw new UnauthorizedAccessException("Invalid username or password.");
        }

        return BuildResponse(user);
    }

    private AuthResponse BuildResponse(User user) => new()
    {
        Token = GenerateJwtToken(user),
        UserId = user.Id,
        Username = user.Username,
        DisplayName = user.DisplayName,
        AvatarUrl = user.AvatarUrl
    };

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
