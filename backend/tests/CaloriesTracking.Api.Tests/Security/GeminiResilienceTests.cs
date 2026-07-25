using System.Net;
using System.Text.Json;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Infrastructure;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Moq;
using Moq.Protected;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace CaloriesTracking.Api.Tests.Security;

public class GeminiResilienceTests
{
    private byte[] CreateValidJpeg()
    {
        using var image = new Image<Rgba32>(10, 10);
        using var ms = new MemoryStream();
        image.SaveAsJpeg(ms);
        return ms.ToArray();
    }

    private ServiceProvider CreateTestServiceProvider(Mock<HttpMessageHandler> handlerMock)
    {
        var services = new ServiceCollection();
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "Gemini:ApiKey", "test-key" },
                { "Gemini:Model", "gemini-2.5-flash" }
            })
            .Build();

        services.AddSingleton<IConfiguration>(config);
        
        // Use production extension method with fast retry/timeout for tests
        services.AddGeminiClient(
            retryDelay: TimeSpan.FromMilliseconds(1),
            timeout: TimeSpan.FromMilliseconds(500))
            .ConfigurePrimaryHttpMessageHandler(() => handlerMock.Object);

        return services.BuildServiceProvider();
    }

    [Fact]
    public async Task AnalyzeAsync_503ThenSuccess_RetriesAndSucceeds()
    {
        var handlerMock = new Mock<HttpMessageHandler>();
        handlerMock.Protected()
            .SetupSequence<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable))
            .ReturnsAsync(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(JsonSerializer.Serialize(new
                {
                    candidates = new[] { new { content = new { parts = new[] { new { text = "{ \"food_detected\": false, \"items\": [] }" } } } } }
                }))
            });

        var provider = CreateTestServiceProvider(handlerMock);
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        var result = await service.AnalyzeAsync(CreateValidJpeg());

        Assert.False(result.FoodDetected);
        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Exactly(2),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Fact]
    public async Task AnalyzeAsync_429ThenSuccess_RetriesAndSucceeds()
    {
        var handlerMock = new Mock<HttpMessageHandler>();
        handlerMock.Protected()
            .SetupSequence<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(new HttpResponseMessage((HttpStatusCode)429))
            .ReturnsAsync(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(JsonSerializer.Serialize(new
                {
                    candidates = new[] { new { content = new { parts = new[] { new { text = "{ \"food_detected\": false, \"items\": [] }" } } } } }
                }))
            });

        var provider = CreateTestServiceProvider(handlerMock);
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        var result = await service.AnalyzeAsync(CreateValidJpeg());

        Assert.False(result.FoodDetected);
        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Exactly(2),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Fact]
    public async Task AnalyzeAsync_502Continuous_StopsAfter2Retries()
    {
        var handlerMock = new Mock<HttpMessageHandler>();
        handlerMock.Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(() => new HttpResponseMessage(HttpStatusCode.BadGateway));

        var provider = CreateTestServiceProvider(handlerMock);
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        var ex = await Assert.ThrowsAsync<GeminiUnavailableException>(() => service.AnalyzeAsync(CreateValidJpeg()));

        Assert.Equal(HttpStatusCode.BadGateway, ex.StatusCode);
        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Exactly(3), // 1 initial + 2 retries
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Fact]
    public async Task AnalyzeAsync_504Continuous_StopsAfter2Retries()
    {
        var handlerMock = new Mock<HttpMessageHandler>();
        handlerMock.Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(() => new HttpResponseMessage(HttpStatusCode.GatewayTimeout));

        var provider = CreateTestServiceProvider(handlerMock);
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        var ex = await Assert.ThrowsAsync<GeminiUnavailableException>(() => service.AnalyzeAsync(CreateValidJpeg()));

        Assert.Equal(HttpStatusCode.GatewayTimeout, ex.StatusCode);
        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Exactly(3), // 1 initial + 2 retries
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest)]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.Forbidden)]
    public async Task AnalyzeAsync_ClientError_DoesNotRetry(HttpStatusCode statusCode)
    {
        var handlerMock = new Mock<HttpMessageHandler>();
        handlerMock.Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(new HttpResponseMessage(statusCode));

        var provider = CreateTestServiceProvider(handlerMock);
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        var ex = await Assert.ThrowsAsync<GeminiException>(() => service.AnalyzeAsync(CreateValidJpeg()));

        Assert.Equal(statusCode, ex.StatusCode);
        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Once(),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Fact]
    public async Task AnalyzeAsync_Cancellation_DoesNotContinueRetry()
    {
        var cts = new CancellationTokenSource();
        var handlerMock = new Mock<HttpMessageHandler>();
        handlerMock.Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .Callback(() => cts.Cancel())
            .ThrowsAsync(new OperationCanceledException(cts.Token));

        var provider = CreateTestServiceProvider(handlerMock);
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        await Assert.ThrowsAsync<OperationCanceledException>(() => service.AnalyzeAsync(CreateValidJpeg(), cts.Token));

        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Once(),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }

    [Fact]
    public async Task AnalyzeAsync_MalformedJson_DoesNotRetry()
    {
        var handlerMock = new Mock<HttpMessageHandler>();
        handlerMock.Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("{ malformed json }")
            });

        var provider = CreateTestServiceProvider(handlerMock);
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        var ex = await Assert.ThrowsAsync<GeminiException>(() => service.AnalyzeAsync(CreateValidJpeg()));

        Assert.Contains("Malformed", ex.Message);
        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Once(),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }
}
