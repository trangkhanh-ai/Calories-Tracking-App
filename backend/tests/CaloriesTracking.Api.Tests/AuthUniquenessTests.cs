using CaloriesTracking.Api.Tests.Support;
using CaloriesTracking.Application.Dtos.Auth;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Application.Services;
using CaloriesTracking.Infrastructure.Data;
using CaloriesTracking.Infrastructure.Repositories;
using Microsoft.Extensions.Configuration;

namespace CaloriesTracking.Api.Tests;

/// <summary>
/// Exercises uniqueness against a real SQLite database so the unique indexes —
/// not just the application pre-check — are what the assertions observe.
/// </summary>
public sealed class AuthUniquenessTests
{
    private const string TestJwtKey = "unit_test_signing_key_that_is_long_enough_1234567890";

    [Fact]
    public async Task Register_WhenUsernameIsDuplicated_Throws409Conflict()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();

        await RegisterAsync(database, "duy", "duy@example.com");

        var conflict = await Assert.ThrowsAsync<ConflictAppException>(
            () => RegisterAsync(database, "duy", "other@example.com"));

        Assert.Equal("Username is already taken.", conflict.Message);
    }

    [Fact]
    public async Task Register_WhenEmailIsDuplicated_Throws409Conflict()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();

        await RegisterAsync(database, "duy", "duy@example.com");

        var conflict = await Assert.ThrowsAsync<ConflictAppException>(
            () => RegisterAsync(database, "other", "duy@example.com"));

        Assert.Equal("Email is already registered.", conflict.Message);
    }

    [Theory]
    [InlineData("duy", "DUY")]
    [InlineData("duy", "Duy")]
    [InlineData("DuyNguyen", "dUYnGUYEN")]
    public async Task Register_WhenUsernameDiffersOnlyByCase_Throws409Conflict(string first, string second)
    {
        await using var database = await SqliteTestDatabase.CreateAsync();

        await RegisterAsync(database, first, $"{first}@example.com");

        await Assert.ThrowsAsync<ConflictAppException>(
            () => RegisterAsync(database, second, "different@example.com"));
    }

    [Theory]
    [InlineData("duy@example.com", "DUY@EXAMPLE.COM")]
    [InlineData("duy@example.com", "Duy@Example.Com")]
    public async Task Register_WhenEmailDiffersOnlyByCase_Throws409Conflict(string first, string second)
    {
        await using var database = await SqliteTestDatabase.CreateAsync();

        await RegisterAsync(database, "first", first);

        await Assert.ThrowsAsync<ConflictAppException>(
            () => RegisterAsync(database, "second", second));
    }

    [Fact]
    public async Task Register_WhenTwoRequestsRaceOnTheSameUsername_ExactlyOneSucceeds()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();

        // Two independent contexts stand in for two concurrent requests. Both
        // pass the advisory pre-check; only the unique index can break the tie.
        await using var contextA = database.CreateContext();
        await using var contextB = database.CreateContext();

        var serviceA = CreateService(contextA);
        var serviceB = CreateService(contextB);

        var request = new RegisterRequest
        {
            Username = "racer",
            Email = "racer@example.com",
            Password = "Password123!",
            DisplayName = "Racer"
        };

        var results = await Task.WhenAll(
            CaptureAsync(() => serviceA.RegisterAsync(request)),
            CaptureAsync(() => serviceB.RegisterAsync(new RegisterRequest
            {
                Username = "racer",
                Email = "racer2@example.com",
                Password = "Password123!",
                DisplayName = "Racer Two"
            })));

        var successes = results.Count(r => r is null);
        var conflicts = results.Count(r => r is ConflictAppException);

        Assert.Equal(1, successes);
        Assert.Equal(1, conflicts);

        // And the database really does hold exactly one row.
        await using var verifyContext = database.CreateContext();
        Assert.Single(verifyContext.Users.Where(u => u.NormalizedUsername == "RACER"));
    }

    [Fact]
    public async Task Register_ConflictMessageNeverLeaksSqlOrConstraintNames()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await RegisterAsync(database, "duy", "duy@example.com");

        var conflict = await Assert.ThrowsAsync<ConflictAppException>(
            () => RegisterAsync(database, "duy", "other@example.com"));

        foreach (var forbidden in new[] { "SQLite", "UNIQUE constraint", "IX_Users", "INSERT", "Data Source" })
        {
            Assert.DoesNotContain(forbidden, conflict.Message, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task Register_PersistsOriginalCasingForDisplay()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();

        await RegisterAsync(database, "DuyNguyen", "Duy@Example.com");

        await using var context = database.CreateContext();
        var user = Assert.Single(context.Users.ToList());

        // Display values keep their original casing; only the normalized
        // columns are folded.
        Assert.Equal("DuyNguyen", user.Username);
        Assert.Equal("duy@example.com", user.Email);
        Assert.Equal("DUYNGUYEN", user.NormalizedUsername);
        Assert.Equal("DUY@EXAMPLE.COM", user.NormalizedEmail);
    }

    [Fact]
    public async Task Login_IsCaseInsensitiveOnUsernameAndEmail()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await RegisterAsync(database, "DuyNguyen", "Duy@Example.com");

        await using var context = database.CreateContext();
        var service = CreateService(context);

        var byUsername = await service.LoginAsync(new LoginRequest
        {
            Username = "dUYnGUYEN",
            Password = "Password123!"
        });

        var byEmail = await service.LoginAsync(new LoginRequest
        {
            Username = "DUY@EXAMPLE.COM",
            Password = "Password123!"
        });

        Assert.Equal("DuyNguyen", byUsername.Username);
        Assert.Equal("DuyNguyen", byEmail.Username);
    }

    [Fact]
    public async Task Login_WhenUserIsUnknown_UsesTheSameMessageAsAWrongPassword()
    {
        await using var database = await SqliteTestDatabase.CreateAsync();
        await RegisterAsync(database, "duy", "duy@example.com");

        await using var context = database.CreateContext();
        var service = CreateService(context);

        var unknownUser = await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => service.LoginAsync(new LoginRequest { Username = "nobody", Password = "Password123!" }));

        var wrongPassword = await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => service.LoginAsync(new LoginRequest { Username = "duy", Password = "WrongPassword1" }));

        // Identical text is what prevents account enumeration.
        Assert.Equal(unknownUser.Message, wrongPassword.Message);
        Assert.Equal("Invalid username or password.", unknownUser.Message);
    }

    private static async Task RegisterAsync(SqliteTestDatabase database, string username, string email)
    {
        await using var context = database.CreateContext();
        var service = CreateService(context);

        await service.RegisterAsync(new RegisterRequest
        {
            Username = username,
            Email = email,
            Password = "Password123!",
            DisplayName = "Test User"
        });
    }

    private static AuthService CreateService(ApplicationDbContext context)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Key"] = TestJwtKey,
                ["Jwt:Issuer"] = "CaloriesTracking.Tests",
                ["Jwt:Audience"] = "CaloriesTracking.Tests"
            })
            .Build();

        return new AuthService(
            new UserRepository(context),
            configuration,
            new UniqueConstraintTranslator());
    }

    private static async Task<Exception?> CaptureAsync(Func<Task> action)
    {
        try
        {
            await action();
            return null;
        }
        catch (Exception exception)
        {
            return exception;
        }
    }
}
