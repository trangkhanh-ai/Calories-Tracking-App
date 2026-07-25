using System.Text;
using System.Threading.RateLimiting;
using CaloriesTracking.Api.Configuration;
using CaloriesTracking.Application;
using CaloriesTracking.Infrastructure;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

ProductionConfigurationValidator.Validate(
    builder.Configuration,
    builder.Environment.EnvironmentName);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

// CORS: chỉ cho phép các origin trong cấu hình (Cors:AllowedOrigins / env CORS__ALLOWEDORIGINS__0...)
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(options =>
{
    options.AddPolicy("Frontend", policy =>
    {
        policy.WithOrigins(allowedOrigins)
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = async (context, token) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        context.HttpContext.Response.ContentType = "application/json";

        if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
        {
            context.HttpContext.Response.Headers.RetryAfter =
                ((int)retryAfter.TotalSeconds).ToString();
        }

        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            status = 429,
            title = "Too many requests",
            detail = "Please wait before trying again."
        }, token);
    };

    options.AddPolicy("AuthLogin", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 5,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("AuthRegister", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 3,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("FoodSearch", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 60,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("GeminiAnalysis", httpContext =>
    {
        var userId = httpContext.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
            ?? httpContext.User.FindFirst("sub")?.Value;
        var partitionKey = !string.IsNullOrWhiteSpace(userId)
            ? $"user_{userId}"
            : (httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown_ip");

        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: partitionKey,
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 5,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            });
    });
});

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration, builder.Environment.EnvironmentName);

var jwtSection = builder.Configuration.GetSection("Jwt");
var signingKey = jwtSection["Key"];
if (string.IsNullOrWhiteSpace(signingKey) || signingKey.Length < 32)
{
    throw new InvalidOperationException(
        "Jwt:Key is missing or too short (min 32 chars). Set it via appsettings.Development.json (dev) or the JWT__KEY environment variable (production).");
}

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer();

builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IConfiguration>((options, configuration) =>
    {
        var jwtSection = configuration.GetSection("Jwt");
        var signingKey = jwtSection["Key"] ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(signingKey))
        {
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidateAudience = true,
                ValidateIssuerSigningKey = true,
                ValidIssuer = jwtSection["Issuer"],
                ValidAudience = jwtSection["Audience"],
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),
                NameClaimType = System.Security.Claims.ClaimTypes.NameIdentifier
            };
        }
    });

builder.Services.AddAuthorization();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

await using (var scope = app.Services.CreateAsyncScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    // Dùng migrations thay cho EnsureCreated. DB cũ tạo bằng EnsureCreated không có
    // bảng __EFMigrationsHistory — xóa file calories.db cũ một lần rồi chạy lại.
    await dbContext.Database.MigrateAsync();

    // Seed USDA foods: ưu tiên SeedData cạnh binary (Docker), fallback về source tree (dev)
    var seedFolder = Path.Combine(AppContext.BaseDirectory, "SeedData");
    if (!Directory.Exists(seedFolder))
    {
        seedFolder = Path.Combine(Directory.GetCurrentDirectory(), "..", "CaloriesTracking.Infrastructure", "Data", "SeedData");
    }
    await CaloriesTracking.Infrastructure.Data.Seeders.DatabaseSeeder.SeedUsdaFoodsAsync(dbContext, seedFolder);
}

app.UseHttpsRedirection();
app.UseCors("Frontend");
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapGet("/health/live", HealthEndpoints.Liveness);
app.MapGet("/health", HealthEndpoints.ReadinessAsync);

app.MapControllers();

app.Run();

public partial class Program { }

public static class HealthEndpoints
{
    public static IResult Liveness() =>
        Results.Ok(new { status = "ok" });

    public static async Task<IResult> ReadinessAsync(
        ApplicationDbContext dbContext,
        CancellationToken cancellationToken)
    {
        try
        {
            return await dbContext.Database.CanConnectAsync(cancellationToken)
                ? Results.Ok(new { status = "ok" })
                : Unavailable();
        }
        catch (Exception)
        {
            return Unavailable();
        }
    }

    private static IResult Unavailable() =>
        Results.Json(
            new { status = "unavailable" },
            statusCode: StatusCodes.Status503ServiceUnavailable);
}
