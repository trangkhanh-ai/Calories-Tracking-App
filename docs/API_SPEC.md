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

Tất cả các trường dữ liệu dưới đây phải luôn tồn tại trong kết quả JSON trả về. Nếu không có dữ liệu, sử dụng giá trị mặc định (như `0` hoặc mảng rỗng `[]`).

| Tên trường (Field) | Kiểu dữ liệu | Bắt buộc | Ý nghĩa |
| :--- | :--- | :---: | :--- |
| `food_detected` | `boolean` | Có | `true` nếu hình ảnh có chứa đồ ăn/thức uống. `false` nếu AI phát hiện ảnh không phải thức ăn (vd: ảnh phong cảnh). |
| `image_quality` | `string` | Có | Chất lượng của bức ảnh. Các giá trị hợp lệ: `"good"`, `"low_light"`, `"blurry"`. |
| `total_calories` | `number` | Có | Tổng lượng Calo ước tính. (Đơn vị: kcal) |
| `total_protein` | `number` | Có | Tổng lượng Protein ước tính. (Đơn vị: gam) |
| `total_carbs` | `number` | Có | Tổng lượng Carbohydrate ước tính. (Đơn vị: gam) |
| `total_fat` | `number` | Có | Tổng lượng Chất béo ước tính. (Đơn vị: gam) |
| `items` | `array` | Có | Danh sách các món ăn. Nếu `food_detected = false`, mảng này có thể rỗng `[]`. |
| `health_tips` | `string` | Có | Lời khuyên ngắn gọn dựa trên thành phần dinh dưỡng của bữa ăn. |

### 2.2. Chi tiết của đối tượng trong mảng `items`

| Tên trường | Kiểu dữ liệu | Ý nghĩa |
| :--- | :--- | :--- |
| `name` | `string` | Tên món ăn bằng tiếng Việt (vd: "Phở Bò"). |
| `confidence` | `number` | Độ tự tin của AI về nhận định này (0.0 đến 1.0). |
| `calories` | `number` | Lượng Calo của món này. |
| `protein` | `number` | Lượng Protein của món này. |
| `serving_size` | `string` | Khẩu phần ước lượng (vd: "1 bát", "100g"). |

---

## 3. Các kịch bản xử lý (Behavioral Scenarios)

Dựa trên Spec, phía Front-end (Giao diện) tuân thủ các quy tắc hiển thị sau:

### Kịch bản 1: Không tìm thấy thức ăn
- **Điều kiện:** `food_detected == false`
- **Hành động (Client):** Giao diện chặn không cho chuyển sang màn hình Kết quả. Hiển thị Dialog: *"Không tìm thấy thức ăn trong ảnh"*.

### Kịch bản 2: Ảnh thiếu sáng / Mờ
- **Điều kiện:** `image_quality == "low_light"` hoặc `"blurry"`
- **Hành động (Client):** Hiển thị thêm một Cảnh báo (Warning SnackBar): *"Ảnh hơi tối — kết quả có thể kém chính xác hơn"*.

### Kịch bản 3: Xử lý ngoại lệ (Fallback)
- **Điều kiện:** AI trả về JSON lỗi cú pháp.
- **Hành động (Client):** Bắt lỗi (Try-Catch) và thông báo yêu cầu thử lại, không được crash app.
