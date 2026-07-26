using System.Diagnostics;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Middleware;

/// <summary>
/// Single RFC 7807 exit point for unhandled exceptions.
///
/// Mapping is driven by exception <em>type</em>, never by searching for words
/// inside a message — substring matching silently reclassifies unrelated
/// failures as soon as anyone rewords a string.
/// </summary>
public sealed class GlobalExceptionHandler : IExceptionHandler
{
    private const string GenericProductionDetail =
        "An unexpected error occurred. Please try again later.";

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
        // A client that hung up is not a server fault. Distinguish it from a
        // server-side timeout, which must still be reported as 5xx.
        if (exception is OperationCanceledException && httpContext.RequestAborted.IsCancellationRequested)
        {
            _logger.LogInformation(
                "Request aborted by client. Path={Path} Method={Method}",
                httpContext.Request.Path,
                httpContext.Request.Method);

            if (!httpContext.Response.HasStarted)
            {
                // 499 (client closed request): nothing is written back because
                // no one is listening.
                httpContext.Response.StatusCode = 499;
            }

            return true;
        }

        var (statusCode, title, detail) = Map(exception);

        // Log the full exception server-side; only the sanitized projection
        // below ever reaches the caller.
        if (statusCode >= StatusCodes.Status500InternalServerError)
        {
            _logger.LogError(
                exception,
                "Unhandled server error. Status={StatusCode} Path={Path} Method={Method}",
                statusCode,
                httpContext.Request.Path,
                httpContext.Request.Method);
        }
        else
        {
            _logger.LogWarning(
                "Request rejected. Status={StatusCode} Path={Path} Method={Method} Reason={Reason}",
                statusCode,
                httpContext.Request.Path,
                httpContext.Request.Method,
                title);
        }

        var problemDetails = new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = detail,
            Instance = httpContext.Request.Path
        };

        problemDetails.Extensions["traceId"] = Activity.Current?.Id ?? httpContext.TraceIdentifier;

        httpContext.Response.StatusCode = statusCode;

        // The content type must be passed to WriteAsJsonAsync: setting
        // Response.ContentType beforehand is overwritten by the serializer,
        // which is why these responses previously went out as application/json.
        await httpContext.Response.WriteAsJsonAsync(
            problemDetails,
            options: null,
            contentType: "application/problem+json",
            cancellationToken);

        return true;
    }

    private (int StatusCode, string Title, string Detail) Map(Exception exception) => exception switch
    {
        ValidationAppException validation => (
            StatusCodes.Status400BadRequest,
            validation.PublicTitle,
            validation.Message),

        ConflictAppException conflict => (
            StatusCodes.Status409Conflict,
            conflict.PublicTitle,
            conflict.Message),

        PayloadTooLargeAppException payload => (
            StatusCodes.Status413PayloadTooLarge,
            payload.PublicTitle,
            payload.Message),

        UnsupportedMediaTypeAppException media => (
            StatusCodes.Status415UnsupportedMediaType,
            media.PublicTitle,
            media.Message),

        // Retained for backwards compatibility with callers that still throw it.
        DuplicateUserException duplicate => (
            StatusCodes.Status409Conflict,
            "Conflict",
            duplicate.Message),

        UnauthorizedAccessException unauthorized => (
            StatusCodes.Status401Unauthorized,
            "Unauthorized",
            unauthorized.Message),

        // Gemini upstream is unavailable — a dependency problem, not a bug here.
        GeminiUnavailableException => (
            StatusCodes.Status503ServiceUnavailable,
            "Service Unavailable",
            "The analysis service is temporarily unavailable. Please try again shortly."),

        // Any other Gemini failure: never echo the upstream body.
        GeminiException => (
            StatusCodes.Status502BadGateway,
            "Bad Gateway",
            "The analysis service returned an unexpected response."),

        // Server-side deadline. Deliberately NOT folded into client-abort above.
        TimeoutException => (
            StatusCodes.Status504GatewayTimeout,
            "Gateway Timeout",
            "The request took too long to complete. Please try again."),

        // Argument failures from framework/BCL code still map to 400, but the
        // message is suppressed outside Development because it can contain
        // parameter names and internal detail.
        ArgumentException => (
            StatusCodes.Status400BadRequest,
            "Bad Request",
            _environment.IsDevelopment() ? exception.Message : "The request was not valid."),

        DataIntegrityAppException integrity => (
            StatusCodes.Status500InternalServerError,
            integrity.PublicTitle,
            _environment.IsDevelopment() ? integrity.Message : GenericProductionDetail),

        _ => (
            StatusCodes.Status500InternalServerError,
            "Internal Server Error",
            _environment.IsDevelopment() ? exception.Message : GenericProductionDetail)
    };
}
