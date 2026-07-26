using System.Text.RegularExpressions;
using CaloriesTracking.Application.Exceptions;

namespace CaloriesTracking.Application.Validation;

/// <summary>
/// Registration/login contract enforcement. Every rule runs before password
/// hashing or any database round-trip so a malformed request never costs a
/// BCrypt work factor.
/// </summary>
public static partial class AuthValidationRules
{
    public const int UsernameMinLength = 3;
    public const int UsernameMaxLength = 50;
    public const int EmailMaxLength = 254;
    public const int PasswordMinLength = 8;
    public const int PasswordMaxLength = 128;
    public const int DisplayNameMinLength = 1;
    public const int DisplayNameMaxLength = 150;
    public const int LoginIdentifierMaxLength = 254;

    [GeneratedRegex(@"^[A-Za-z0-9_.\-]+$", RegexOptions.CultureInvariant)]
    private static partial Regex UsernamePattern();

    /// <summary>
    /// Validates and returns the trimmed username. Never echoes the password.
    /// </summary>
    public static string ValidateUsername(string? username)
    {
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new ValidationAppException("username", "Username is required.");
        }

        var trimmed = username.Trim();

        if (trimmed.Length < UsernameMinLength || trimmed.Length > UsernameMaxLength)
        {
            throw new ValidationAppException(
                "username",
                $"Username must be between {UsernameMinLength} and {UsernameMaxLength} characters.");
        }

        if (!UsernamePattern().IsMatch(trimmed))
        {
            throw new ValidationAppException(
                "username",
                "Username may only contain letters, digits, underscore, dot, and hyphen.");
        }

        return trimmed;
    }

    /// <summary>Validates and returns the trimmed, lowercased email.</summary>
    public static string ValidateEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ValidationAppException("email", "Email is required.");
        }

        var trimmed = email.Trim();

        if (trimmed.Length > EmailMaxLength)
        {
            throw new ValidationAppException(
                "email",
                $"Email must not exceed {EmailMaxLength} characters.");
        }

        if (!IsValidEmailFormat(trimmed))
        {
            throw new ValidationAppException("email", "Email must be a valid email address.");
        }

        return trimmed.ToLowerInvariant();
    }

    /// <summary>
    /// Validates password length only. The value is never trimmed (leading and
    /// trailing spaces are legitimate password characters) and never logged.
    /// </summary>
    public static void ValidatePassword(string? password)
    {
        if (string.IsNullOrWhiteSpace(password))
        {
            throw new ValidationAppException("password", "Password is required.");
        }

        if (password.Length < PasswordMinLength)
        {
            throw new ValidationAppException(
                "password",
                $"Password must be at least {PasswordMinLength} characters long.");
        }

        if (password.Length > PasswordMaxLength)
        {
            throw new ValidationAppException(
                "password",
                $"Password must not exceed {PasswordMaxLength} characters.");
        }
    }

    /// <summary>Validates and returns the trimmed display name.</summary>
    public static string ValidateDisplayName(string? displayName)
    {
        if (string.IsNullOrWhiteSpace(displayName))
        {
            throw new ValidationAppException("displayName", "DisplayName is required.");
        }

        var trimmed = displayName.Trim();

        if (trimmed.Length < DisplayNameMinLength || trimmed.Length > DisplayNameMaxLength)
        {
            throw new ValidationAppException(
                "displayName",
                $"DisplayName must be between {DisplayNameMinLength} and {DisplayNameMaxLength} characters.");
        }

        return trimmed;
    }

    /// <summary>
    /// Login accepts either a username or an email, so the format is not
    /// constrained beyond length — only the credential check decides the outcome.
    /// </summary>
    public static string ValidateLoginIdentifier(string? identifier)
    {
        if (string.IsNullOrWhiteSpace(identifier))
        {
            throw new ValidationAppException("username", "Username or Email is required.");
        }

        var trimmed = identifier.Trim();

        if (trimmed.Length > LoginIdentifierMaxLength)
        {
            throw new ValidationAppException(
                "username",
                $"Username or Email must not exceed {LoginIdentifierMaxLength} characters.");
        }

        return trimmed;
    }

    /// <summary>
    /// Login only enforces presence and an upper bound. A minimum here would
    /// leak the registration policy to unauthenticated callers.
    /// </summary>
    public static void ValidateLoginPassword(string? password)
    {
        if (string.IsNullOrWhiteSpace(password))
        {
            throw new ValidationAppException("password", "Password is required.");
        }

        if (password.Length > PasswordMaxLength)
        {
            throw new ValidationAppException(
                "password",
                $"Password must not exceed {PasswordMaxLength} characters.");
        }
    }

    /// <summary>
    /// Uppercase-invariant normalization, matching the ASP.NET Identity
    /// convention. Persisted so the database — not application code — owns
    /// case-insensitive uniqueness.
    /// </summary>
    public static string Normalize(string value) => value.Trim().ToUpperInvariant();

    private static bool IsValidEmailFormat(string trimmed)
    {
        if (!System.Net.Mail.MailAddress.TryCreate(trimmed, out var address))
        {
            return false;
        }

        if (address.Address != trimmed)
        {
            return false;
        }

        var atIndex = trimmed.IndexOf('@');
        if (atIndex <= 0 || atIndex != trimmed.LastIndexOf('@'))
        {
            return false;
        }

        var domain = trimmed[(atIndex + 1)..];
        return domain.Contains('.') && !domain.StartsWith('.') && !domain.EndsWith('.');
    }
}
