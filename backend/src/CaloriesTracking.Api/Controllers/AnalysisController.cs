using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Analysis;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

using Microsoft.AspNetCore.RateLimiting;

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
        catch (InvalidOperationException ex)
        {
            _logger.LogError(ex, "Gemini analysis error");
            return StatusCode(500, new { error = "Failed to analyze image due to an internal error." });
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Gemini network error");
            return StatusCode(503, new { error = "Gemini AI service is temporarily unavailable." });
        }
        catch (OperationCanceledException)
        {
            return StatusCode(499, new { error = "Request was cancelled by client." });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Food analysis failed");
            return StatusCode(500, new { error = "Failed to analyze image due to an internal error." });
        }
    }
}
