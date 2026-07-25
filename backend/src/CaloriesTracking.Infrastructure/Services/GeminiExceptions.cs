using System.Net;

namespace CaloriesTracking.Infrastructure.Services;

public class GeminiUnavailableException : Exception
{
    public HttpStatusCode? StatusCode { get; }

    public GeminiUnavailableException(string message, HttpStatusCode? statusCode = null) 
        : base(message)
    {
        StatusCode = statusCode;
    }
}

public class GeminiException : Exception
{
    public HttpStatusCode? StatusCode { get; }

    public GeminiException(string message, HttpStatusCode? statusCode = null) 
        : base(message)
    {
        StatusCode = statusCode;
    }
}
