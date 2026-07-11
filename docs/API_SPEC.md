# Đặc tả API: Tính năng Phân tích Thức ăn (Food Analysis API Spec)

Tài liệu này được xây dựng theo phương pháp **Spec-Driven Development (SDD)** — là "nguồn chân lý duy nhất" (Single Source of Truth) cho cấu trúc dữ liệu giữa Client (Flutter), Backend (.NET) và AI Model (Gemini Vision).

> Spec này được đồng bộ 1:1 với code thật:
> - Client model: `lib/features/scanner/models/food_analysis_result.dart`
> - Backend DTO: `backend/src/CaloriesTracking.Application/Dtos/Analysis/FoodAnalysisDtos.cs`
> - Backend service (prompt): `backend/src/CaloriesTracking.Infrastructure/Services/GeminiFoodAnalysisService.cs`

---

## 1. Tổng quan

- **Endpoint:** `POST /api/analysis/food` (yêu cầu JWT — header `Authorization: Bearer <token>`)
- **Luồng:** Client gửi ảnh base64 → Backend nén ảnh (resize 800px, JPEG q70) → gọi Gemini với prompt cố định, `responseMimeType: application/json` → trả JSON về client.
- **Client không gọi Gemini trực tiếp** — API key chỉ tồn tại ở backend.

### Request

```json
{
  "imageBase64": "<ảnh JPEG/PNG/WebP mã hóa base64>"
}
```

## 2. Đặc tả JSON Trả về (Response Schema)

```json
{
  "food_detected": true,
  "items": [
    {
      "name": "Phở Bò",
      "name_en": "Beef Pho",
      "serving_size": "1 bát / 350g",
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
```

### 2.1. Trường cấp cao nhất

| Field | Kiểu | Bắt buộc | Ý nghĩa |
| :--- | :--- | :---: | :--- |
| `food_detected` | `boolean` | Có | `true` nếu ảnh có đồ ăn/thức uống; `false` nếu không (vd: ảnh phong cảnh). |
| `items` | `array` | Có | Danh sách món ăn. Rỗng `[]` khi `food_detected = false`. |
| `image_quality` | `string` | Có | `"good"` \| `"low_light"` \| `"blurry"` \| `"too_far"`. |
| `notes` | `string` | Có | Ghi chú/lời khuyên ngắn của AI (chuỗi rỗng nếu không có). |

> **Lưu ý:** Không có trường `total_*` — client tự cộng tổng từ `items`. Không có `health_tips` — dùng `notes`.

### 2.2. Trường trong mỗi phần tử `items`

| Field | Kiểu | Ý nghĩa |
| :--- | :--- | :--- |
| `name` | `string` | Tên món bằng tiếng Việt (vd: "Phở Bò"). |
| `name_en` | `string` | Tên tiếng Anh. |
| `serving_size` | `string` | Khẩu phần ước lượng (vd: "1 bát", "300g"). |
| `calories` | `number` | Calo của món này (kcal, cho 1 khẩu phần). |
| `protein_g` | `number` | Protein (gam). |
| `carbs_g` | `number` | Carbohydrate (gam). |
| `fat_g` | `number` | Chất béo (gam). |
| `confidence` | `number` | Độ tự tin của AI (0.0 – 1.0). |

Mọi trường luôn tồn tại; thiếu dữ liệu thì dùng mặc định (`0`, `""`, `[]`) — client parse với null-safety fallback nên không bao giờ crash.

---

## 3. Các kịch bản xử lý (Behavioral Scenarios)

### Kịch bản 1: Không tìm thấy thức ăn
- **Điều kiện:** `food_detected == false`
- **Client:** chặn chuyển sang màn Kết quả, hiển thị Dialog *"Không tìm thấy thức ăn trong ảnh"*.

### Kịch bản 2: Ảnh thiếu sáng / mờ / quá xa
- **Điều kiện:** `image_quality ∈ {"low_light", "blurry", "too_far"}`
- **Client:** hiển thị Warning SnackBar *"Ảnh hơi tối — kết quả có thể kém chính xác hơn"*.

### Kịch bản 3: Lỗi ngoại lệ (Fallback)
- **Điều kiện:** backend trả lỗi (401/500) hoặc JSON sai cú pháp.
- **Client:** retry tối đa 3 lần (backoff 2s/4s), sau đó báo lỗi yêu cầu thử lại — không crash app.

### Mã lỗi backend

| HTTP | Điều kiện |
| :--- | :--- |
| `400` | Thiếu `imageBase64` hoặc không phải base64 hợp lệ. |
| `401` | Thiếu/sai JWT. |
| `500` | Gemini lỗi hoặc không parse được kết quả — body: `{"error": "Failed to analyze image"}`. |
