# 🍏 Calories Tracking App (AI-Powered)

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![.NET](https://img.shields.io/badge/.NET_9-512BD4?style=for-the-badge&logo=dotnet&logoColor=white)
![Gemini AI](https://img.shields.io/badge/Gemini_AI-%238E75B2.svg?style=for-the-badge&logo=google&logoColor=white)

Ứng dụng theo dõi calo thông minh: chụp ảnh món ăn → **Google Gemini Vision** tự động nhận diện và phân tích dinh dưỡng (ưu tiên món Việt: phở, bún, cơm, bánh mì...).

- **Frontend:** Flutter (Web / Android / iOS)
- **Backend:** .NET 9 Web API (Clean Architecture) + EF Core; SQLite cho development, PostgreSQL/Neon cho production
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
- 🎯 **Thiết lập mục tiêu calo** — sau khi đăng ký (hoặc đăng nhập lần đầu chưa có mục tiêu), app dẫn qua màn `/goal-setup`: chọn mức vận động (Không tập / Tập nhẹ / Tập vừa / Tập nhiều), backend tính BMI, BMR (Mifflin-St Jeor), TDEE (không tập ⇒ hệ số 1.2) và calo khuyến nghị theo 5 mục tiêu: giữ cân, giảm chậm (−300), giảm bình thường (−500), tăng chậm (+250), tăng bình thường (+500). Endpoint `GET /api/profile/calorie-goal` trả về cả `activityFactor` đã áp dụng.
- 📊 **Nhật ký & thống kê** — ghi bữa ăn theo Sáng/Trưa/Tối/Ăn vặt, thống kê 7 ngày. Nhật ký đồng bộ qua Diary API backend (server là source-of-truth).
- 🔎 **Tra cứu thực phẩm** — tìm kiếm trên bộ dữ liệu dinh dưỡng USDA được seed bằng EF Core.
- 🛡️ **Rate limiting** — endpoint phân tích ảnh, đăng ký, đăng nhập và tìm kiếm đều có rate limit per-IP hoặc per-user.
- 🚀 **CI/CD** — GitHub Actions chạy analyze, test và build Flutter Web release trên mỗi PR; Vercel deploy frontend, Render deploy backend.

## 🔮 Planned / Future improvements

- [ ] Lưu JWT bằng `flutter_secure_storage` + refresh-token flow.
- [ ] Lưu avatar thật (hiện là `FakeAvatarStorageService`).
- [ ] Offline cache nhật ký bằng Isar.

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
                                              SQLite dev / Neon prod │ x-goog-api-key
                                                     + EF Core       ▼
                                                         Google Gemini 2.5 Flash
```

- Toàn bộ lời gọi Gemini đi qua backend (`POST /api/analysis/food`, yêu cầu JWT). API key chỉ tồn tại trong biến môi trường server.
- Proxy Node cũ (`scripts/gemini_proxy.js`) **đã bị xóa**. Toàn bộ lời gọi Gemini nay chỉ đi qua backend .NET.

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

### Bước 1 — Cấu hình secrets cho backend (bắt buộc)
Không có secret nào nằm trong source code. Dùng user-secrets (dev):

```bash
cd backend/src/CaloriesTracking.Api
dotnet user-secrets set "Gemini:ApiKey" "YOUR_GEMINI_API_KEY"
dotnet user-secrets set "Jwt:Key" "CHUOI_BI_MAT_NGAU_NHIEN_DAI_HON_32_KY_TU"
```

(Production: dùng biến môi trường.) Backend **từ chối khởi động** nếu thiếu PostgreSQL connection string, `Jwt:Key`, Gemini key hoặc CORS HTTPS an toàn.

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

### Backend → Render Free + Neon Free

Repository có [render.yaml](render.yaml) để tạo đúng một Docker Web Service Free; Blueprint không tạo Render Postgres. Database production dùng Neon và connection string chỉ được nhập qua biến môi trường Render.

| Biến | Ý nghĩa |
|---|---|
| `JWT__KEY` | Chuỗi bí mật ≥ 32 ký tự (app từ chối chạy nếu thiếu) |
| `GEMINI__APIKEY` | Gemini API key |
| `CORS__ALLOWEDORIGINS__0` | Origin Vercel dạng `https://<tên-project>.vercel.app`, không có path hoặc dấu `/` cuối |
| `ConnectionStrings__DefaultConnection` | Neon PostgreSQL URI có `sslmode=require&channel_binding=require` |

Hướng dẫn đầy đủ: [docs/DEPLOY_RENDER.md](docs/DEPLOY_RENDER.md). Render dùng `GET /health` để kiểm tra database readiness; `GET /health/live` chỉ kiểm tra process liveness.

### Frontend → Vercel

Vercel là nền tảng deploy frontend duy nhất. Import repository, giữ **Root Directory** ở gốc repo (dự án Flutter nằm ở gốc), rồi đặt Environment Variable:

```text
BACKEND_BASE_URL=https://<service-name>.onrender.com
```

Không thêm `/api`, path, query hay dấu `/` cuối. [scripts/vercel-build.sh](scripts/vercel-build.sh) sẽ dừng build nếu giá trị thiếu, không phải HTTPS, có path/credentials, hoặc trỏ về loopback. Flutter SDK được pin cứng ở `3.44.1` để build có thể tái lập.

Build tay:
```bash
flutter build web --release --base-href / \
  --dart-define=BACKEND_BASE_URL=https://calories-api.onrender.com
```

> Workflow [.github/workflows/deploy.yml](.github/workflows/deploy.yml) (GitHub Pages) **đã deprecated** và chỉ còn chạy thủ công qua `workflow_dispatch`. Hai đường deploy frontend song song sẽ cần hai origin CORS, trong khi `render.yaml` chỉ khai báo `CORS__ALLOWEDORIGINS__0`.

Sau khi deploy, phải kiểm tra URL Render thật, `GET /health`, CORS preflight và URL Vercel (kể cả deep-link như `/goal-setup`) trước khi tuyên bố hệ thống đã hoạt động production. Checklist smoke test đầy đủ: [docs/DEPLOYMENT_GUIDE.md §5](docs/DEPLOYMENT_GUIDE.md).

---

## 📱 iOS
Đã cấu hình `Info.plist` (Camera, Photo Library, Microphone) và Deployment Target ≥ 13.0. Build iOS cần macOS + Xcode.

## 🔒 Bảo mật
- Client không chứa bất kỳ secret nào (Flutter Web compile ra JS — mọi thứ nhúng vào đều đọc được).
- Mật khẩu: BCrypt hash ở server, không bao giờ lưu plaintext ở client.
- JWT key & Gemini key: chỉ qua user-secrets (dev) hoặc biến môi trường (production).
- Nếu lỡ commit key: **revoke ngay** tại Google AI Studio — xóa khỏi code là không đủ vì key còn trong git history.
