using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Application.Validation;

namespace CaloriesTracking.Api.Tests;

public sealed class AuthValidationRulesTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ValidateUsername_WhenMissing_Throws(string? username)
    {
        var exception = Assert.Throws<ValidationAppException>(
            () => AuthValidationRules.ValidateUsername(username));

        Assert.Equal("username", exception.Field);
    }

    [Theory]
    [InlineData("ab")]                 // one below the 3-character minimum
    [InlineData("a")]
    public void ValidateUsername_WhenBelowMinimum_Throws(string username)
    {
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidateUsername(username));
    }

    [Fact]
    public void ValidateUsername_WhenAtBoundaries_IsAccepted()
    {
        Assert.Equal("abc", AuthValidationRules.ValidateUsername("abc"));

        var maxLength = new string('a', AuthValidationRules.UsernameMaxLength);
        Assert.Equal(maxLength, AuthValidationRules.ValidateUsername(maxLength));
    }

    [Fact]
    public void ValidateUsername_WhenAboveMaximum_Throws()
    {
        var tooLong = new string('a', AuthValidationRules.UsernameMaxLength + 1);
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidateUsername(tooLong));
    }

    [Theory]
    [InlineData("user name")]          // space
    [InlineData("user@name")]
    [InlineData("user!name")]
    [InlineData("user/name")]
    [InlineData("user\\name")]
    [InlineData("user%name")]
    [InlineData("người-dùng")]         // non-ASCII letters are outside the allow-list
    public void ValidateUsername_WhenCharactersAreDisallowed_Throws(string username)
    {
        var exception = Assert.Throws<ValidationAppException>(
            () => AuthValidationRules.ValidateUsername(username));

        Assert.Contains("letters, digits, underscore, dot, and hyphen", exception.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("user_name")]
    [InlineData("user.name")]
    [InlineData("user-name")]
    [InlineData("User123")]
    public void ValidateUsername_WhenCharactersAreAllowed_IsAccepted(string username)
    {
        Assert.Equal(username, AuthValidationRules.ValidateUsername(username));
    }

    [Fact]
    public void ValidateUsername_TrimsSurroundingWhitespace()
    {
        Assert.Equal("valid_user", AuthValidationRules.ValidateUsername("  valid_user  "));
    }

    [Fact]
    public void ValidateEmail_NormalizesToLowercase()
    {
        Assert.Equal("user@example.com", AuthValidationRules.ValidateEmail("  User@Example.COM  "));
    }

    [Theory]
    [InlineData("not-an-email")]
    [InlineData("missing@domain")]
    [InlineData("@example.com")]
    [InlineData("two@@example.com")]
    [InlineData("trailing@example.")]
    public void ValidateEmail_WhenFormatIsInvalid_Throws(string email)
    {
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidateEmail(email));
    }

    [Fact]
    public void ValidateEmail_WhenAboveMaximumLength_Throws()
    {
        // 255 characters total — one past the RFC-derived 254 limit.
        var local = new string('a', AuthValidationRules.EmailMaxLength - "@example.com".Length + 1);
        var email = $"{local}@example.com";

        Assert.True(email.Length > AuthValidationRules.EmailMaxLength);
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidateEmail(email));
    }

    [Fact]
    public void ValidatePassword_AtMinimumBoundary_IsAccepted()
    {
        AuthValidationRules.ValidatePassword(new string('x', AuthValidationRules.PasswordMinLength));
    }

    [Fact]
    public void ValidatePassword_OneBelowMinimum_Throws()
    {
        var tooShort = new string('x', AuthValidationRules.PasswordMinLength - 1);
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidatePassword(tooShort));
    }

    [Fact]
    public void ValidatePassword_AtMaximumBoundary_IsAccepted()
    {
        AuthValidationRules.ValidatePassword(new string('x', AuthValidationRules.PasswordMaxLength));
    }

    [Fact]
    public void ValidatePassword_OneAboveMaximum_Throws()
    {
        var tooLong = new string('x', AuthValidationRules.PasswordMaxLength + 1);
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidatePassword(tooLong));
    }

    [Fact]
    public void ValidatePassword_ErrorMessageNeverContainsThePassword()
    {
        const string secret = "short";

        var exception = Assert.Throws<ValidationAppException>(
            () => AuthValidationRules.ValidatePassword(secret));

        Assert.DoesNotContain(secret, exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ValidateDisplayName_AtMaximumBoundary_IsAccepted()
    {
        var maxLength = new string('n', AuthValidationRules.DisplayNameMaxLength);
        Assert.Equal(maxLength, AuthValidationRules.ValidateDisplayName(maxLength));
    }

    [Fact]
    public void ValidateDisplayName_OneAboveMaximum_Throws()
    {
        var tooLong = new string('n', AuthValidationRules.DisplayNameMaxLength + 1);
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidateDisplayName(tooLong));
    }

    [Fact]
    public void ValidateLoginIdentifier_AtMaximumBoundary_IsAccepted()
    {
        var maxLength = new string('u', AuthValidationRules.LoginIdentifierMaxLength);
        Assert.Equal(maxLength, AuthValidationRules.ValidateLoginIdentifier(maxLength));
    }

    [Fact]
    public void ValidateLoginIdentifier_OneAboveMaximum_Throws()
    {
        var tooLong = new string('u', AuthValidationRules.LoginIdentifierMaxLength + 1);
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidateLoginIdentifier(tooLong));
    }

    [Fact]
    public void ValidateLoginPassword_OneAboveMaximum_Throws()
    {
        var tooLong = new string('x', AuthValidationRules.PasswordMaxLength + 1);
        Assert.Throws<ValidationAppException>(() => AuthValidationRules.ValidateLoginPassword(tooLong));
    }

    [Fact]
    public void ValidateLoginPassword_DoesNotEnforceARegistrationMinimum()
    {
        // Login must not leak the registration policy to unauthenticated callers.
        AuthValidationRules.ValidateLoginPassword("x");
    }

    [Theory]
    [InlineData("User", "USER")]
    [InlineData("  user  ", "USER")]
    [InlineData("USER@Example.com", "USER@EXAMPLE.COM")]
    public void Normalize_IsUppercaseInvariantAndTrimmed(string input, string expected)
    {
        Assert.Equal(expected, AuthValidationRules.Normalize(input));
    }
}
