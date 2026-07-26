using System.Text;
using System.Threading.RateLimiting;
using CaloriesTracking.Api.Configuration;
using CaloriesTracking.Api.Middleware;
using CaloriesTracking.Application;
using CaloriesTracking.Infrastructure;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Data.Seeders;
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

    var authLoginLimit = int.TryParse(builder.Configuration["RateLimiting:AuthLoginPermitLimit"], out var l) ? l : 5;
    var authRegisterLimit = int.TryParse(builder.Configuration["RateLimiting:AuthRegisterPermitLimit"], out var r) ? r : 3;
    var foodSearchLimit = int.TryParse(builder.Configuration["RateLimiting:FoodSearchPermitLimit"], out var f) ? f : 60;
    var geminiAnalysisLimit = int.TryParse(builder.Configuration["RateLimiting:GeminiAnalysisPermitLimit"], out var g) ? g : 5;

    options.AddPolicy("AuthLogin", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = authLoginLimit,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("AuthRegister", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = authRegisterLimit,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("FoodSearch", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = foodSearchLimit,
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
                PermitLimit = geminiAnalysisLimit,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            });
    });
});

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration, builder.Environment.EnvironmentName);

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
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

var app = builder.Build();

// Fail-fast: validate JWT key from the *final* configuration (after all
// overlays — including WebApplicationFactory test overrides — are applied).
var jwtKey = app.Configuration["Jwt:Key"];
if (string.IsNullOrWhiteSpace(jwtKey) || jwtKey.Length < 32)
{
    throw new InvalidOperationException(
        "Jwt:Key is missing or too short (min 32 chars). " +
        "Development: run 'dotnet user-secrets set \"Jwt:Key\" \"<your-32+-char-key>\"'. " +
        "Production: set the JWT__KEY environment variable.");
}

app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

await using (var scope = app.Services.CreateAsyncScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

    // Report case-insensitive user conflicts as a named diagnostic before the
    // unique indexes reject them with an opaque provider error. Detection only.
    await MigrationPreflight.EnsureNoCaseInsensitiveUserConflictsAsync(dbContext);

    // Dùng migrations thay cho EnsureCreated. DB cũ tạo bằng EnsureCreated không có
    // bảng __EFMigrationsHistory — xóa file calories.db cũ một lần rồi chạy lại.
    await dbContext.Database.MigrateAsync();

    // Detect data that would violate the unique indexes before importing more.
    // Throws a clear diagnostic naming the conflicting FdcIds; never mutates
    // or deletes the conflicting rows.
    await DatabaseSeeder.EnsureNoDuplicateFoodIdentitiesAsync(dbContext);

    // Seed USDA foods: ưu tiên SeedData cạnh binary (Docker), fallback về source tree (dev)
    var seedFolder = Path.Combine(AppContext.BaseDirectory, "SeedData");
    if (!Directory.Exists(seedFolder))
    {
        seedFolder = Path.Combine(Directory.GetCurrentDirectory(), "..", "CaloriesTracking.Infrastructure", "Data", "SeedData");
    }

    var seeder = scope.ServiceProvider.GetRequiredService<UsdaFoodSeeder>();
    await seeder.SeedAsync(seedFolder, app.Lifetime.ApplicationStopping);
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
