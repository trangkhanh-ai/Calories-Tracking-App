using System.Net;
using CaloriesTracking.Infrastructure.Data;

namespace CaloriesTracking.Api.Configuration;

public static class ProductionConfigurationValidator
{
    public static void Validate(IConfiguration configuration, string environmentName)
    {
        if (!string.Equals(environmentName, Environments.Production, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        NeonConnectionStringNormalizer.Normalize(
            configuration.GetConnectionString("DefaultConnection"));

        var jwtKey = configuration["Jwt:Key"];
        if (string.IsNullOrWhiteSpace(jwtKey) || jwtKey.Length < 32)
        {
            throw new InvalidOperationException(
                "Jwt:Key is missing or too short for production (minimum 32 characters).");
        }

        if (string.IsNullOrWhiteSpace(configuration["Gemini:ApiKey"]))
        {
            throw new InvalidOperationException(
                "Gemini:ApiKey is required in production.");
        }

        var allowedOrigins = configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
        if (allowedOrigins.Length == 0 || allowedOrigins.Any(origin => !IsSafeOrigin(origin)))
        {
            throw new InvalidOperationException(
                "Production CORS origins must be non-empty HTTPS origins without wildcards or loopback hosts.");
        }
    }

    private static bool IsSafeOrigin(string? origin)
    {
        if (string.IsNullOrWhiteSpace(origin) ||
            origin.Contains('*') ||
            origin.EndsWith('/'))
        {
            return false;
        }

        if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps ||
            string.IsNullOrWhiteSpace(uri.Host) ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            uri.AbsolutePath != "/" ||
            !string.IsNullOrEmpty(uri.Query) ||
            !string.IsNullOrEmpty(uri.Fragment))
        {
            return false;
        }

        if (string.Equals(uri.Host, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return !IPAddress.TryParse(uri.Host, out var address) || !IPAddress.IsLoopback(address);
    }
}
