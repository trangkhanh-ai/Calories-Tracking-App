# Production Deployment & Manual Handoff Guide

Hướng dẫn từng bước triển khai ứng dụng **Calories Tracking App** lên môi trường Production.

---

## Architecture Overview

```text
Flutter Web (Vercel)
    ↓ HTTPS (NO /api trailing path in BACKEND_BASE_URL)
ASP.NET Core .NET 9 API (Render)
    ↓ TLS
PostgreSQL (Neon)

* Gemini API Key CHỈ được cấu hình và gọi tại backend API (Render).
```

---

## 1. Rotate Gemini API Key (Google AI Studio)

1. Truy cập [Google AI Studio](https://aistudio.google.com/).
2. Đăng nhập tài khoản Google và chuyển đến mục **Get API key**.
3. Chọn **Create API key** (hoặc thu hồi key cũ và tạo key mới).
4. Sao chép API key mới.
5. **LƯU Ý BẢO MẬT**: Không bao giờ commit key vào source code hoặc đưa vào build frontend. Key này chỉ được đặt tại biến môi trường `GEMINI__APIKEY` trên Render.

> ⚠️ **Bắt buộc xoay key trước khi lên production.** Một Gemini key đã từng xuất hiện trong Git history của repository này. Xóa khỏi code hiện tại **không** vô hiệu hóa key đã lộ — phải revoke và tạo key mới tại Google AI Studio.

---

## 2. Tạo Neon PostgreSQL Database

1. Truy cập [Neon Console](https://console.neon.tech/).
2. Tạo một Project mới (ví dụ: `calories-tracking-prod`).
3. Sau khi khởi tạo xong, truy cập **Dashboard** / **Connection Details**.
4. Chọn Driver **Connection string** (PostgreSQL URL).
5. Chuỗi kết nối có dạng:
   ```text
   postgresql://<user>:<password>@ep-xyz.region.aws.neon.tech/neondb?sslmode=require&channel_binding=require
   ```
6. Lưu chuỗi này lại để nhập vào Render.

---

## 3. Tạo Render Web Service (Backend API)

1. Truy cập [Render Dashboard](https://dashboard.render.com/) và chọn **New +** -> **Web Service**.
2. Kết nối với GitHub Repository `trangkhanh-ai/Calories-Tracking-App`.
3. Cấu hình dịch vụ:
   - **Name**: `calories-tracking-api`
   - **Region**: Singapore / Oregon (tùy chọn)
   - **Branch**: `main`
   - **Root Directory**: để trống khi dùng `render.yaml` (Blueprint đã khai báo `dockerContext: ./backend`). Nếu tạo service thủ công thì đặt `backend`.
   - **Environment**: `Docker` (Render sẽ tự tìm `backend/Dockerfile`)
4. Khai báo **Environment Variables** trong tab Environment. Tên biến phải đúng chính xác như bảng dưới — ASP.NET Core dùng `__` để phân tách section:

| Variable | Sample / Description |
|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `ConnectionStrings__DefaultConnection` | `postgresql://<user>:<password>@ep-xyz.neon.tech/neondb?sslmode=require&channel_binding=require` |
| `JWT__KEY` | `<GENERATE_A_RANDOM_SECRET_OF_AT_LEAST_32_CHARACTERS>` |
| `GEMINI__APIKEY` | Gemini API key vừa tạo ở bước 1 |
| `CORS__ALLOWEDORIGINS__0` | `https://<tên-project>.vercel.app` (không có path, không có dấu `/` cuối) |

> Không dùng các biến thể `Jwt__Key` hay `Gemini__ApiKey` — tài liệu cũ từng ghi sai. Chuỗi `JWT__KEY` phải được sinh ngẫu nhiên; app từ chối khởi động nếu key ngắn hơn 32 ký tự hoặc trùng một placeholder đã biết.
>
> Connection string bắt buộc có cả `sslmode=require` và `channel_binding=require`; backend từ chối `sslmode=disable|allow|prefer`.

5. Chọn **Create Web Service** và chờ Render hoàn tất build & deploy.

---

## 4. Build và Deploy Flutter Web (Vercel)

1. Truy cập [Vercel Dashboard](https://vercel.com/dashboard) và chọn **Add New** -> **Project**.
2. Import repository `trangkhanh-ai/Calories-Tracking-App`.
3. Cấu hình Project Settings:
   - **Framework Preset**: `Other`
   - **Root Directory**: `.` — **giữ nguyên gốc repository**. Dự án Flutter nằm ở gốc repo (`pubspec.yaml`, `lib/`, `web/` đều ở đó), nên đổi Root Directory sang thư mục con sẽ làm build fail.
   - **Build Command**:
     ```bash
     bash scripts/vercel-build.sh
     ```
   - **Output Directory**: `build/web`
4. Cấu hình Environment Variable (**bắt buộc** — script build sẽ dừng nếu thiếu):
   - `BACKEND_BASE_URL`: `https://calories-tracking-api.onrender.com`

   Đây là cấu hình công khai, không phải secret. Script từ chối giá trị: thiếu, không phải HTTPS, có `/api`, có dấu `/` cuối, có path/query/fragment, có credentials nhúng, hoặc trỏ tới loopback (`localhost`, `127.0.0.1`, `::1`).

   Flutter SDK được pin cứng ở `3.44.1` trong `scripts/vercel-build.sh`, khớp với `.github/workflows/flutter-ci.yml`. Khi nâng version phải sửa cả hai nơi.
5. Chọn **Deploy**. File `vercel.json` trong repository sẽ tự động cấu hình SPA rewrite (`/index.html`) và security headers. Vercel sẽ tự động build frontend Web khi có commit vào `main` dựa trên cấu hình `vercel.json`.

---

## 5. Quy Trình Smoke Test Production

Sau khi triển khai hoàn tất cả 2 dịch vụ, thực hiện chuỗi test kiểm tra hệ thống:

### 5.1 Backend Health & Database Check
```bash
curl -i https://calories-tracking-api.onrender.com/health
```
- **Kỳ vọng**: HTTP 200 OK với body `{"status":"ok"}`.

### 5.2 Registration & Authentication Test
```bash
curl -i -X POST https://calories-tracking-api.onrender.com/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "smoketest_user",
    "email": "smoke@example.com",
    "password": "Password123!",
    "displayName": "Smoke Tester"
  }'
```
- **Kỳ vọng**: HTTP 200 OK trả về `token` JWT (hoặc 409 Conflict nếu user đã tồn tại).

### 5.3 Food Search API Check
```bash
curl -i "https://calories-tracking-api.onrender.com/api/food/search?query=pho&limit=5"
```
- **Kỳ vọng**: HTTP 200 OK trả về danh sách món ăn từ cơ sở dữ liệu USDA / PostgreSQL.

### 5.4 Diary Logging & Stats Check
```bash
curl -i -X POST https://calories-tracking-api.onrender.com/api/diary \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "foodName": "Phở Bò",
    "caloriesPer100g": 150,
    "quantity": 200,
    "mealType": "Breakfast",
    "date": "2026-07-25T00:00:00Z"
  }'
```
- **Kỳ vọng**: HTTP 200 OK với body chứa cả `message` và `diary`:
  ```json
  { "message": "Meal logged successfully.", "diary": { "date": "...", "breakfast": [ ... ] } }
  ```
  Trường `diary` là state chuẩn từ server; client dùng nó thay vì tự tạo entry cục bộ. Trường `message` được giữ lại để client cũ không vỡ.

```bash
curl -i "https://calories-tracking-api.onrender.com/api/diary/daily?date=2026-07-25" \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>"
```
- **Kỳ vọng**: HTTP 200 OK trả về dữ liệu nhật ký bữa ăn trong ngày.

### 5.5 Gemini Image Analysis Check
Send a valid base64 food image to `/api/analysis/food` with Authorization token.
- **Kỳ vọng**: HTTP 200 OK trả về thông tin món ăn và dinh dưỡng phân tích bởi Gemini API.

### 5.6 CORS Preflight Check
Kiểm tra endpoint có trả về đúng Access-Control-Allow-Origin:
```bash
curl -i -X OPTIONS https://calories-tracking-api.onrender.com/health \
  -H "Origin: https://<tên-project>.vercel.app" \
  -H "Access-Control-Request-Method: GET"
```
- **Kỳ vọng**: HTTP 204 No Content và có header `Access-Control-Allow-Origin: https://<tên-project>.vercel.app`.

### 5.7 Vercel Deep-link / SPA Check
Truy cập trực tiếp rồi tải lại (F5) từng đường dẫn sau:

- `/login`
- `/profile`
- `/diary`
- `/goal-setup`
- `/results`

- **Kỳ vọng**: mỗi trang tải bình thường, không 404. Đồng thời mở DevTools → Network và xác nhận các file tĩnh (`main.dart.js`, `/assets/*`, `/canvaskit/*`) trả về đúng content-type, **không** bị rewrite thành `index.html`.

### 5.8 Gemini Error Path Check
Với JWT hợp lệ, gửi lần lượt:

| Trường hợp | Cách tạo | Kỳ vọng |
|---|---|---|
| 413 | Ảnh JPEG/PNG giải mã > 5 MB | HTTP 413, app hiện "Ảnh quá lớn (giới hạn 5 MB sau khi giải mã)" |
| 415 | File BMP hoặc GIF | HTTP 415, app hiện "Định dạng ảnh không được hỗ trợ. Chỉ chấp nhận JPEG, PNG hoặc WebP." |
| 429 | Gọi `/api/analysis/food` 6 lần trong 1 phút | HTTP 429, app hiện thông báo chờ, **không** tự động retry |
| 503 | Tạm đặt `GEMINI__APIKEY` sai rồi khôi phục | HTTP 503, app hiện lỗi tạm thời |

Tất cả response lỗi phải có `Content-Type: application/problem+json` và chứa `traceId`. Không được lộ stack trace, SQL, connection string hay nội dung ảnh.

### 5.9 JWT Expiration Check
1. Đăng nhập, mở DevTools → Application → Local Storage, sao chép `jwt_token`.
2. Sửa `exp` trong payload thành thời điểm quá khứ (hoặc chờ token 7 ngày hết hạn).
3. Tải lại app.
- **Kỳ vọng**: app tự xóa token, chuyển về màn hình đăng nhập, **không** lặp vô hạn giữa các route.
- Thử tiếp: mở 2 tab cùng lúc rồi để cả hai gặp 401 — chỉ một lần logout được thực hiện.

### 5.10 Render Cold Start Check
1. Để service Render Free ngủ (không truy cập ~15 phút).
2. Mở app và tải nhật ký.
- **Kỳ vọng**: request GET tự retry tối đa 2 lần (chờ 1s rồi 2s). App hiện "Máy chủ đang khởi động..." chứ không phải "Không có kết nối mạng".

### 5.11 Diary Backend Failure Check
1. Tạm dừng service Render (hoặc ngắt mạng sau khi app đã tải).
2. Trong app, thử lưu một bữa ăn từ màn hình Tra cứu thực phẩm và từ màn hình Kết quả scan.
- **Kỳ vọng**: app hiện thông báo lỗi rõ ràng, **không** hiện "đã lưu thành công", và form vẫn mở để người dùng thử lại thủ công.
3. Khôi phục service, tải lại nhật ký.
- **Kỳ vọng**: không có entry trùng lặp — bữa ăn thất bại trước đó không được ghi cục bộ.

### 5.12 Neon Persistence Check
1. Ghi một bữa ăn qua app.
2. Trên Render dashboard chọn **Manual Deploy** → **Restart service**.
3. Sau khi service khởi động lại, tải lại nhật ký.
- **Kỳ vọng**: dữ liệu vẫn còn (Neon là nơi lưu trữ, không phải ổ đĩa của Render).
- Kiểm tra log khởi động: seeder USDA phải báo `already completed`, **không** import lại từ đầu.

---

## 6. Frontend deployment: chỉ dùng Vercel

Vercel là nền tảng deploy frontend duy nhất. Workflow GitHub Pages
(`.github/workflows/deploy.yml`) đã bị vô hiệu hóa (chỉ chạy khi
`workflow_dispatch` thủ công) để tránh hai đường deploy cạnh tranh nhau và hai
origin cần khai báo CORS.

`CORS__ALLOWEDORIGINS__0` vì vậy chỉ cần chứa origin Vercel.

---
