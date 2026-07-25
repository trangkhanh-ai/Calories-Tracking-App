using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CaloriesTracking.Api.Controllers;
using CaloriesTracking.Application.Dtos.Analysis;
using CaloriesTracking.Application.Dtos.Auth;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Http.Resilience;
using System.Net.Http.Headers;

namespace CaloriesTracking.Api.Tests.Security;

public class RateLimitingIntegrationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public RateLimitingIntegrationTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Login_ShouldReturn429_WhenExceeding5RequestsPerMinute()
    {
        var client = _factory.CreateClient();
        var request = new { Email = "test@test.com", Password = "password" };

        for (int i = 0; i < 5; i++)
        {
            var response = await client.PostAsJsonAsync("/api/auth/login", request);
            // First 5 can be 400/401/200, we just want to trigger the rate limiter
        }

        var rateLimitedResponse = await client.PostAsJsonAsync("/api/auth/login", request);
        Assert.Equal(HttpStatusCode.TooManyRequests, rateLimitedResponse.StatusCode);
        
        var json = await rateLimitedResponse.Content.ReadAsStringAsync();
        Assert.Contains("Too many requests", json);
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
