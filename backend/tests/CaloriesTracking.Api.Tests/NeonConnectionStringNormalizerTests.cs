using CaloriesTracking.Infrastructure.Data;
using Npgsql;

namespace CaloriesTracking.Api.Tests;

public sealed class NeonConnectionStringNormalizerTests
{
    [Fact]
    public void Normalize_WhenGivenNeonUri_PreservesCredentialsAndTlsOptions()
    {
        const string neonUri =
            "postgresql://cal_user:p%40ss%3Aword@ep-example.neon.tech/calories?sslmode=require&channel_binding=require";

        var normalized = NeonConnectionStringNormalizer.Normalize(neonUri);
        var builder = new NpgsqlConnectionStringBuilder(normalized);

        Assert.Equal("ep-example.neon.tech", builder.Host);
        Assert.Equal(5432, builder.Port);
        Assert.Equal("calories", builder.Database);
        Assert.Equal("cal_user", builder.Username);
        Assert.Equal("p@ss:word", builder.Password);
        Assert.Equal(SslMode.Require, builder.SslMode);
        Assert.Equal(ChannelBinding.Require, builder.ChannelBinding);
    }

    [Fact]
    public void Normalize_WhenGivenKeywordConnectionString_ReturnsEquivalentConnectionString()
    {
        const string connectionString =
            "Host=ep-example.neon.tech;Database=calories;Username=cal_user;Password=test;SSL Mode=Require;Channel Binding=Require";

        var normalized = NeonConnectionStringNormalizer.Normalize(connectionString);
        var builder = new NpgsqlConnectionStringBuilder(normalized);

        Assert.Equal("ep-example.neon.tech", builder.Host);
        Assert.Equal("calories", builder.Database);
        Assert.Equal(SslMode.Require, builder.SslMode);
        Assert.Equal(ChannelBinding.Require, builder.ChannelBinding);
    }

    [Fact]
    public void Normalize_WhenChannelBindingIsOmitted_RequiresChannelBinding()
    {
        const string connectionString =
            "postgresql://cal_user:test@ep-example.neon.tech/calories?sslmode=require";

        var normalized = NeonConnectionStringNormalizer.Normalize(connectionString);
        var builder = new NpgsqlConnectionStringBuilder(normalized);

        Assert.Equal(ChannelBinding.Require, builder.ChannelBinding);
    }

    [Fact]
    public void Normalize_WhenChannelBindingIsPrefer_Throws()
    {
        const string connectionString =
            "postgresql://cal_user:test@ep-example.neon.tech/calories?sslmode=require&channel_binding=prefer";

        var exception = Assert.Throws<InvalidOperationException>(
            () => NeonConnectionStringNormalizer.Normalize(connectionString));

        Assert.Contains("channel binding", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("disable")]
    [InlineData("allow")]
    [InlineData("prefer")]
    public void Normalize_WhenTlsIsWeak_Throws(string sslMode)
    {
        var connectionString =
            $"postgresql://cal_user:test@ep-example.neon.tech/calories?sslmode={sslMode}&channel_binding=require";

        var exception = Assert.Throws<InvalidOperationException>(
            () => NeonConnectionStringNormalizer.Normalize(connectionString));

        Assert.Contains("secure", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Normalize_WhenTlsIsOmitted_DefaultsToRequire()
    {
        const string connectionString =
            "postgresql://cal_user:test@ep-example.neon.tech/calories?channel_binding=require";

        var normalized = NeonConnectionStringNormalizer.Normalize(connectionString);
        var builder = new NpgsqlConnectionStringBuilder(normalized);

        Assert.Equal(SslMode.Require, builder.SslMode);
    }
    public void Normalize_WhenChannelBindingIsDisabled_Throws()
    {
        const string connectionString =
            "postgresql://cal_user:test@ep-example.neon.tech/calories?sslmode=require&channel_binding=disable";

        var exception = Assert.Throws<InvalidOperationException>(
            () => NeonConnectionStringNormalizer.Normalize(connectionString));

        Assert.Contains("channel binding", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("")]
    [InlineData("Data Source=calories.db")]
    [InlineData("mysql://user:password@example.com/calories")]
    public void Normalize_WhenConnectionStringIsNotPostgres_Throws(string connectionString)
    {
        var exception = Assert.Throws<InvalidOperationException>(
            () => NeonConnectionStringNormalizer.Normalize(connectionString));

        Assert.Contains("PostgreSQL", exception.Message, StringComparison.OrdinalIgnoreCase);
    }
}
