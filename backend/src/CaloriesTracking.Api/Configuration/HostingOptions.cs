namespace CaloriesTracking.Api.Configuration;

public sealed class HostingOptions
{
    public const string SectionName = "Hosting";

    public bool BehindTlsTerminatingProxy { get; set; }
}
