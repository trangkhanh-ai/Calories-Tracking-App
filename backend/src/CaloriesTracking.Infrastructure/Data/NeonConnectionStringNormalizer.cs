using Npgsql;

namespace CaloriesTracking.Infrastructure.Data;

public static class NeonConnectionStringNormalizer
{
    public static string Normalize(string? connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("A PostgreSQL connection string is required.");
        }

        var trimmed = connectionString.Trim();
        NpgsqlConnectionStringBuilder builder;

        if (Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) &&
            uri.Scheme is "postgres" or "postgresql")
        {
            builder = FromUri(uri);
        }
        else
        {
            try
            {
                builder = new NpgsqlConnectionStringBuilder(trimmed);
            }
            catch (ArgumentException exception)
            {
                throw new InvalidOperationException(
                    "The configured database connection must be a valid PostgreSQL connection string.",
                    exception);
            }
        }

        if (string.IsNullOrWhiteSpace(builder.Host) ||
            string.IsNullOrWhiteSpace(builder.Database) ||
            string.IsNullOrWhiteSpace(builder.Username))
        {
            throw new InvalidOperationException(
                "The PostgreSQL connection string must include host, database, and username values.");
        }

        var hasExplicitSslMode = builder.ShouldSerialize("SSL Mode");
        if (hasExplicitSslMode)
        {
            if (builder.SslMode is SslMode.Disable or SslMode.Allow or SslMode.Prefer)
            {
                throw new InvalidOperationException(
                    "The PostgreSQL connection must keep secure TLS enabled; sslmode=disable, allow, and prefer are not allowed.");
            }
        }
        else
        {
            builder.SslMode = SslMode.Require;
        }

        var hasExplicitChannelBinding = builder.ShouldSerialize("Channel Binding");
        if (hasExplicitChannelBinding && builder.ChannelBinding != ChannelBinding.Require)
        {
            throw new InvalidOperationException(
                "PostgreSQL channel binding must be set to Require; Prefer and Disable are not allowed.");
        }

        builder.ChannelBinding = ChannelBinding.Require;

        return builder.ConnectionString;
    }

    private static NpgsqlConnectionStringBuilder FromUri(Uri uri)
    {
        var userInfo = uri.UserInfo.Split(':', 2);
        if (userInfo.Length == 0 || string.IsNullOrWhiteSpace(userInfo[0]))
        {
            throw new InvalidOperationException(
                "The PostgreSQL connection URI must include a username.");
        }

        var database = Uri.UnescapeDataString(uri.AbsolutePath.TrimStart('/'));
        if (string.IsNullOrWhiteSpace(database))
        {
            throw new InvalidOperationException(
                "The PostgreSQL connection URI must include a database name.");
        }

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = uri.Host,
            Port = uri.Port > 0 ? uri.Port : 5432,
            Database = database,
            Username = Uri.UnescapeDataString(userInfo[0]),
            Password = userInfo.Length == 2 ? Uri.UnescapeDataString(userInfo[1]) : string.Empty
        };

        foreach (var pair in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = pair.Split('=', 2);
            var key = Uri.UnescapeDataString(parts[0]);
            var value = parts.Length == 2 ? Uri.UnescapeDataString(parts[1]) : string.Empty;
            var keyword = key.Replace('_', ' ');

            try
            {
                builder[keyword] = value;
            }
            catch (ArgumentException exception)
            {
                throw new InvalidOperationException(
                    $"The PostgreSQL connection URI contains an unsupported parameter: {key}.",
                    exception);
            }
        }

        return builder;
    }
}
