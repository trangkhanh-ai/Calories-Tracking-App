using System.Net;
using System.Text.Json;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;
using Polly;
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

    [Fact]
    public async Task AnalyzeAsync_RetriesOn503AndSucceeds()
    {
        var handlerMock = new Mock<HttpMessageHandler>();
        
        handlerMock.Protected()
            .SetupSequence<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)) // Fail 1
            .ReturnsAsync(new HttpResponseMessage(HttpStatusCode.OK) // Success
            {
                Content = new StringContent(JsonSerializer.Serialize(new {
                    candidates = new[] { new { content = new { parts = new[] { new { text = "{ \"food_detected\": false, \"items\": [] }" } } } } }
                }))
            });

        var services = new ServiceCollection();
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { { "Gemini:ApiKey", "test-key" } })
            .Build();
            
        services.AddSingleton<IConfiguration>(config);
        
        // Use the exact resilience setup from DI
        services.AddHttpClient<IFoodAnalysisService, GeminiFoodAnalysisService>()
            .ConfigurePrimaryHttpMessageHandler(() => handlerMock.Object)
            .AddResilienceHandler("gemini-retry", builder =>
            {
                builder.AddRetry(new Microsoft.Extensions.Http.Resilience.HttpRetryStrategyOptions
                {
                    MaxRetryAttempts = 2,
                    BackoffType = Polly.DelayBackoffType.Constant, // Constant for fast tests
                    Delay = TimeSpan.FromMilliseconds(10), // Short delay
                    UseJitter = false,
                    ShouldHandle = args =>
                    {
                        if (args.Outcome.Exception is HttpRequestException) return new ValueTask<bool>(true);
                        if (args.Outcome.Result is HttpResponseMessage response)
                        {
                            var status = (int)response.StatusCode;
                            if (status == 429 || status == 502 || status == 503 || status == 504)
                                return new ValueTask<bool>(true);
                        }
                        return new ValueTask<bool>(false);
                    }
                });
            });

        var provider = services.BuildServiceProvider();
        var service = provider.GetRequiredService<IFoodAnalysisService>();

        var result = await service.AnalyzeAsync(CreateValidJpeg());
        
        Assert.False(result.FoodDetected);
        handlerMock.Protected().Verify(
            "SendAsync",
            Times.Exactly(2),
            ItExpr.IsAny<HttpRequestMessage>(),
            ItExpr.IsAny<CancellationToken>());
    }
}
