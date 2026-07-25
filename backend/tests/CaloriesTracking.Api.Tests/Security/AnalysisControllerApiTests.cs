using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Analysis;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Moq;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace CaloriesTracking.Api.Tests.Security;

public class AnalysisControllerApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string TestJwtKey = "test_jwt_secret_key_must_be_at_least_32_bytes!";
    private readonly WebApplicationFactory<Program> _factory;
    private readonly Mock<IFoodAnalysisService> _mockFoodAnalysisService;

    public AnalysisControllerApiTests(WebApplicationFactory<Program> factory)
    {
        _mockFoodAnalysisService = new Mock<IFoodAnalysisService>();

        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Jwt:Key"] = TestJwtKey,
                    ["Jwt:Issuer"] = "CaloriesTracking.Api",
                    ["Jwt:Audience"] = "CaloriesTracking.Client",
                    ["Gemini:ApiKey"] = "test-key"
                });
            });

            builder.ConfigureServices(services =>
            {
                services.AddScoped(_ => _mockFoodAnalysisService.Object);
            });
        });
    }

    private HttpClient CreateAuthenticatedClient()
    {
        var client = _factory.CreateClient();
        var token = GenerateTestToken("user_test_123");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private static string GenerateTestToken(string userId)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(TestJwtKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, userId),
            new Claim(ClaimTypes.Name, "testuser"),
            new Claim(ClaimTypes.Email, "test@example.com")
        };

        var token = new JwtSecurityToken(
            issuer: "CaloriesTracking.Api",
            audience: "CaloriesTracking.Client",
            claims: claims,
            expires: DateTime.UtcNow.AddHours(1),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static byte[] CreateJpegImage(int width, int height)
    {
        using var image = new Image<Rgba32>(width, height);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);
        return ms.ToArray();
    }

    [Fact]
    public async Task AnalyzeFood_EmptyBase64_Returns400()
    {
        var client = CreateAuthenticatedClient();
        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest(""));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_InvalidBase64_Returns400()
    {
        var client = CreateAuthenticatedClient();
        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest("invalid_base64_content!!!"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_DataUriPrefix_Returns400()
    {
        var client = CreateAuthenticatedClient();
        var validBase64 = Convert.ToBase64String(CreateJpegImage(10, 10));
        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest($"data:image/jpeg;base64,{validBase64}"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_Base64StringTooLong_Returns413()
    {
        var client = CreateAuthenticatedClient();
        var oversizedBase64 = new string('A', 7_000_001);
        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest(oversizedBase64));

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_DecodedBytesOver5MB_Returns413()
    {
        var client = CreateAuthenticatedClient();
        var largeBytes = new byte[5 * 1024 * 1024 + 100];
        var largeBase64 = Convert.ToBase64String(largeBytes);

        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest(largeBase64));

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_UnsupportedImageFormat_Returns415()
    {
        var client = CreateAuthenticatedClient();
        _mockFoodAnalysisService
            .Setup(s => s.AnalyzeAsync(It.IsAny<byte[]>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new NotSupportedException("bmp is not supported"));

        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsBmp(ms);
        var base64 = Convert.ToBase64String(ms.ToArray());

        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest(base64));

        Assert.Equal(HttpStatusCode.UnsupportedMediaType, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_ImageWidthOver8000_Returns413()
    {
        var client = CreateAuthenticatedClient();
        _mockFoodAnalysisService
            .Setup(s => s.AnalyzeAsync(It.IsAny<byte[]>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Image dimensions exceed 8000x8000."));

        var base64 = Convert.ToBase64String(CreateJpegImage(10, 10));
        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest(base64));

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_ImageHeightOver8000_Returns413()
    {
        var client = CreateAuthenticatedClient();
        _mockFoodAnalysisService
            .Setup(s => s.AnalyzeAsync(It.IsAny<byte[]>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Image dimensions exceed 8000x8000."));

        var base64 = Convert.ToBase64String(CreateJpegImage(10, 10));
        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest(base64));

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeFood_PixelCountOver20Million_Returns413()
    {
        var client = CreateAuthenticatedClient();
        _mockFoodAnalysisService
            .Setup(s => s.AnalyzeAsync(It.IsAny<byte[]>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Image pixel count exceeds 20,000,000."));

        var base64 = Convert.ToBase64String(CreateJpegImage(10, 10));
        var response = await client.PostAsJsonAsync("/api/analysis/food", new AnalyzeFoodRequest(base64));

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
    }
}
