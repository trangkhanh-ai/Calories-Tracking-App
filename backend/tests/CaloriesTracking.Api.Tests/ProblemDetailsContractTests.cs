using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CaloriesTracking.Application.Dtos.Auth;
using CaloriesTracking.Application.Dtos.Diary;

namespace CaloriesTracking.Api.Tests;

/// <summary>
/// Every error path must return RFC 7807 ProblemDetails with the same shape —
/// no endpoint may fall back to an ad-hoc anonymous object.
/// </summary>
public sealed class ProblemDetailsContractTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public ProblemDetailsContractTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Register_WithInvalidUsername_ReturnsProblemDetails400()
    {
        var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/register", new RegisterRequest
        {
            Username = "has spaces",
            Email = "spaces@example.com",
            Password = "Password123!",
            DisplayName = "Spaces"
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await AssertProblemDetailsAsync(response, expectedStatus: 400, expectedTitle: "Bad Request");
    }

    [Fact]
    public async Task Register_WithShortPassword_ReturnsProblemDetails400()
    {
        var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/register", new RegisterRequest
        {
            Username = "shortpw",
            Email = "shortpw@example.com",
            Password = "Ab1!",
            DisplayName = "Short"
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);

        var problem = await AssertProblemDetailsAsync(response, 400, "Bad Request");

        // The rejected password must never be echoed back.
        Assert.DoesNotContain("Ab1!", problem.RootElement.GetRawText(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Register_WhenDuplicated_ReturnsProblemDetails409()
    {
        var client = _factory.CreateClient();

        var request = new RegisterRequest
        {
            Username = $"dup{Guid.NewGuid():N}"[..20],
            Email = $"dup{Guid.NewGuid():N}@example.com",
            Password = "Password123!",
            DisplayName = "Duplicate"
        };

        var first = await client.PostAsJsonAsync("/api/auth/register", request);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        var second = await client.PostAsJsonAsync("/api/auth/register", request);

        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);

        var problem = await AssertProblemDetailsAsync(second, 409, "Conflict");

        // No SQL, constraint name, or provider text may leak.
        var raw = problem.RootElement.GetRawText();
        foreach (var forbidden in new[] { "SQLite", "UNIQUE constraint", "IX_Users", "INSERT INTO" })
        {
            Assert.DoesNotContain(forbidden, raw, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task Diary_WithoutAuthentication_Returns401()
    {
        var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/diary", new LogMealRequest(
            FoodName: "Phở",
            CaloriesPer100g: 100,
            Quantity: 100,
            MealType: "Breakfast",
            Date: DateTime.UtcNow));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task FoodSearch_WithOversizedQuery_ReturnsProblemDetails400()
    {
        var client = _factory.CreateClient();
        var oversized = new string('a', 101);

        var response = await client.GetAsync($"/api/food/search?query={oversized}");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await AssertProblemDetailsAsync(response, 400, "Bad Request");
    }

    private static async Task<JsonDocument> AssertProblemDetailsAsync(
        HttpResponseMessage response,
        int expectedStatus,
        string expectedTitle)
    {
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);

        var payload = await response.Content.ReadAsStringAsync();
        var document = JsonDocument.Parse(payload);
        var root = document.RootElement;

        Assert.Equal(expectedStatus, root.GetProperty("status").GetInt32());
        Assert.Equal(expectedTitle, root.GetProperty("title").GetString());

        Assert.True(root.TryGetProperty("detail", out var detail));
        Assert.False(string.IsNullOrWhiteSpace(detail.GetString()));

        // traceId is what makes a production report actionable.
        Assert.True(root.TryGetProperty("traceId", out var traceId));
        Assert.False(string.IsNullOrWhiteSpace(traceId.GetString()));

        // A stack trace must never cross the wire.
        Assert.DoesNotContain("   at ", payload, StringComparison.Ordinal);

        return document;
    }
}
