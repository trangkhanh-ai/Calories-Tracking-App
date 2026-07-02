using System.Text.Json.Serialization;

namespace CaloriesTracking.Application.Dtos.Analysis;

/// <summary>Request từ client: ảnh món ăn dạng base64 (JPEG/PNG/WebP).</summary>
public sealed record AnalyzeFoodRequest(string ImageBase64);

/// <summary>
/// Response đúng theo docs/API_SPEC.md — phải khớp 1:1 với model
/// FoodAnalysisResult phía Flutter (lib/features/scanner/models/food_analysis_result.dart).
/// </summary>
public sealed class FoodAnalysisResponse
{
    [JsonPropertyName("food_detected")]
    public bool FoodDetected { get; set; }

    [JsonPropertyName("items")]
    public List<FoodAnalysisItem> Items { get; set; } = [];

    [JsonPropertyName("image_quality")]
    public string ImageQuality { get; set; } = "good";

    [JsonPropertyName("notes")]
    public string Notes { get; set; } = string.Empty;
}

public sealed class FoodAnalysisItem
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("name_en")]
    public string NameEn { get; set; } = string.Empty;

    [JsonPropertyName("serving_size")]
    public string ServingSize { get; set; } = string.Empty;

    [JsonPropertyName("calories")]
    public double Calories { get; set; }

    [JsonPropertyName("protein_g")]
    public double ProteinG { get; set; }

    [JsonPropertyName("carbs_g")]
    public double CarbsG { get; set; }

    [JsonPropertyName("fat_g")]
    public double FatG { get; set; }

    [JsonPropertyName("confidence")]
    public double Confidence { get; set; }
}
