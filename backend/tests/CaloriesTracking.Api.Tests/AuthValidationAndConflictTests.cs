using System.Net;
using System.Net.Http.Json;
using CaloriesTracking.Application.Dtos.Auth;

namespace CaloriesTracking.Api.Tests;

public class AuthValidationAndConflictTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public AuthValidationAndConflictTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    [Theory]
    [InlineData("invalid-email")]
    [InlineData("plainaddress")]
    [InlineData("@missinguser.com")]
    [InlineData("user@.com")]
    [InlineData("")]
    public async Task Register_InvalidEmail_Returns400BadRequest(string email)
    {
        var client = _factory.CreateClient();
        var request = new RegisterRequest
        {
            Username = $"user_{Guid.NewGuid():N}",
            Email = email,
            Password = "ValidPassword123!",
            DisplayName = "Test User"
        };

        var response = await client.PostAsJsonAsync("/api/auth/register", request);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Theory]
    [InlineData("short")]
    [InlineData("1234567")]
    [InlineData("")]
    public async Task Register_ShortPassword_Returns400BadRequest(string password)
    {
        var client = _factory.CreateClient();
        var request = new RegisterRequest
        {
            Username = $"user_{Guid.NewGuid():N}",
            Email = $"valid_{Guid.NewGuid():N}@example.com",
            Password = password,
            DisplayName = "Test User"
        };

        var response = await client.PostAsJsonAsync("/api/auth/register", request);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Register_DuplicateUsernameOrEmail_Returns409Conflict()
    {
        var client = _factory.CreateClient();
        var username = $"dup_user_{Guid.NewGuid():N}";
        var email = $"dup_{Guid.NewGuid():N}@example.com";

        var firstRequest = new RegisterRequest
        {
            Username = username,
            Email = email,
            Password = "Password123!",
            DisplayName = "First User"
        };

        var firstResponse = await client.PostAsJsonAsync("/api/auth/register", firstRequest);
        Assert.Equal(HttpStatusCode.OK, firstResponse.StatusCode);

        // Try registering with same email but different username
        var duplicateEmailRequest = new RegisterRequest
        {
            Username = $"other_{Guid.NewGuid():N}",
            Email = email,
            Password = "Password123!",
            DisplayName = "Second User"
        };

        var duplicateResponse = await client.PostAsJsonAsync("/api/auth/register", duplicateEmailRequest);
        Assert.Equal(HttpStatusCode.Conflict, duplicateResponse.StatusCode);
    }

    [Fact]
    public async Task Login_InvalidCredentials_Returns401Unauthorized()
    {
        var client = _factory.CreateClient();
        var request = new LoginRequest
        {
            Username = "non_existent_user",
            Password = "WrongPassword123!"
        };

        var response = await client.PostAsJsonAsync("/api/auth/login", request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
