using System.Text;
using CaloriesTracking.Application;
using CaloriesTracking.Infrastructure;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

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

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

var jwtSection = builder.Configuration.GetSection("Jwt");
var signingKey = jwtSection["Key"];
if (string.IsNullOrWhiteSpace(signingKey) || signingKey.Length < 32)
{
    throw new InvalidOperationException(
        "Jwt:Key is missing or too short (min 32 chars). Set it via appsettings.Development.json (dev) or the JWT__KEY environment variable (production).");
}

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
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

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapControllers();

app.Run();
