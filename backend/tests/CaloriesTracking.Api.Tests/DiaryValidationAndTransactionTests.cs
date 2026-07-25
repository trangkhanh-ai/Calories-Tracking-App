using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using CaloriesTracking.Application.Dtos.Diary;
using Microsoft.IdentityModel.Tokens;

namespace CaloriesTracking.Api.Tests;

public class DiaryValidationAndTransactionTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public DiaryValidationAndTransactionTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    [InlineData(-0.01)]
    public async Task LogMeal_InvalidQuantity_Returns400BadRequest(decimal quantity)
    {
        var client = CreateAuthenticatedClient();
        var request = new LogMealRequest(
            FoodName: "Apple",
            CaloriesPer100g: 52m,
            Quantity: quantity,
            MealType: "Breakfast",
            Date: DateTime.UtcNow);

        var response = await client.PostAsJsonAsync("/api/diary", request);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Theory]
    [InlineData("Brunch")]
    [InlineData("MidnightSnack")]
    [InlineData("breakfast")]
    [InlineData("")]
    public async Task LogMeal_InvalidMealType_Returns400BadRequest(string mealType)
    {
        var client = CreateAuthenticatedClient();
        var request = new LogMealRequest(
            FoodName: "Apple",
            CaloriesPer100g: 52m,
            Quantity: 100m,
            MealType: mealType,
            Date: DateTime.UtcNow);

        var response = await client.PostAsJsonAsync("/api/diary", request);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task GetStats_StartDateAfterEndDate_Returns400BadRequest()
    {
        var client = CreateAuthenticatedClient();
        var startDate = DateTime.UtcNow.AddDays(5).ToString("yyyy-MM-dd");
        var endDate = DateTime.UtcNow.ToString("yyyy-MM-dd");

        var response = await client.GetAsync($"/api/diary/stats?startDate={startDate}&endDate={endDate}");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private HttpClient CreateAuthenticatedClient()
    {
        var client = _factory.CreateClient();
        var token = GenerateTestToken("999");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private static string GenerateTestToken(string userId)
    {
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, userId),
            new Claim(ClaimTypes.Name, "testuser")
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
}
