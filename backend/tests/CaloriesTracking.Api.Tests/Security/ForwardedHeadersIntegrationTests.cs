using System.Net;
using System.Net.Http.Json;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.HttpsPolicy;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace CaloriesTracking.Api.Tests.Security;

public sealed class ForwardedHeadersIntegrationTests
{
    internal const string FrontendOrigin = "http://localhost:54321";
    private const string ImmediateProxyIp = "10.0.0.42";

    [Fact]
    public async Task ProxiedHttpsRequest_WhenProxyModeEnabled_DoesNotRedirect()
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: true);
        using var client = CreateClient(factory);
        using var request = CreateProxyRequest(HttpMethod.Get, "/health/live", "198.51.100.10");

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null(response.Headers.Location);
    }

    [Fact]
    public async Task ForwardedProtoHttps_WhenProxyModeEnabled_SetsRequestSchemeToHttps()
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: true);
        using var client = CreateClient(factory);
        using var request = CreateProxyRequest(HttpMethod.Get, "/health/live", "198.51.100.10");

        using var response = await client.SendAsync(request);

        Assert.Equal("https", GetProbeHeader(response, ForwardedHeaderProbeStartupFilter.SchemeHeader));
    }

    [Fact]
    public async Task ForwardedHeaders_WhenDevelopmentFlagIsFalse_AreNotTrusted()
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: false);
        using var client = CreateClient(factory);
        using var request = CreateProxyRequest(HttpMethod.Get, "/health/live", "198.51.100.10");

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.TemporaryRedirect, response.StatusCode);
        Assert.Equal("http", GetProbeHeader(response, ForwardedHeaderProbeStartupFilter.SchemeHeader));
        Assert.Equal(ImmediateProxyIp, GetProbeHeader(response, ForwardedHeaderProbeStartupFilter.RemoteIpHeader));
        Assert.Equal("https", response.Headers.Location?.Scheme);
    }

    [Theory]
    [InlineData("/api/auth/login")]
    [InlineData("/api/auth/register")]
    public async Task AuthRateLimits_UseSeparateForwardedClientIpPartitions(string path)
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: true, authPermitLimit: 1);
        using var client = CreateClient(factory);

        using var firstA = CreateProxyRequest(HttpMethod.Post, path, "198.51.100.10", new { });
        using var secondA = CreateProxyRequest(HttpMethod.Post, path, "198.51.100.10", new { });
        using var firstB = CreateProxyRequest(HttpMethod.Post, path, "198.51.100.11", new { });

        using var firstAResponse = await client.SendAsync(firstA);
        using var secondAResponse = await client.SendAsync(secondA);
        using var firstBResponse = await client.SendAsync(firstB);

        Assert.NotEqual(HttpStatusCode.TooManyRequests, firstAResponse.StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, secondAResponse.StatusCode);
        Assert.NotEqual(HttpStatusCode.TooManyRequests, firstBResponse.StatusCode);
    }

    [Fact]
    public async Task MalformedForwardedFor_DoesNotCrashOrReplaceRemoteAddress()
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: true);
        using var client = CreateClient(factory);
        using var request = CreateProxyRequest(HttpMethod.Get, "/health/live", "not-an-ip");

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(ImmediateProxyIp, GetProbeHeader(response, ForwardedHeaderProbeStartupFilter.RemoteIpHeader));
    }

    [Fact]
    public async Task ForwardedHeaderChain_ProcessesOnlyOneHop()
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: true);
        using var client = CreateClient(factory);
        using var request = new HttpRequestMessage(HttpMethod.Get, "/health/live");
        request.Headers.TryAddWithoutValidation("X-Forwarded-For", "198.51.100.10, 203.0.113.20");
        request.Headers.TryAddWithoutValidation("X-Forwarded-Proto", "http, https");

        using var response = await client.SendAsync(request);
        var options = factory.Services.GetRequiredService<IOptions<ForwardedHeadersOptions>>().Value;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, options.ForwardLimit);
        Assert.Equal("203.0.113.20", GetProbeHeader(response, ForwardedHeaderProbeStartupFilter.RemoteIpHeader));
        Assert.Equal("https", GetProbeHeader(response, ForwardedHeaderProbeStartupFilter.SchemeHeader));
    }

    [Theory]
    [InlineData("/health/live")]
    [InlineData("/health")]
    public async Task HealthEndpoints_WorkBehindSimulatedProxy(string path)
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: true);
        using var client = CreateClient(factory);
        using var request = CreateProxyRequest(HttpMethod.Get, path, "198.51.100.10");

        using var response = await client.SendAsync(request);
        var payload = await response.Content.ReadFromJsonAsync<HealthPayload>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("ok", payload?.Status);
    }

    [Fact]
    public async Task AuthorizationAndCors_WorkBehindSimulatedProxy()
    {
        using var factory = new ForwardedHeadersWebApplicationFactory(behindProxy: true);
        using var client = CreateClient(factory);

        using var protectedRequest = CreateProxyRequest(HttpMethod.Get, "/api/profile/me", "198.51.100.10");
        protectedRequest.Headers.TryAddWithoutValidation("Origin", FrontendOrigin);
        using var protectedResponse = await client.SendAsync(protectedRequest);

        Assert.Equal(HttpStatusCode.Unauthorized, protectedResponse.StatusCode);

        using var corsRequest = CreateProxyRequest(HttpMethod.Get, "/health/live", "198.51.100.10");
        corsRequest.Headers.TryAddWithoutValidation("Origin", FrontendOrigin);
        using var corsResponse = await client.SendAsync(corsRequest);

        Assert.Equal(HttpStatusCode.OK, corsResponse.StatusCode);
        Assert.Equal(FrontendOrigin, GetHeader(corsResponse, "Access-Control-Allow-Origin"));

        using var preflight = CreateProxyRequest(HttpMethod.Options, "/api/profile/me", "198.51.100.10");
        preflight.Headers.TryAddWithoutValidation("Origin", FrontendOrigin);
        preflight.Headers.TryAddWithoutValidation("Access-Control-Request-Method", "GET");
        preflight.Headers.TryAddWithoutValidation("Access-Control-Request-Headers", "authorization");
        using var preflightResponse = await client.SendAsync(preflight);

        Assert.Equal(HttpStatusCode.NoContent, preflightResponse.StatusCode);
        Assert.Equal(FrontendOrigin, GetHeader(preflightResponse, "Access-Control-Allow-Origin"));
        Assert.Contains("GET", GetHeader(preflightResponse, "Access-Control-Allow-Methods"));
        Assert.Contains("authorization", GetHeader(preflightResponse, "Access-Control-Allow-Headers"), StringComparison.OrdinalIgnoreCase);
    }

    private static HttpClient CreateClient(WebApplicationFactory<Program> factory) =>
        factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false,
            BaseAddress = new Uri("http://localhost")
        });

    private static HttpRequestMessage CreateProxyRequest(
        HttpMethod method,
        string path,
        string forwardedFor,
        object? body = null)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.TryAddWithoutValidation("X-Forwarded-For", forwardedFor);
        request.Headers.TryAddWithoutValidation("X-Forwarded-Proto", "https");
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }

        return request;
    }

    private static string GetProbeHeader(HttpResponseMessage response, string name) =>
        GetHeader(response, name);

    private static string GetHeader(HttpResponseMessage response, string name)
    {
        Assert.True(response.Headers.TryGetValues(name, out var values), $"Missing response header {name}.");
        return Assert.Single(values);
    }

    private sealed record HealthPayload(string Status);
}

internal sealed class ForwardedHeadersWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly bool _behindProxy;
    private readonly int _authPermitLimit;
    private readonly string _databasePath = Path.Combine(
        Path.GetTempPath(),
        $"calories-proxy-tests-{Guid.NewGuid():N}.db");

    public ForwardedHeadersWebApplicationFactory(bool behindProxy, int authPermitLimit = 1000)
    {
        _behindProxy = behindProxy;
        _authPermitLimit = authPermitLimit;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = $"Data Source={_databasePath};Pooling=False",
                ["Jwt:Key"] = CustomWebApplicationFactory.TestJwtKey,
                ["Jwt:Issuer"] = "CaloriesTracking.Api",
                ["Jwt:Audience"] = "CaloriesTracking.Client",
                ["Gemini:ApiKey"] = "test_gemini_api_key_placeholder",
                ["Cors:AllowedOrigins:0"] = ForwardedHeadersIntegrationTests.FrontendOrigin,
                ["Hosting:BehindTlsTerminatingProxy"] = _behindProxy.ToString(),
                ["Seeding:Enabled"] = "false",
                ["RateLimiting:AuthLoginPermitLimit"] = _authPermitLimit.ToString(),
                ["RateLimiting:AuthRegisterPermitLimit"] = _authPermitLimit.ToString(),
                ["RateLimiting:FoodSearchPermitLimit"] = "1000",
                ["RateLimiting:GeminiAnalysisPermitLimit"] = "1000"
            });
        });
        builder.ConfigureServices(services =>
        {
            services.Configure<HttpsRedirectionOptions>(options => options.HttpsPort = 443);
            services.AddSingleton<IStartupFilter, ForwardedHeaderProbeStartupFilter>();
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (!disposing)
        {
            return;
        }

        foreach (var path in Directory.EnumerateFiles(
                     Path.GetDirectoryName(_databasePath)!,
                     Path.GetFileName(_databasePath) + "*"))
        {
            try
            {
                File.Delete(path);
            }
            catch (IOException)
            {
                // TestServer can release its final SQLite handle just after
                // factory disposal on Windows; the OS temp directory remains
                // the fallback cleanup boundary.
            }
        }
    }
}

internal sealed class ForwardedHeaderProbeStartupFilter : IStartupFilter
{
    public const string SchemeHeader = "X-Test-Observed-Scheme";
    public const string RemoteIpHeader = "X-Test-Observed-Remote-Ip";

    public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
    {
        app.Use(async (context, nextMiddleware) =>
        {
            context.Connection.RemoteIpAddress = IPAddress.Parse("10.0.0.42");
            context.Response.OnStarting(() =>
            {
                context.Response.Headers[SchemeHeader] = context.Request.Scheme;
                context.Response.Headers[RemoteIpHeader] = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
                return Task.CompletedTask;
            });

            await nextMiddleware();
        });

        next(app);
    };
}
