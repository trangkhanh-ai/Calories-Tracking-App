using System.Diagnostics;
using CaloriesTracking.Application.Exceptions;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Middleware;

public sealed class GlobalExceptionHandler : IExceptionHandler
{
    private readonly IHostEnvironment _environment;
    private readonly ILogger<GlobalExceptionHandler> _logger;

    public GlobalExceptionHandler(IHostEnvironment environment, ILogger<GlobalExceptionHandler> logger)
    {
        _environment = environment;
        _logger = logger;
    }

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        _logger.LogError(exception, "Unhandled exception occurred: {Message}", exception.Message);

        var (statusCode, title, detail) = exception switch
        {
            ArgumentException argEx => (
                StatusCodes.Status400BadRequest,
                "Bad Request",
                argEx.Message),

            DuplicateUserException dupEx => (
                StatusCodes.Status409Conflict,
                "Conflict",
                dupEx.Message),

            UnauthorizedAccessException unauthEx => (
                StatusCodes.Status401Unauthorized,
                "Unauthorized",
                unauthEx.Message),

            InvalidOperationException invEx when invEx.Message.Contains("exceed", StringComparison.OrdinalIgnoreCase) ||
                                                invEx.Message.Contains("dimension", StringComparison.OrdinalIgnoreCase) ||
                                                invEx.Message.Contains("decoded", StringComparison.OrdinalIgnoreCase) => (
                StatusCodes.Status413PayloadTooLarge,
                "Payload Too Large",
                invEx.Message),

            NotSupportedException notSuppEx => (
                StatusCodes.Status415UnsupportedMediaType,
                "Unsupported Media Type",
                notSuppEx.Message),

            _ => (
                StatusCodes.Status500InternalServerError,
                "Internal Server Error",
                _environment.IsDevelopment()
                    ? exception.Message
                    : "An unexpected error occurred. Please try again later.")
        };

        var problemDetails = new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = detail,
            Instance = httpContext.Request.Path
        };

        problemDetails.Extensions["traceId"] = Activity.Current?.Id ?? httpContext.TraceIdentifier;

        httpContext.Response.StatusCode = statusCode;
        httpContext.Response.ContentType = "application/problem+json";

        await httpContext.Response.WriteAsJsonAsync(problemDetails, cancellationToken);

        return true;
    }
}
