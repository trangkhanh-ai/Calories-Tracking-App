using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CaloriesTracking.Api.Tests;

public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    public const string TestJwtKey = "test_jwt_secret_key_must_be_at_least_32_bytes!";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Key"] = TestJwtKey,
                ["Jwt:Issuer"] = "CaloriesTracking.Api",
                ["Jwt:Audience"] = "CaloriesTracking.Client",
                ["Gemini:ApiKey"] = "test_gemini_api_key_placeholder",
                ["RateLimiting:AuthLoginPermitLimit"] = "1000",
                ["RateLimiting:AuthRegisterPermitLimit"] = "1000",
                ["RateLimiting:FoodSearchPermitLimit"] = "1000",
                ["RateLimiting:GeminiAnalysisPermitLimit"] = "1000"
            });
        });
    }
}
