using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Analysis;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Polly.Timeout;

namespace CaloriesTracking.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[EnableRateLimiting("GeminiAnalysis")]
public class AnalysisController : ControllerBase
{
    /// <summary>Decoded-image budget. Kept in sync with the client-facing message.</summary>
    public const int MaxDecodedImageBytes = 5 * 1024 * 1024;

    /// <summary>
    /// Base64 inflates by 4/3, so this is the smallest string that could decode
    /// past the budget. Checked before decoding to avoid materializing the array.
    /// </summary>
    private const int MaxBase64Length = 7_000_000;

    private readonly IFoodAnalysisService _foodAnalysisService;
    private readonly ILogger<AnalysisController> _logger;

    public AnalysisController(IFoodAnalysisService foodAnalysisService, ILogger<AnalysisController> logger)
    {
        _foodAnalysisService = foodAnalysisService;
        _logger = logger;
    }

    [HttpPost("food")]
    [RequestSizeLimit(8 * 1024 * 1024)]
    public async Task<IActionResult> AnalyzeFood([FromBody] AnalyzeFoodRequest request, CancellationToken cancellationToken)
    {
        // Validation throws typed exceptions so every failure leaves this
        // endpoint as RFC 7807 ProblemDetails, matching the rest of the API.
        if (string.IsNullOrWhiteSpace(request.ImageBase64))
        {
            throw new ValidationAppException("imageBase64", "imageBase64 is required.");
        }

        if (request.ImageBase64.StartsWith("data:image", StringComparison.OrdinalIgnoreCase))
        {
            throw new ValidationAppException(
                "imageBase64",
                "Raw base64 string is required; do not include the data URI prefix.");
        }

        if (request.ImageBase64.Length > MaxBase64Length)
        {
            throw new PayloadTooLargeAppException("Decoded image exceeds the 5 MB limit.");
        }

        byte[] imageBytes;
        try
        {
            imageBytes = Convert.FromBase64String(request.ImageBase64);
        }
        catch (FormatException)
        {
            throw new ValidationAppException("imageBase64", "imageBase64 is not valid base64.");
        }

        if (imageBytes.Length == 0)
        {
            throw new ValidationAppException("imageBase64", "Image is empty.");
        }

        if (imageBytes.Length > MaxDecodedImageBytes)
        {
            throw new PayloadTooLargeAppException("Decoded image exceeds the 5 MB limit.");
        }

        try
        {
            var result = await _foodAnalysisService.AnalyzeAsync(imageBytes, cancellationToken);
            return Ok(result);
        }
        catch (TimeoutRejectedException ex)
        {
            // Polly gave up waiting on the upstream. This is a dependency
            // timeout, not a client abort — surface it as 503.
            _logger.LogWarning(ex, "Gemini analysis request timed out.");
            throw new GeminiUnavailableException("Gemini analysis request timed out.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // Cancelled without the client aborting means an internal deadline fired.
            _logger.LogWarning("Gemini analysis exceeded its internal deadline.");
            throw new GeminiUnavailableException("Gemini analysis exceeded its deadline.");
        }
    }
}
