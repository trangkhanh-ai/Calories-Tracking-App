# Đặc tả API: Tính năng Phân tích Thức ăn (Food Analysis API Spec)

Tài liệu này được xây dựng dựa trên phương pháp **Spec-Driven Development (SDD)**. Nó đóng vai trò là "nguồn chân lý duy nhất" (Single Source of Truth) định nghĩa cấu trúc dữ liệu giao tiếp giữa Ứng dụng Di động (Client) và AI Model (Gemini Vision API).

---

## 1. Tổng quan
- **Chức năng:** Nhận hình ảnh thức ăn từ người dùng (chụp qua Camera hoặc tải lên từ thư viện) và trả về thông tin dinh dưỡng chi tiết.
- **Phương thức gọi:** Hệ thống gửi ảnh dạng Base64 kèm Prompt (hướng dẫn) tới dịch vụ Gemini AI.
- **Định dạng dữ liệu trả về (Output Format):** Bắt buộc trả về định dạng `application/json`.

---

## 2. Đặc tả JSON Trả về (Response Schema)

AI **bắt buộc** phải trả về một Object JSON với cấu trúc chính xác như sau:

```json
{
  "food_detected": true,
  "image_quality": "good",
  "total_calories": 450,
  "total_protein": 25.5,
  "total_carbs": 40.0,
  "total_fat": 15.0,
  "items": [
    {
      "name": "Tên món ăn (vd: Phở Bò)",
      "confidence": 0.95,
      "calories": 400,
      "protein": 20.0,
      "serving_size": "1 bát"
    }
  ],
  "health_tips": "Mẹo sức khỏe ngắn gọn về bữa ăn này."
}
```

### 2.1. Giải thích các trường dữ liệu (Field Definitions)

> [!IMPORTANT]
> Tất cả các trường dữ liệu dưới đây phải luôn tồn tại trong kết quả JSON trả về. Nếu không có dữ liệu, sử dụng giá trị mặc định (như `0` hoặc mảng rỗng `[]`).

| Tên trường (Field) | Kiểu dữ liệu | Bắt buộc | Ý nghĩa |
| :--- | :--- | :---: | :--- |
| `food_detected` | `boolean` | Có | `true` nếu hình ảnh có chứa đồ ăn/thức uống. `false` nếu AI phát hiện ảnh không phải thức ăn (vd: ảnh phong cảnh, ảnh bàn ghế). |
| `image_quality` | `string` | Có | Chất lượng của bức ảnh. Các giá trị hợp lệ: `"good"` (rõ nét), `"low_light"` (thiếu sáng), `"blurry"` (mờ nhòe). |
| `total_calories` | `number` | Có | Tổng lượng Calo ước tính của tất cả các món ăn trong hình. (Đơn vị: kcal) |
| `total_protein` | `number` | Có | Tổng lượng Protein ước tính. (Đơn vị: gam) |
| `total_carbs` | `number` | Có | Tổng lượng Carbohydrate ước tính. (Đơn vị: gam) |
| `total_fat` | `number` | Có | Tổng lượng Chất béo ước tính. (Đơn vị: gam) |
| `items` | `array` | Có | Danh sách các món ăn/thực phẩm được nhận diện trong hình. Nếu `food_detected = false`, mảng này có thể rỗng `[]`. |
| `health_tips` | `string` | Có | Một lời khuyên ngắn gọn dựa trên thành phần dinh dưỡng của bữa ăn (vd: "Bữa ăn này giàu đạm, tốt cho cơ bắp!"). |

### 2.2. Chi tiết của đối tượng trong mảng `items`

Mỗi đối tượng trong mảng `items` mô tả một món ăn đơn lẻ:

| Tên trường | Kiểu dữ liệu | Ý nghĩa |
| :--- | :--- | :--- |
| `name` | `string` | Tên món ăn bằng tiếng Việt (vd: "Phở Bò", "Salad", "Trứng luộc"). |
| `confidence` | `number` | Độ tự tin của AI về nhận định này (Từ 0.0 đến 1.0). |
| `calories` | `number` | Lượng Calo của riêng món này. |
| `protein` | `number` | Lượng Protein của riêng món này. |
| `serving_size` | `string` | Khẩu phần ước lượng (vd: "1 bát", "100g", "1 quả"). |

---

## 3. Các kịch bản xử lý (Behavioral Scenarios)

Dựa trên Spec, phía Front-end (Giao diện) và Back-end (Logic) phải tuân thủ các quy tắc hiển thị sau:

### Kịch bản 1: Không tìm thấy thức ăn
- **Điều kiện:** `food_detected == false`
- **Hành động (Client):** Giao diện phải chặn không cho chuyển sang màn hình Kết quả. Hiển thị thông báo (Dialog): *"Không tìm thấy thức ăn trong ảnh. Hãy đảm bảo khung hình chứa món ăn rõ ràng"*.

### Kịch bản 2: Ảnh thiếu sáng / Mờ
- **Điều kiện:** `image_quality == "low_light"` hoặc `image_quality == "blurry"`
- **Hành động (Client):** Giao diện vẫn hiển thị số liệu Calo, nhưng phải hiển thị thêm một Cảnh báo (Warning SnackBar): *"💡 Ảnh hơi tối — kết quả có thể kém chính xác hơn"*.

### Kịch bản 3: Xử lý ngoại lệ (Fallback)
- **Điều kiện:** AI trả về JSON lỗi cú pháp (Unexpected end of JSON input) hoặc bị Timeout (hết thời gian chờ).
- **Hành động (Client):** Bắt lỗi (Try-Catch) và thông báo cho người dùng yêu cầu thử lại, không được làm sập (Crash) ứng dụng.

---

> [!TIP]
> **Lợi ích của Đặc tả này đối với dự án:**
> Việc định nghĩa chuẩn tài liệu này giúp Team giao diện có thể độc lập thiết kế màn hình `ResultsScreen` bằng cách giả lập (mock data) đoạn JSON trên, trong khi Team AI hoàn thiện việc tương tác với Gemini API. Khi 2 bên ghép code lại sẽ đảm bảo ăn khớp 100% không bị xung đột.
