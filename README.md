# 🍏 Calories Tracking App (AI-Powered)

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![.NET](https://img.shields.io/badge/.NET_9-512BD4?style=for-the-badge&logo=dotnet&logoColor=white)
![Gemini AI](https://img.shields.io/badge/Gemini_AI-%238E75B2.svg?style=for-the-badge&logo=google&logoColor=white)

Ứng dụng theo dõi calo thông minh: chụp ảnh món ăn → **Google Gemini Vision** tự động nhận diện và phân tích dinh dưỡng (ưu tiên món Việt: phở, bún, cơm, bánh mì...).

- **Frontend:** Flutter (Web / Android / iOS)
- **Backend:** .NET 9 Web API (Clean Architecture) + EF Core + SQLite
- **AI:** Gemini 2.5 Flash (gọi từ backend — client không giữ API key)

## 📸 Screenshots

<!-- TODO: chạy app và chụp màn hình, lưu vào docs/screenshots/ -->
| Trang chủ | Scan món ăn | Kết quả | Mục tiêu calo |
|---|---|---|---|
| _(coming soon)_ | _(coming soon)_ | _(coming soon)_ | _(coming soon)_ |

---

## ✅ Tính năng đã hoàn thành

- 📸 **Scan món ăn qua Camera/Gallery** — Gemini phân tích Calories, Protein, Carbs, Fat cho từng món trong ảnh, trả JSON theo spec cố định ([docs/API_SPEC.md](docs/API_SPEC.md)).
- 🔐 **Đăng ký / Đăng nhập** — JWT 7 ngày, mật khẩu hash BCrypt. "Nhớ tài khoản" chỉ lưu username (không bao giờ lưu mật khẩu).
- 👤 **Hồ sơ cá nhân** — chiều cao/cân nặng/tuổi/giới tính/mức vận động + avatar, đồng bộ backend.
- 🎯 **Thiết lập mục tiêu calo** — sau khi đăng ký, app dẫn qua màn `/goal-setup`: chọn mức vận động (Không tập / Tập nhẹ / Tập vừa / Tập nhiều), backend tính BMI, BMR (Mifflin-St Jeor), TDEE (không tập ⇒ hệ số 1.2) và calo khuyến nghị theo mục tiêu giảm/giữ/tăng cân.
- 📊 **Nhật ký & thống kê** — ghi bữa ăn theo Sáng/Trưa/Tối/Ăn vặt, thống kê 7 ngày.
- 🔎 **Tra cứu thực phẩm** — tìm kiếm trên bộ dữ liệu dinh dưỡng USDA (seed sẵn vào SQLite).
- 🚀 **CI/CD** — GitHub Actions tự build Flutter Web và deploy GitHub Pages khi push `main`.

## 🔮 Planned / Future improvements

- [ ] Deploy backend lên Render/Railway (Dockerfile đã sẵn — xem [Deploy](#-deploy-production)); chuyển SQLite → PostgreSQL để dữ liệu không mất khi redeploy.
- [ ] Lưu JWT bằng `flutter_secure_storage` + refresh-token flow.
- [ ] Rate limiting cho endpoint phân tích ảnh (chống lạm dụng Gemini key).
- [ ] Lưu avatar thật (hiện là `FakeAvatarStorageService`).
- [ ] Offline cache nhật ký bằng Isar.
- [ ] Unit tests cho `CalorieCalculator` (C#) và parse `FoodAnalysisResult` (Dart).

---

## 🏗 Architecture hiện tại

```text
┌──────────────────┐        HTTPS/JSON         ┌───────────────────────────┐
│   Flutter App    │ ────────────────────────▶ │   .NET 9 Web API          │
│  (Web/Android)   │   /api/auth, /profile,    │   Clean Architecture      │
│                  │   /diary, /food,          │   Api → Application       │
│  KHÔNG giữ       │   /analysis/food          │       → Domain            │
│  API key nào     │ ◀──────────────────────── │       → Infrastructure    │
└──────────────────┘                           └─────────┬─────────┬───────┘
                                                         │         │
                                                  SQLite + EF Core │ x-goog-api-key
                                                  (USDA seed data) ▼
                                                         Google Gemini 2.5 Flash
```

- Toàn bộ lời gọi Gemini đi qua backend (`POST /api/analysis/food`, yêu cầu JWT). API key chỉ tồn tại trong biến môi trường server.
- `scripts/gemini_proxy.js` (proxy Node cũ) **đã deprecated**, giữ tạm để tham khảo — sẽ xóa.

Cấu trúc Flutter (Feature-First):

```text
lib/
├── app/               # Theme, Router (go_router)
├── core/network/      # ApiClient (dio + JWT interceptor)
├── features/
│   ├── auth/          # Đăng ký / đăng nhập
│   ├── diary/         # Nhật ký bữa ăn + thống kê
│   ├── food_search/   # Tra cứu thực phẩm USDA
│   ├── home/          # Dashboard vòng tròn calo
│   ├── profile/       # Hồ sơ + BMI/TDEE + goal setup
│   └── scanner/       # Camera + phân tích ảnh qua backend
└── shared/utils/      # Hằng số app (không chứa secret)
```

Chi tiết: [docs/SYSTEM_ARCHITECTURE.md](docs/SYSTEM_ARCHITECTURE.md) · [docs/SPEC_DRIVEN_DEVELOPMENT.md](docs/SPEC_DRIVEN_DEVELOPMENT.md)

---

## 🚀 Chạy dự án (Development)

### Yêu cầu
- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.12 (Windows: cần bật **Developer Mode** — `start ms-settings:developers`)
- [.NET SDK](https://dotnet.microsoft.com/download) 9/10
- Gemini API key ([Google AI Studio](https://aistudio.google.com/apikey))

### Bước 1 — Cấu hình Gemini key cho backend (bắt buộc)
Key **không nằm trong source code**. Dùng user-secrets (dev):

```bash
cd backend/src/CaloriesTracking.Api
dotnet user-secrets set "Gemini:ApiKey" "YOUR_GEMINI_API_KEY"
```

(Hoặc đặt biến môi trường `GEMINI__APIKEY`.)

### Bước 2 — Chạy backend + frontend

```bash
# Cách nhanh (Windows): mở 2 cửa sổ tự động
start.bat

# Hoặc thủ công:
cd backend/src/CaloriesTracking.Api && dotnet run     # API tại http://localhost:5210
flutter pub get && flutter run -d chrome --web-port=54321
```

> ⚠️ Nếu trước đây từng chạy bản cũ: xóa file `backend/src/CaloriesTracking.Api/calories.db` một lần (DB cũ tạo bằng `EnsureCreated`, bản mới dùng EF Migrations).

### Android Emulator
```bash
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:5210
```

---

## 📦 Deploy (Production)

### Backend → Render/Railway/Fly.io
Đã có sẵn [backend/Dockerfile](backend/Dockerfile). Biến môi trường cần đặt:

| Biến | Ý nghĩa |
|---|---|
| `JWT__KEY` | Chuỗi bí mật ≥ 32 ký tự (app từ chối chạy nếu thiếu) |
| `GEMINI__APIKEY` | Gemini API key |
| `CORS__ALLOWEDORIGINS__0` | Origin frontend, vd `https://trangkhanh-ai.github.io` |
| `ConnectionStrings__DefaultConnection` | Mặc định SQLite; nên trỏ PostgreSQL khi lên production |

Health check: `GET /health`.

### Frontend → GitHub Pages
Workflow [.github/workflows/deploy.yml](.github/workflows/deploy.yml) tự chạy khi push `main`. Đặt **Repository Variable** `BACKEND_BASE_URL` (Settings → Secrets and variables → Actions → Variables) trỏ về URL backend đã deploy, vd `https://calories-api.onrender.com`.

Build tay:
```bash
flutter build web --release --base-href "/Calories-Tracking-App/" \
  --dart-define=BACKEND_BASE_URL=https://calories-api.onrender.com
```

> 🔗 Live demo: `https://trangkhanh-ai.github.io/Calories-Tracking-App/` — chỉ hoạt động đầy đủ (scan/đăng nhập) sau khi backend đã được deploy và `BACKEND_BASE_URL` được cấu hình.

---

## 📱 iOS
Đã cấu hình `Info.plist` (Camera, Photo Library, Microphone) và Deployment Target ≥ 13.0. Build iOS cần macOS + Xcode.

## 🔒 Bảo mật
- Client không chứa bất kỳ secret nào (Flutter Web compile ra JS — mọi thứ nhúng vào đều đọc được).
- Mật khẩu: BCrypt hash ở server, không bao giờ lưu plaintext ở client.
- JWT key & Gemini key: chỉ qua user-secrets (dev) hoặc biến môi trường (production).
- Nếu lỡ commit key: **revoke ngay** tại Google AI Studio — xóa khỏi code là không đủ vì key còn trong git history.
