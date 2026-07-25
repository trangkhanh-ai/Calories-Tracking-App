using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Analysis;
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
        if (string.IsNullOrWhiteSpace(request.ImageBase64))
        {
            return BadRequest(new { error = "imageBase64 is required" });
        }

        if (request.ImageBase64.StartsWith("data:image", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(new { error = "Raw base64 string is required, do not include data URI prefix." });
        }

        if (request.ImageBase64.Length > 7_000_000)
        {
            return StatusCode(413, new { error = "Decoded image file exceeds 5MB limit." });
        }

        byte[] imageBytes;
        try
        {
            imageBytes = Convert.FromBase64String(request.ImageBase64);
        }
        catch (FormatException)
        {
            return BadRequest(new { error = "imageBase64 is not valid base64" });
        }

        if (imageBytes.Length == 0)
        {
            return BadRequest(new { error = "Image is empty" });
        }
        
        if (imageBytes.Length > 5 * 1024 * 1024)
        {
            return StatusCode(413, new { error = "Decoded image file exceeds 5MB limit." });
        }

        try
        {
            var result = await _foodAnalysisService.AnalyzeAsync(imageBytes, cancellationToken);
            return Ok(result);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (NotSupportedException ex)
        {
            return StatusCode(415, new { error = ex.Message });
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("exceeds"))
        {
            return StatusCode(413, new { error = ex.Message });
        }
        catch (GeminiUnavailableException ex)
        {
            _logger.LogWarning(ex, "Gemini upstream unavailable.");
            return StatusCode(503, new { error = "Gemini AI service is temporarily unavailable." });
        }
        catch (GeminiException ex)
        {
            _logger.LogError(ex, "Gemini service exception.");
            return StatusCode(500, new { error = "Failed to analyze image due to an internal error." });
        }
        catch (TimeoutRejectedException ex)
        {
            _logger.LogWarning(ex, "Gemini analysis request timed out.");
            return StatusCode(503, new { error = "Gemini AI service request timed out." });
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return StatusCode(499, new { error = "Request was cancelled by client." });
        }
        catch (OperationCanceledException ex)
        {
            _logger.LogWarning(ex, "Gemini analysis request timed out.");
            return StatusCode(503, new { error = "Gemini AI service request timed out." });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Food analysis failed");
            return StatusCode(500, new { error = "Failed to analyze image due to an internal error." });
        }
    }
}
