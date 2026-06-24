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

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

var jwtSection = builder.Configuration.GetSection("Jwt");
var signingKey = jwtSection["Key"] ?? "DevelopmentOnlySuperSecretKey_ChangeMe_123456789";

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
    await dbContext.Database.EnsureCreatedAsync();

    try
    {
        await dbContext.Database.ExecuteSqlRawAsync("ALTER TABLE MealItems ADD COLUMN MealType TEXT NOT NULL DEFAULT 'Snack';");
    }
    catch { /* Ignore if column already exists */ }

    if (!await dbContext.Users.AnyAsync())
    {
        dbContext.Users.Add(new CaloriesTracking.Domain.Entities.User
        {
            Username = "testuser",
            Email = "test@example.com",
            PasswordHash = "dummyhash",
            DisplayName = "Test User"
        });
        await dbContext.SaveChangesAsync();
    }

    // Seed USDA foods
    var seedFolder = Path.Combine(Directory.GetCurrentDirectory(), "..", "CaloriesTracking.Infrastructure", "Data", "SeedData");
    await CaloriesTracking.Infrastructure.Data.Seeders.DatabaseSeeder.SeedUsdaFoodsAsync(dbContext, seedFolder);
}

app.UseHttpsRedirection();
app.UseCors("AllowAll");
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
