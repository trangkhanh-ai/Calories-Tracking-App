using System.Net;
using System.Net.Http.Json;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Exceptions;
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

public class ImageValidationTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;
    private readonly GeminiFoodAnalysisService _service;

    public ImageValidationTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;

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
    public async Task AnalyzeAsync_WithTextFile_ThrowsValidationAppException()
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes("This is not an image");

        var ex = await Assert.ThrowsAsync<ValidationAppException>(() =>
            _service.AnalyzeAsync(bytes));

        Assert.Contains("Invalid image format or content.", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithBmp_ThrowsUnsupportedMediaTypeAppException()
    {
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsBmp(ms);

        var ex = await Assert.ThrowsAsync<UnsupportedMediaTypeAppException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("bmp is not supported", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnalyzeAsync_WithOver8000Width_ThrowsPayloadTooLargeAppException()
    {
        using var image = new Image<Rgba32>(8001, 10);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var ex = await Assert.ThrowsAsync<PayloadTooLargeAppException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("exceed 8000x8000", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithOver8000Height_ThrowsPayloadTooLargeAppException()
    {
        using var image = new Image<Rgba32>(10, 8001);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var ex = await Assert.ThrowsAsync<PayloadTooLargeAppException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("exceed 8000x8000", ex.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_WithOver20MillionPixels_ThrowsPayloadTooLargeAppException()
    {
        using var image = new Image<Rgba32>(5000, 4001); // 20,005,000 pixels
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var ex = await Assert.ThrowsAsync<PayloadTooLargeAppException>(() => _service.AnalyzeAsync(ms.ToArray()));
        Assert.Contains("exceeds 20,000,000", ex.Message);
    }

    private static (GeminiFoodAnalysisService Service, Mock<HttpMessageHandler> HandlerMock) CreateServiceWithFakeResponse()
    {
        var httpMock = new Mock<HttpMessageHandler>();
        httpMock.Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(System.Text.Json.JsonSerializer.Serialize(new
                {
                    candidates = new[]
                    {
                        new
                        {
                            content = new
                            {
                                parts = new[]
                                {
                                    new
                                    {
                                        text = System.Text.Json.JsonSerializer.Serialize(new
                                        {
                                            food_detected = true,
                                            items = new[]
                                            {
                                                new
                                                {
                                                    name = "Phở Bò",
                                                    name_en = "Beef Pho",
                                                    serving_size = "1 tô",
                                                    calories = 450,
                                                    protein_g = 25.0,
                                                    carbs_g = 55.0,
                                                    fat_g = 12.0,
                                                    confidence = 0.95
                                                }
                                            },
                                            image_quality = "good",
                                            notes = "Nóng hổi"
                                        })
                                    }
                                }
                            }
                        }
                    }
                }))
            });

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { { "Gemini:ApiKey", "test-key" } })
            .Build();

        return (new GeminiFoodAnalysisService(new HttpClient(httpMock.Object), config), httpMock);
    }

    [Fact]
    public async Task AnalyzeAsync_WithValidJpeg_PassesValidationAndCallsGeminiOnce()
    {
        var (service, handlerMock) = CreateServiceWithFakeResponse();
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);

        var response = await service.AnalyzeAsync(ms.ToArray());

        Assert.NotNull(response);
        Assert.True(response.FoodDetected);
        Assert.Single(response.Items);
        Assert.Equal("Phở Bò", response.Items[0].Name);

        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Once(),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Fact]
    public async Task AnalyzeAsync_WithValidPng_PassesValidationAndCallsGeminiOnce()
    {
        var (service, handlerMock) = CreateServiceWithFakeResponse();
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsPng(ms);

        var response = await service.AnalyzeAsync(ms.ToArray());

        Assert.NotNull(response);
        Assert.True(response.FoodDetected);
        Assert.Single(response.Items);

        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Once(),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Fact]
    public async Task AnalyzeAsync_WithValidWebP_PassesValidationAndCallsGeminiOnce()
    {
        var (service, handlerMock) = CreateServiceWithFakeResponse();
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsWebp(ms);

        var response = await service.AnalyzeAsync(ms.ToArray());

        Assert.NotNull(response);
        Assert.True(response.FoodDetected);
        Assert.Single(response.Items);

        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Once(),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
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
