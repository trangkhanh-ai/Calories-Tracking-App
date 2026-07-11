using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Analysis;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CaloriesTracking.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
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
    [RequestSizeLimit(20 * 1024 * 1024)]
    public async Task<IActionResult> AnalyzeFood([FromBody] AnalyzeFoodRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.ImageBase64))
        {
            return BadRequest(new { error = "imageBase64 is required" });
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

        try
        {
            var result = await _foodAnalysisService.AnalyzeAsync(imageBytes, cancellationToken);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Food analysis failed");
            return StatusCode(500, new { error = "Failed to analyze image" });
        }
    }
}
