using System.Net.Http.Json;
using System.Text.Json;
using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Analysis;
using Microsoft.Extensions.Configuration;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Processing;

namespace CaloriesTracking.Infrastructure.Services;

/// <summary>
/// Gọi Gemini Vision để phân tích ảnh món ăn. Thay thế proxy Node cũ
/// (scripts/gemini_proxy.js) — logic nén ảnh và prompt được giữ nguyên.
/// </summary>
public sealed class GeminiFoodAnalysisService : IFoodAnalysisService
{
    private const int MaxImageWidth = 800;
    private const int JpegQuality = 70;

    private const string SystemPrompt = """
        Bạn là chuyên gia dinh dưỡng người Việt Nam. Hãy phân tích ảnh thức ăn và trả về JSON.
        Ưu tiên nhận diện các món ăn Việt Nam (phở, bún, cơm, bánh mì, v.v.).

        Trả về CHÍNH XÁC format JSON sau (không thêm markdown, không thêm text):
        {
          "food_detected": true,
          "items": [
            {
              "name": "Tên món bằng tiếng Việt",
              "name_en": "English name",
              "serving_size": "Khẩu phần ước tính (VD: 1 bát / 300g)",
              "calories": 350,
              "protein_g": 15.5,
              "carbs_g": 45.0,
              "fat_g": 8.2,
              "confidence": 0.92
            }
          ],
          "image_quality": "good",
          "notes": "Ghi chú bổ sung nếu có"
        }

        Quy tắc:
        - Nếu không thấy thức ăn: food_detected = false, items = []
        - image_quality: "good" | "low_light" | "blurry" | "too_far"
        - confidence: 0.0 đến 1.0
        - Nếu có nhiều món: liệt kê tất cả trong mảng items
        - calories và macros là ước tính cho 1 khẩu phần thông thường
        """;

    private readonly HttpClient _httpClient;
    private readonly string _apiKey;
    private readonly string _model;

    public GeminiFoodAnalysisService(HttpClient httpClient, IConfiguration configuration)
    {
        _httpClient = httpClient;
        _apiKey = configuration["Gemini:ApiKey"]
            ?? throw new InvalidOperationException("Gemini:ApiKey is not configured.");
        _model = configuration["Gemini:Model"] ?? "gemini-2.5-flash";

        if (string.IsNullOrWhiteSpace(_apiKey))
        {
            throw new InvalidOperationException(
                "Gemini:ApiKey is empty. Set it via the GEMINI__APIKEY environment variable.");
        }
    }

    public async Task<FoodAnalysisResponse> AnalyzeAsync(byte[] imageBytes, CancellationToken cancellationToken = default)
    {
        var compressedBase64 = Convert.ToBase64String(Compress(imageBytes));

        var requestBody = new
        {
            contents = new[]
            {
                new
                {
                    parts = new object[]
                    {
                        new { text = SystemPrompt },
                        new { inlineData = new { mimeType = "image/jpeg", data = compressedBase64 } }
                    }
                }
            },
            generationConfig = new
            {
                temperature = 0.4,
                responseMimeType = "application/json"
            }
        };

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent");
        request.Headers.Add("x-goog-api-key", _apiKey);
        request.Content = JsonContent.Create(requestBody);

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var responseText = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Gemini API error {(int)response.StatusCode}: {responseText}");
        }

        using var document = JsonDocument.Parse(responseText);
        var modelText = document.RootElement
            .GetProperty("candidates")[0]
            .GetProperty("content")
            .GetProperty("parts")[0]
            .GetProperty("text")
            .GetString() ?? throw new InvalidOperationException("Gemini returned an empty response.");

        return JsonSerializer.Deserialize<FoodAnalysisResponse>(modelText)
            ?? throw new InvalidOperationException("Failed to parse Gemini response as FoodAnalysisResponse.");
    }

    private static byte[] Compress(byte[] imageBytes)
    {
        using var image = Image.Load(imageBytes);
        if (image.Width > MaxImageWidth)
        {
            image.Mutate(x => x.Resize(MaxImageWidth, 0)); // 0 = giữ tỉ lệ
        }

        using var output = new MemoryStream();
        image.Save(output, new JpegEncoder { Quality = JpegQuality });
        return output.ToArray();
    }
}
