# 🚀 Dev Setup — Chạy Full Stack bằng F5 (VS Code)

Sau khi `git pull`, làm theo các bước dưới để bấm **F5** chạy đồng thời backend .NET + Flutter Web.

> ⚠️ `git pull` **không** mang theo user-secrets. Máy mới **bắt buộc** tự thiết lập `Jwt:Key` (xem [Bước 2](#2-thiết-lập-secrets-bắt-buộc)), nếu không backend sẽ không khởi động và Flutter sẽ không mở.

---

## 1. Yêu cầu cài đặt (prerequisites)

| Công cụ | Ghi chú |
|---|---|
| **.NET SDK 9 hoặc 10** | Project target `net9.0`. Máy chỉ có .NET 10 vẫn chạy được nhờ `DOTNET_ROLL_FORWARD=LatestMajor` (đã cấu hình sẵn trong `launch.json`). |
| **Flutter SDK** (stable) | `flutter doctor` không báo lỗi nghiêm trọng. |
| **Google Chrome** | Flutter Web chạy trên device `chrome`. |
| **VS Code extensions** | C# (`ms-dotnettools.csharp`), Dart, Flutter. VS Code sẽ tự gợi ý cài từ `.vscode/extensions.json`. |

---

## 2. Thiết lập secrets (bắt buộc)

Secrets nằm trong .NET user-secrets (không commit vào git). Chạy một lần cho mỗi máy:

```bash
# Bắt buộc — backend throw ngay lúc khởi động nếu thiếu (Jwt:Key phải ≥ 32 ký tự)
dotnet user-secrets set "Jwt:Key" "<dev-key-tối-thiểu-32-ký-tự>" --project backend/src/CaloriesTracking.Api/CaloriesTracking.Api.csproj

# Chỉ cần nếu muốn dùng scanner (POST /api/analysis/food gọi Gemini)
dotnet user-secrets set "Gemini:ApiKey" "<gemini-api-key>" --project backend/src/CaloriesTracking.Api/CaloriesTracking.Api.csproj
```

Kiểm tra key đã có (không hiện giá trị):

```bash
dotnet user-secrets list --project backend/src/CaloriesTracking.Api/CaloriesTracking.Api.csproj
```

---

## 3. Cài dependency

```bash
flutter pub get
# backend restore/build tự chạy qua preLaunchTask khi F5, hoặc chạy tay:
dotnet build backend/src/CaloriesTracking.Api/CaloriesTracking.Api.csproj
```

---

## 4. Chạy bằng F5

1. Mở thư mục repo trong VS Code.
2. Panel **Run and Debug** → chọn cấu hình **`CalTrack: Full Stack`**.
3. Bấm **F5**.

Luồng tự động:
1. Build backend → chạy trên `http://localhost:5210`.
2. Task `caltrack-wait-backend` poll `http://localhost:5210/health` (timeout 45s).
3. Khi `/health` trả **200**, Flutter Web mở tại `http://127.0.0.1:54321`.
4. Bấm **Stop** → cả backend lẫn Flutter dừng (`stopAll`).

Cấu hình cố định:
- Backend URL: `http://localhost:5210`
- Flutter Web: `http://127.0.0.1:54321` (**giữ đúng port 54321** — backend chỉ mở CORS cho port này)
- `BACKEND_BASE_URL=http://localhost:5210` (truyền qua `--dart-define`)

---

## 5. Xử lý sự cố

| Triệu chứng | Nguyên nhân & cách xử lý |
|---|---|
| Flutter không mở, task readiness fail sau 45s | Backend chưa lên. Mở Debug Console của **`CalTrack: Backend`** xem lỗi (thường là thiếu `Jwt:Key` hoặc port 5210 đang bận). |
| Backend báo `Jwt:Key is missing or too short` | Chưa set user-secret `Jwt:Key` — xem [Bước 2](#2-thiết-lập-secrets-bắt-buộc). |
| `Failed to bind to address ...:5210` | Port 5210 đang bị chiếm. Tự đóng process đang giữ port (cấu hình **không** tự giết process lạ). |
| Chrome báo XMLHttpRequest / CORS error | Flutter đang chạy sai port. Phải là `127.0.0.1:54321`. |
| Scanner báo lỗi khi phân tích ảnh | Thiếu user-secret `Gemini:ApiKey`. Nút "Bỏ qua đăng nhập" **không** tạo JWT — phải đăng nhập/đăng ký thật để dùng scanner. |

---

## 6. Ghi chú cho teammate macOS / Linux

Task readiness `caltrack-wait-backend` trong `.vscode/tasks.json` hiện **chỉ có nhánh Windows** (dùng `powershell.exe`). Trên macOS/Linux cần bổ sung nhánh `linux`/`osx` (ví dụ dùng `bash` + `curl` poll `/health`) thì compound mới chạy được. Team toàn Windows có thể bỏ qua mục này.
