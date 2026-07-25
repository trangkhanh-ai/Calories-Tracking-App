using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

namespace CaloriesTracking.Api.Tests.Security;

public class RateLimitingTestWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Key"] = CustomWebApplicationFactory.TestJwtKey,
                ["Jwt:Issuer"] = "CaloriesTracking.Api",
                ["Jwt:Audience"] = "CaloriesTracking.Client",
                ["Gemini:ApiKey"] = "test_gemini_api_key_placeholder"
            });
        });
    }
}

public class RateLimitingIntegrationTests : IClassFixture<RateLimitingTestWebApplicationFactory>
{
    private readonly RateLimitingTestWebApplicationFactory _factory;

    public RateLimitingIntegrationTests(RateLimitingTestWebApplicationFactory factory)
    {
        _factory = factory;
    }

    private static string CreateTestJwtToken(string userId)
    {
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, userId),
            new Claim(ClaimTypes.Name, userId)
        };

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(CustomWebApplicationFactory.TestJwtKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: "CaloriesTracking.Api",
            audience: "CaloriesTracking.Client",
            claims: claims,
            expires: DateTime.UtcNow.AddDays(1),
            signingCredentials: creds
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    [Fact]
    public async Task Login_ShouldReturn429_WhenExceeding5RequestsPerMinute()
    {
        var client = _factory.CreateClient();
        var request = new { Email = "test@test.com", Password = "password" };

        for (int i = 0; i < 5; i++)
        {
            await client.PostAsJsonAsync("/api/auth/login", request);
        }

        var rateLimitedResponse = await client.PostAsJsonAsync("/api/auth/login", request);
        Assert.Equal(HttpStatusCode.TooManyRequests, rateLimitedResponse.StatusCode);
    }

    [Fact]
    public async Task Register_ShouldReturn429_WhenExceeding3RequestsPerMinute()
    {
        var client = _factory.CreateClient();
        var request = new { Username = "test", Email = "test2@test.com", Password = "password" };

        for (int i = 0; i < 3; i++)
        {
            await client.PostAsJsonAsync("/api/auth/register", request);
        }

        var rateLimitedResponse = await client.PostAsJsonAsync("/api/auth/register", request);
        Assert.Equal(HttpStatusCode.TooManyRequests, rateLimitedResponse.StatusCode);
    }

    [Fact]
    public async Task FoodSearch_ShouldReturn429_WhenExceeding60RequestsPerMinute()
    {
        var client = _factory.CreateClient();

        for (int i = 0; i < 60; i++)
        {
            await client.GetAsync("/api/food/search?query=rice");
        }

        var rateLimitedResponse = await client.GetAsync("/api/food/search?query=rice");
        Assert.Equal(HttpStatusCode.TooManyRequests, rateLimitedResponse.StatusCode);
    }

    [Fact]
    public async Task Gemini_WithoutJwt_Returns401_BeforeServiceCall()
    {
        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/analysis/food", new { ImageBase64 = "validbase64" });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Gemini_ShouldReturn429_WhenExceeding5RequestsPerMinute_ForSameUser()
    {
        var client = _factory.CreateClient();
        var token = CreateTestJwtToken("user_rate_limit_1");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var payload = new { ImageBase64 = "validbase64" };

        for (int i = 0; i < 5; i++)
        {
            await client.PostAsJsonAsync("/api/analysis/food", payload);
        }

        var rateLimitedResponse = await client.PostAsJsonAsync("/api/analysis/food", payload);
        Assert.Equal(HttpStatusCode.TooManyRequests, rateLimitedResponse.StatusCode);
    }

    [Fact]
    public async Task Gemini_TwoDifferentUsers_HaveIndependentQuotas()
    {
        var client1 = _factory.CreateClient();
        var token1 = CreateTestJwtToken("quota_user_1");
        client1.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token1);

        var payload = new { ImageBase64 = "validbase64" };

        // Exceed user 1 quota
        for (int i = 0; i < 5; i++)
        {
            await client1.PostAsJsonAsync("/api/analysis/food", payload);
        }

        var client1RateLimited = await client1.PostAsJsonAsync("/api/analysis/food", payload);
        Assert.Equal(HttpStatusCode.TooManyRequests, client1RateLimited.StatusCode);

        // User 2 should NOT be rate limited by User 1's quota
        var client2 = _factory.CreateClient();
        var token2 = CreateTestJwtToken("quota_user_2");
        client2.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token2);

        var client2Response = await client2.PostAsJsonAsync("/api/analysis/food", payload);
        Assert.NotEqual(HttpStatusCode.TooManyRequests, client2Response.StatusCode);
    }

    [Fact]
    public async Task Response429_HasCorrectFormattingAndHeaders()
    {
        var client = _factory.CreateClient();
        var request = new { Username = "format_test", Email = "fmt@test.com", Password = "password" };

        for (int i = 0; i < 3; i++)
        {
            await client.PostAsJsonAsync("/api/auth/register", request);
        }

        var rateLimitedResponse = await client.PostAsJsonAsync("/api/auth/register", request);
        Assert.Equal(HttpStatusCode.TooManyRequests, rateLimitedResponse.StatusCode);
        Assert.Equal("application/json", rateLimitedResponse.Content.Headers.ContentType?.MediaType);

        var json = await rateLimitedResponse.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        Assert.Equal(429, root.GetProperty("status").GetInt32());
        Assert.False(string.IsNullOrEmpty(root.GetProperty("title").GetString()));
        Assert.False(string.IsNullOrEmpty(root.GetProperty("detail").GetString()));

        Assert.True(rateLimitedResponse.Headers.Contains("Retry-After"));
    }

    [Fact]
    public async Task HealthEndpoints_ShouldNotBeRateLimited()
    {
        var client = _factory.CreateClient();

        for (int i = 0; i < 70; i++)
        {
            var response = await client.GetAsync("/health/live");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
    }
}
