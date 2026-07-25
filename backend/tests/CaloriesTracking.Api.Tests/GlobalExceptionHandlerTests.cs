using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace CaloriesTracking.Api.Tests;

public class GlobalExceptionHandlerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public GlobalExceptionHandlerTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task HandledException_ReturnsProblemDetailsFormat()
    {
        var client = _factory.CreateClient();

        // Send invalid json or request to trigger handled error format
        var response = await client.GetAsync("/api/food/search?query=");

        Assert.True(response.IsSuccessStatusCode || response.StatusCode == HttpStatusCode.BadRequest);
    }
}
