# 🍏 Calories Tracking App (AI-Powered)

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Gemini AI](https://img.shields.io/badge/Gemini_AI-%238E75B2.svg?style=for-the-badge&logo=google&logoColor=white)

Ứng dụng Theo dõi Calo thông minh sử dụng **Google Gemini Vision AI** để tự động nhận diện và phân tích lượng dinh dưỡng từ hình ảnh thức ăn của bạn. 

Dự án được xây dựng trên nền tảng **Flutter**, hỗ trợ đa nền tảng (Web, Android, iOS) và áp dụng phương pháp luận **Spec-Driven Development (SDD)** chuyên nghiệp.

---

## ✨ Tính Năng Nổi Bật (Key Features)

- 📸 **Quét Thức Ăn Bằng Camera/Thư Viện:** Chụp ảnh bữa ăn của bạn hoặc tải ảnh lên từ điện thoại để AI tự động phân tích.
- 🤖 **Tích Hợp Google Gemini AI:** Phân tích cực kỳ chính xác số Calo, Protein, Carbs, và Fat của từng món ăn có trong hình.
- 📊 **Dashboard & Diary:** Theo dõi tổng lượng calo đã nạp trong ngày (Home) và xem lại lịch sử các bữa ăn (Diary).
- 🌐 **Hỗ Trợ Đa Nền Tảng:** Chạy mượt mà trên Web (truy cập qua link HTTPS), thiết bị Android (file `.apk`).
- 🚀 **CI/CD Tự Động:** Được thiết lập GitHub Actions tự động build và deploy lên GitHub Pages mỗi khi có mã nguồn mới.

---

## 🛠 Công Nghệ Sử Dụng (Tech Stack)

Dự án sử dụng các thư viện và kỹ thuật hiện đại nhất của hệ sinh thái Flutter:
- **Framework:** Flutter (`^3.12.0`), Dart
- **Quản lý trạng thái (State Management):** `flutter_riverpod`
- **Điều hướng (Routing):** `go_router`
- **AI & Mạng (Networking):** `http` (Giao tiếp với Gemini REST API), `connectivity_plus`
- **Xử lý Hình Ảnh:** `camera`, `image_picker`, `image`, `cross_file` (hỗ trợ đọc file an toàn trên Web)
- **Giao Diện (UI):** `google_fonts`, `lottie` (hiệu ứng chuyển động mượt mà), `cupertino_icons`
- **Lưu trữ Cục Bộ:** `shared_preferences`

---

## 🏗 Kiến Trúc Dự Án (Architecture Structure)

Dự án tuân thủ nguyên tắc **Feature-First Architecture** (Kiến trúc chia theo tính năng), giúp mã nguồn dễ dàng mở rộng và bảo trì:

```text
lib/
├── app/               # Cấu hình cốt lõi (Theme, Router config)
├── features/          # Chứa các tính năng chính của App
│   ├── diary/         # Tính năng Lịch sử bữa ăn
│   ├── home/          # Tính năng Dashboard trang chủ
│   └── scanner/       # Cốt lõi: Xử lý Camera & Tích hợp Gemini AI
│       ├── models/    # Data class (FoodAnalysisResult...)
│       ├── screens/   # Màn hình (CameraScannerScreen, ResultsScreen...)
│       ├── services/  # Xử lý logic gọi API (GeminiVisionService)
│       └── widgets/   # Các UI Component dùng chung cho tính năng này
└── shared/            # Tiện ích dùng chung toàn App (utils, constants...)
```

---

## 🌟 Phương Pháp Phát Triển: Spec-Driven Development (SDD)

Dự án này là minh chứng thực tế cho việc áp dụng phương pháp **Spec-Driven Development**. Sự giao tiếp giữa Front-end và AI Model không dựa trên sự ước đoán, mà dựa trên "Bản Hợp Đồng" (Specification) cố định.

- 📖 **[Đọc tài liệu lý thuyết và ứng dụng SDD của nhóm tại đây](docs/SPEC_DRIVEN_DEVELOPMENT.md)**
- ⚙️ **[Xem Bản Đặc Tả JSON (API Spec) tại đây](docs/API_SPEC.md)**

*Nhờ áp dụng SDD, dự án đảm bảo tính đồng nhất 100% dữ liệu đầu ra từ Gemini AI, tránh hoàn toàn các lỗi parsing JSON hay Crash App.*

---

## 🚀 Hướng Dẫn Cài Đặt (Getting Started)

### Yêu Cầu Hệ Thống
- Đã cài đặt [Flutter SDK](https://docs.flutter.dev/get-started/install) (phiên bản 3.12.0 trở lên).
- Có tài khoản Google AI Studio để lấy API Key.

### Bước 1: Clone dự án về máy
```bash
git clone https://github.com/trangkhanh-ai/Calories-Tracking-App.git
cd Calories-Tracking-App
flutter pub get
```

### Bước 2: Cấu hình API Key (BẮT BUỘC)
Do vấn đề bảo mật, mã API Key của Gemini không được đẩy lên GitHub. Bạn cần thiết lập thủ công trên máy của mình:
1. Đi tới thư mục `lib/shared/utils/`.
2. Tạo một file mới tên là `constants.dart` (hoặc sao chép từ file `constants.example.dart` nếu có).
3. Thêm đoạn code sau vào file vừa tạo và điền API Key của bạn:
```dart
class AppConstants {
  static const String geminiApiKey = 'ĐIỀN_API_KEY_CỦA_BẠN_VÀO_ĐÂY';
}
```

### Bước 3: Chạy ứng dụng
- **Chạy trên Trình Duyệt Web (Khuyên dùng để test):**
  ```bash
  flutter run -d chrome
  ```
- **Chạy trên Máy Ảo / Thiết bị Android thật:**
  ```bash
  flutter run
  ```

---

## 📱 Triển Khai iOS (Apple Devices)

Dự án đã được cấu hình đầy đủ `Info.plist` (cấp quyền Camera, Photo Library, Microphone) và iOS Deployment Target (>=13.0). 
Tuy nhiên, để tạo file ứng dụng trên iOS, bắt buộc bạn phải sử dụng máy tính macOS (MacBook/Mac Mini) có cài đặt Xcode. Các thiết bị Windows không thể biên dịch mã nguồn iOS.

## 🔗 Liên Kết Triển Khai Thực Tế (Live Demo)
Nếu GitHub Pages đã được thiết lập thành công, bạn có thể trải nghiệm ứng dụng trực tiếp trên bất kỳ trình duyệt di động nào qua đường dẫn:
👉 `https://trangkhanh-ai.github.io/Calories-Tracking-App/`
