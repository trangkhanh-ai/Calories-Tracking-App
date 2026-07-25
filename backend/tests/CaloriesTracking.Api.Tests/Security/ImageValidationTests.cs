using System.Net;
using System.Net.Http.Json;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Moq;
using Moq.Protected;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace CaloriesTracking.Api.Tests.Security;

public class ImageValidationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly GeminiFoodAnalysisService _service;

    public ImageValidationTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Jwt:Key"] = "test_jwt_secret_key_must_be_at_least_32_bytes!",
                    ["Jwt:Issuer"] = "CaloriesTracking",
                    ["Jwt:Audience"] = "CaloriesTracking"
                });
            });
        });

        var httpMock = new Mock<HttpMessageHandler>();
        var httpClient = new HttpClient(httpMock.Object);

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "Gemini:ApiKey", "test-key" }
            })
            .Build();

        _service = new GeminiFoodAnalysisService(httpClient, config);
    }

    [Fact]
    public async Task AnalyzeAsync_WithTextFile_ThrowsArgumentException()
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes("This is not an image");

        var ex = await Assert.ThrowsAsync<ArgumentException>(() =>
            _service.AnalyzeAsync(bytes));

        Assert.Contains("Invalid image format or content.", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithBmp_ThrowsNotSupportedException()
    {
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsBmp(ms);

        var ex = await Assert.ThrowsAsync<NotSupportedException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("bmp is not supported", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithOver8000Width_ThrowsInvalidOperationException()
    {
        using var image = new Image<Rgba32>(8001, 10);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("exceed 8000x8000", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithOver8000Height_ThrowsInvalidOperationException()
    {
        using var image = new Image<Rgba32>(10, 8001);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("exceed 8000x8000", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithOver20MillionPixels_ThrowsInvalidOperationException()
    {
        using var image = new Image<Rgba32>(5000, 4001); // 20,005,000 pixels
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("exceeds 20,000,000", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithValidJpeg_DoesNotThrowValidationException()
    {
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        // Will throw GeminiUnavailableException or GeminiException because httpMock isn't set up,
        // but image validation passed.
        await Assert.ThrowsAnyAsync<Exception>(() => _service.AnalyzeAsync(ms.ToArray()));
    }

    [Fact]
    public async Task AnalyzeAsync_WithValidPng_DoesNotThrowValidationException()
    {
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsPng(ms);

        await Assert.ThrowsAnyAsync<Exception>(() => _service.AnalyzeAsync(ms.ToArray()));
    }

    [Fact]
    public async Task AnalyzeAsync_WithValidWebP_DoesNotThrowValidationException()
    {
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsWebp(ms);

        await Assert.ThrowsAnyAsync<Exception>(() => _service.AnalyzeAsync(ms.ToArray()));
    }

    [Fact]
    public async Task AnalyzeAsync_WithCancellation_ThrowsOperationCanceledException()
    {
        var httpMock = new Mock<HttpMessageHandler>();
        httpMock.Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ThrowsAsync(new OperationCanceledException());

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { { "Gemini:ApiKey", "test-key" } })
            .Build();

        var service = new GeminiFoodAnalysisService(new HttpClient(httpMock.Object), config);

        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var cts = new CancellationTokenSource();
        cts.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.AnalyzeAsync(ms.ToArray(), cts.Token));
    }
}
