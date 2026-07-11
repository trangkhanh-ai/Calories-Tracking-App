using CaloriesTracking.Application.Dtos.Analysis;

namespace CaloriesTracking.Application.Abstractions;

public interface IFoodAnalysisService
{
    /// <summary>Phân tích ảnh món ăn, trả về dinh dưỡng theo spec docs/API_SPEC.md.</summary>
    Task<FoodAnalysisResponse> AnalyzeAsync(byte[] imageBytes, CancellationToken cancellationToken = default);
}
