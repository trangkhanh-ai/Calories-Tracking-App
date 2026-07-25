using System.Text.Json;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.Extensions.Configuration;
using Moq;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace CaloriesTracking.Api.Tests.Security;

public class ImageValidationTests
{
    private readonly GeminiFoodAnalysisService _service;
    private readonly Mock<HttpMessageHandler> _httpMock;

    public ImageValidationTests()
    {
        _httpMock = new Mock<HttpMessageHandler>();
        var httpClient = new HttpClient(_httpMock.Object);

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
    public async Task AnalyzeAsync_WithOver20MillionPixels_ThrowsInvalidOperationException()
    {
        using var image = new Image<Rgba32>(5000, 4001); // 20,005,000 pixels
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);
        
        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("exceeds 20,000,000", ex.Message);
    }
}
