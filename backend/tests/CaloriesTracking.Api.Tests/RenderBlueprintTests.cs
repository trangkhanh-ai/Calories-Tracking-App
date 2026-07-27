namespace CaloriesTracking.Api.Tests;

public sealed class RenderBlueprintTests
{
    [Fact]
    public void RenderBlueprint_PreservesProductionContractAndUsesPollingFileWatcher()
    {
        var renderYamlPath = FindRepositoryFile("render.yaml");
        var actualLines = File.ReadAllLines(renderYamlPath);
        var expectedLines = new[]
        {
            "services:",
            "  - type: web",
            "    name: calories-tracking-api",
            "    runtime: docker",
            "    plan: free",
            "    region: singapore",
            "    dockerContext: ./backend",
            "    dockerfilePath: ./backend/Dockerfile",
            "    healthCheckPath: /health",
            "    envVars:",
            "      - key: ASPNETCORE_ENVIRONMENT",
            "        value: Production",
            "      - key: DOTNET_USE_POLLING_FILE_WATCHER",
            "        value: \"1\"",
            "      - key: HOSTING__BEHINDTLSTERMINATINGPROXY",
            "        value: \"true\"",
            "      - key: SEEDING__ENABLED",
            "        value: \"true\"",
            "      - key: ConnectionStrings__DefaultConnection",
            "        sync: false",
            "      - key: JWT__KEY",
            "        sync: false",
            "      - key: GEMINI__APIKEY",
            "        sync: false",
            "      - key: CORS__ALLOWEDORIGINS__0",
            "        sync: false"
        };

        Assert.Equal(expectedLines, actualLines);
    }

    private static string FindRepositoryFile(string relativePath)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
             directory is not null;
             directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, relativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException($"Could not locate repository file '{relativePath}'.");
    }
}
