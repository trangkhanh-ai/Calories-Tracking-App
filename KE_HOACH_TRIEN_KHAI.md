# Kế hoạch triển khai chi tiết — Calories Tracking App

> Lập ngày 02/07/2026, dựa trên khảo sát toàn bộ mã nguồn (Flutter `lib/`, backend .NET `backend/`, proxy `scripts/`, docs).

---

## 0. Hiện trạng thực tế (khác với giả định ban đầu)

Trước khi làm theo checklist, cần biết những điểm sau vì chúng **thay đổi thứ tự công việc**:

1. **Backend .NET ĐÃ TỒN TẠI** tại `backend/` (Clean Architecture 4 tầng: Api / Application / Domain / Infrastructure, chạy .NET 9 + EF Core + SQLite):
   - ✅ Auth: register/login, BCrypt hash password, JWT 7 ngày (`AuthService.cs`)
   - ✅ Profile: height/weight/age/gender/targetCalories + upload avatar
   - ✅ Diary: DailyLog + MealItem (có MealType)
   - ✅ Food search: seed từ USDA CSV (`FoodController.cs`)
   - ❌ **CHƯA có endpoint phân tích ảnh Gemini** — Flutter vẫn gọi proxy Node local `http://127.0.0.1:3000/api/analyze-food` (`gemini_vision_service.dart:106`)
   - ❌ Chưa có endpoint Calorie Calculator (TDEE tính ở client, `DiaryService.cs:36` còn ghi "assuming sedentary for now")
2. **API key Gemini thật đang lộ ở 2 chỗ trong repo public** `github.com/trangkhanh-ai/Calories-Tracking-App`:
   - `lib/shared/utils/constants.dart:14` — key nằm trong `defaultValue` (commit `84b6b7f`)
   - Commit deploy `859fa5a` — key bị **bake vào bundle web** đã publish lên GitHub Pages
3. **README nói dối hiện trạng**: nói "API Key không push lên GitHub" (sai — key đang nằm trong repo), hướng dẫn tự tạo `constants.dart` (sai — file đang được track), mô tả kiến trúc `lib/` thiếu 4 feature mới (auth, profile, diary API, food_search).
4. **`API_SPEC.md` lệch hoàn toàn với model thật** `FoodAnalysisResult`:
   | Spec (docs/API_SPEC.md) | Code thật (food_analysis_result.dart + gemini_proxy.js) |
   |---|---|
   | `total_calories`, `total_protein`, `total_carbs`, `total_fat` | ❌ không tồn tại (client tự cộng từ items) |
   | `health_tips` | ❌ code dùng `notes` |
   | items: `name, confidence, calories, protein, serving_size` | items: `name, name_en, serving_size, calories, protein_g, carbs_g, fat_g, confidence` |
   | image_quality: `good/low_light/blurry` | proxy còn có thêm `too_far` |
5. **Password lưu plaintext** trong SharedPreferences (`auth_provider.dart:97-101`, tính năng Remember Me).
6. **`ApiClient` hardcode** `http://127.0.0.1:5210/api` (`api_client.dart:10`), bỏ qua `AppConstants.backendBaseUrl` (vốn đã hỗ trợ `--dart-define=BACKEND_BASE_URL`).
7. Backend còn các "hack dev": `EnsureCreated` + `ALTER TABLE` raw trong `Program.cs`, seed user `testuser/dummyhash`, JWT key fallback hardcode `DevelopmentOnlySuperSecretKey_ChangeMe_123456789` (cả trong `appsettings.json` đã commit), CORS `AllowAll`.
8. Màn Profile đã có đủ dropdown 5 mức vận động + tính BMI/BMR/TDEE/khuyến nghị calo (`profile_screen.dart`, `calculator_utils.dart`) — nhưng lưu vào SharedPreferences ở client, backend chưa nhận `activityLevel`.

---

## GIAI ĐOẠN 1 — KHẨN CẤP: Xử lý API key bị lộ (làm NGAY, ~30 phút)

Key đã nằm trong lịch sử git public → coi như **đã bị lộ vĩnh viễn**. Xóa khỏi code là chưa đủ.

1. **Revoke/rotate key** tại [Google AI Studio](https://aistudio.google.com/apikey): xóa key Gemini cũ (key từng nằm trong `constants.dart`, xem git history), tạo key mới. Key mới **chỉ đặt trong `.env` của proxy/backend, không bao giờ đưa vào code Dart** (Flutter web không giấu được secret — mọi thứ compile ra JS đều đọc được).
2. Sửa `lib/shared/utils/constants.dart:14`: đổi `defaultValue` thành `''`. (Không cần xóa cả field ngay — nhưng về lâu dài nên xóa hẳn `geminiApiKey` khỏi client, vì client chỉ nên gọi backend.)
3. Tạo `lib/shared/utils/constants.example.dart` (bản mẫu, không secret) + thêm `lib/shared/utils/constants.dart` vào `.gitignore` **hoặc** giữ `constants.dart` được track nhưng không bao giờ chứa secret (khuyến nghị cách này, vì file còn chứa mealTypes/servingScales là config thường). Nếu chọn tách: chuyển phần secret sang file riêng `secrets.dart` bị gitignore.
4. Commit + push ngay bản đã gỡ key.
5. (Tùy chọn, vì key đã rotate nên không bắt buộc) Xóa key khỏi history bằng `git filter-repo` — chỉ làm nếu muốn sạch history; sẽ đổi hash toàn bộ commit và cần force-push + thông báo team.
6. Kiểm tra branch `gh-pages`/bundle web đã deploy: rebuild và deploy lại để bundle không còn key cũ.
7. Bật **API key restrictions** cho key mới trên Google Cloud Console (giới hạn theo API Generative Language + giới hạn quota).

**Tiêu chí xong:** `git grep AIza` trên HEAD không ra kết quả; key cũ đã bị revoke (gọi thử trả 403); app vẫn chạy qua proxy với key mới trong `.env`.

---

## GIAI ĐOẠN 2 — Vệ sinh bảo mật & repo (~half day)

### 2.1. Bỏ lưu password trong SharedPreferences
File: `lib/features/auth/providers/auth_provider.dart:94-119` + `login_screen.dart` (chỗ gọi `saveCredentials`).
- Phương án gọn nhất: "Remember Me" chỉ lưu **username**, không lưu password; JWT 7 ngày đã đủ giữ phiên đăng nhập.
- Phương án đầy đủ: dùng `flutter_secure_storage` cho token + refresh-token flow ở backend. (Để giai đoạn 5.)
- Việc cụ thể: xóa `saveCredentials`/`loadSavedCredentials` phần password, thêm migration xóa `saved_password` cũ: `prefs.remove('saved_password')` khi app khởi động.

### 2.2. Dọn secret backend
- Chuyển `Jwt:Key` ra biến môi trường (`JWT__KEY`), xóa giá trị thật khỏi `appsettings.json`; xóa fallback hardcode trong `Program.cs:28` và `AuthService.cs:76` (fail-fast nếu thiếu key).
- Xóa seed user `testuser` với `PasswordHash = "dummyhash"` trong `Program.cs:66-76`.

### 2.3. `.gitignore` / `.env`
- `scripts/.env` đã có `.env.example` mẫu — xác nhận `.env` nằm trong gitignore (thêm dòng `**/.env` cho chắc).

---

## GIAI ĐOẠN 3 — Đồng bộ tài liệu (~half day)

### 3.1. Viết lại `README.md` theo cấu trúc:
```
1. Giới thiệu + Screenshots (bảng 2-3 ảnh: Home, Scanner, Results, Profile)
2. ✅ Đã hoàn thành (Current Features)
   - Scan món ăn qua Gemini (qua proxy local)
   - Auth (register/login, JWT), Profile + BMI/TDEE, Diary, Food search USDA
3. 🏗 Architecture hiện tại
   - Sơ đồ: Flutter ─→ Node proxy (localhost:3000) ─→ Gemini
             Flutter ─→ .NET API (localhost:5210) ─→ SQLite
   - Cập nhật cây lib/ đủ 6 features (auth, diary, food_search, home, profile, scanner) + core/network
4. 🔮 Planned / Future improvements
   - Chuyển Gemini call vào backend, deploy Render/Railway, secure storage, refresh token, v.v.
5. Getting Started (sửa lại cho đúng: constants.dart đã có sẵn, cần chạy backend + proxy — mô tả start.bat; hướng dẫn .env cho proxy)
6. Live Demo (ghi rõ: bản GitHub Pages hiện chỉ chạy UI, scan không hoạt động vì proxy là localhost — hoặc gỡ claim này đến khi có backend thật)
```
- Chụp screenshot: chạy `start.bat`, chụp 3-4 màn hình chính, lưu vào `docs/screenshots/`, nhúng vào README.

### 3.2. Đồng bộ `docs/API_SPEC.md` với `FoodAnalysisResult`
Chọn **code là chuẩn** (vì proxy + model + prompt đều đã thống nhất với nhau), sửa spec theo bảng ở mục 0.4:
- items: `name, name_en, serving_size, calories, protein_g, carbs_g, fat_g, confidence`
- bỏ `total_*` và `health_tips`, thay bằng `notes`; thêm `too_far` vào image_quality.
- Thêm ghi chú "totals do client tự tính bằng tổng items".
- Đồng thời sửa `gemini_vision_service.dart:12` — dòng `_baseUrl` trỏ model `gemini-3.5-flash` không tồn tại và không được dùng → xóa dead code (`_baseUrl`, `_systemPrompt`, `_getMimeType` đều không dùng vì đã đi qua proxy).

---

## GIAI ĐOẠN 4 — Backend: hoàn thiện API (1-2 ngày)

### 4.1. Chuyển Gemini call vào backend .NET (thay proxy Node)
- Tạo `AnalysisController` (`POST /api/analysis/food`, `[Authorize]`):
  - Nhận multipart image hoặc base64; nén ảnh (resize 800px, JPEG q70 — port logic từ `gemini_proxy.js:25-31`, dùng `SixLabors.ImageSharp`).
  - Gọi `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent` với prompt tiếng Việt hiện có, `responseMimeType: application/json`, temperature 0.4.
  - Key đọc từ config `Gemini:ApiKey` (env var `GEMINI__APIKEY`).
  - Trả về đúng schema `FoodAnalysisResult` đã chốt ở 3.2.
- Thêm `IGeminiService` vào tầng Application, implementation ở Infrastructure (đúng kiến trúc hiện có).
- Giữ `scripts/gemini_proxy.js` thêm một thời gian làm fallback dev, đánh dấu deprecated trong README, xóa sau khi backend chạy ổn.

### 4.2. Calorie Calculator + Activity Level ở backend
- Thêm vào `User` entity: `ActivityLevel` (string/enum) — migration mới.
- `UpdateProfileRequest` + `ProfileController`: nhận `activityLevel`.
- Tạo service tính toán (port `calculator_utils.dart` sang C#): BMI, BMR Mifflin-St Jeor, TDEE với hệ số:
  - Không tập thể dục / sedentary → **1.2** (yêu cầu đã chốt)
  - Nhẹ 1.375, vừa 1.55, nhiều 1.725, rất nhiều 1.9
- Sửa `DiaryService.cs:36` bỏ "assuming sedentary": đọc activityLevel thật của user.
- Endpoint `GET /api/profile/calorie-goal` trả `{bmi, bmr, tdee, recommendedCalories}`.

### 4.3. Dọn production-readiness
- Thay `EnsureCreated` + raw `ALTER TABLE` bằng `dbContext.Database.Migrate()` (đã có sẵn Migrations folder).
- CORS: thay `AllowAll` bằng whitelist origin (localhost dev + domain GitHub Pages).
- Thêm health check endpoint `GET /health` (Render/Railway cần để probe).

---

## GIAI ĐOẠN 5 — Flutter: nối backend thật (1-2 ngày)

### 5.1. Sửa `ApiClient` (`lib/core/network/api_client.dart`)
- Thay `baseUrl` hardcode bằng `AppConstants.backendBaseUrl` (+ `/api`), để build production bằng `--dart-define=BACKEND_BASE_URL=https://...`.
- Bỏ `print()` interceptor → dùng `kDebugMode` guard hoặc `LogInterceptor`.

### 5.2. Chuyển `GeminiVisionService` → gọi backend
- `_callGeminiApi` đổi từ `http://127.0.0.1:3000/api/analyze-food` sang `ApiClient` (`POST /analysis/food`, kèm JWT tự động qua interceptor sẵn có).
- Xóa dependency `google_generative_ai` khỏi `pubspec.yaml` nếu không còn dùng.

### 5.3. Màn hình "Thiết lập mục tiêu calo"
Màn Profile hiện đã có gần đủ — việc còn lại:
- Tách flow "Thiết lập mục tiêu" thành bước riêng (route `/goal-setup`), bắt buộc sau khi register lần đầu.
- 4 lựa chọn theo yêu cầu: Không tập thể dục (1.2) / Tập nhẹ / Tập vừa / Tập nhiều — map vào enum backend.
- Kết quả TDEE/goal lấy **từ backend** (`GET /api/profile/calorie-goal`) thay vì tính local, đồng bộ về `dailyGoalProvider` để vòng tròn Home cập nhật.
- Giữ tính local làm preview tức thì khi user kéo dropdown (optimistic UI), nhưng nguồn chân lý là backend.

---

## GIAI ĐOẠN 6 — Deploy (1 ngày)

### 6.1. Backend lên Render (khuyến nghị — free tier, hỗ trợ Docker)
1. Viết `Dockerfile` cho `CaloriesTracking.Api` (multi-stage: sdk build → aspnet runtime).
2. Lưu ý SQLite trên Render free bị mất khi redeploy → gắn Persistent Disk ($) **hoặc** chuyển sang PostgreSQL free (Neon/Supabase) — chỉ cần đổi provider EF Core, khuyến nghị làm luôn vì SQLite + đường dẫn seed tương đối (`Program.cs:79`) sẽ vỡ trong container.
3. Env vars trên Render: `JWT__KEY`, `GEMINI__APIKEY`, `ConnectionStrings__DefaultConnection`, `ASPNETCORE_ENVIRONMENT=Production`.
4. Seed USDA: copy CSV vào image hoặc seed một lần bằng script.

### 6.2. Flutter web production
```bash
flutter build web --release --base-href "/Calories-Tracking-App/" \
  --dart-define=BACKEND_BASE_URL=https://<app>.onrender.com
```
- Cập nhật GitHub Actions workflow (`.github/workflows/`) thêm `--dart-define` từ GitHub Secrets.
- Test end-to-end trên GitHub Pages: register → goal setup → scan ảnh → diary.

---

## GIAI ĐOẠN 7 — Cải tiến sau (backlog, không chặn demo)

- `flutter_secure_storage` cho JWT + refresh token flow.
- Rate limiting cho endpoint analysis (chống lạm dụng key Gemini).
- Unit test: `CalculatorUtils` (C# + Dart), parse `FoodAnalysisResult`, AuthService.
- Isar/local cache offline cho Diary (đã có file `isar_food_entry.dart` dở dang).
- Avatar storage thật (hiện là `FakeAvatarStorageService`).

---

## Thứ tự thực hiện tóm tắt

| # | Việc | Ưu tiên | Ước lượng |
|---|------|---------|-----------|
| 1 | Rotate key + gỡ key khỏi code + redeploy Pages | 🔴 NGAY | 30 phút |
| 2 | Bỏ lưu password plaintext; dọn JWT secret backend | 🔴 Cao | nửa ngày |
| 3 | README (done vs planned, architecture, screenshots) + API_SPEC sync | 🟡 | nửa ngày |
| 4 | Backend: endpoint Gemini + activityLevel + calculator + Migrate() | 🟡 | 1-2 ngày |
| 5 | Flutter: ApiClient dùng BACKEND_BASE_URL, scanner gọi backend, màn goal setup | 🟡 | 1-2 ngày |
| 6 | Deploy Render (Postgres) + build web với dart-define + CI | 🟢 | 1 ngày |
| 7 | Backlog (secure storage, rate limit, tests) | ⚪ | dần dần |
