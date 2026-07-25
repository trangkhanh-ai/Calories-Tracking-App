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
5. **LƯU Ý BẢO MẬT**: Không bao giờ commit key vào source code hoặc đưa vào build frontend. Key này chỉ được đặt tại biến môi trường `Gemini__ApiKey` trên Render.

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
   - **Root Directory**: `backend` (hoặc để trống nếu dùng `render.yaml`)
   - **Environment**: `Docker` (Render sẽ tự tìm `backend/Dockerfile`)
4. Khai báo **Environment Variables** trong tab Environment:

| Variable | Sample / Description |
|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `ConnectionStrings__DefaultConnection` | `postgresql://user:pass@ep-xyz.neon.tech/neondb?sslmode=require&channel_binding=require` |
| `JWT__KEY` | `[Mật khẩu ngẫu nhiên tối thiểu 32 ký tự, không lưu ở text]` |
| `GEMINI__APIKEY` | `[Gemini API Key vừa tạo]` |
| `CORS__ALLOWEDORIGINS__0` | `https://<tên-project>.vercel.app` |

5. Chọn **Create Web Service** và chờ Render hoàn tất build & deploy.

---

## 4. Build và Deploy Flutter Web (Vercel)

1. Truy cập [Vercel Dashboard](https://vercel.com/dashboard) và chọn **Add New** -> **Project**.
2. Import repository `trangkhanh-ai/Calories-Tracking-App`.
3. Cấu hình Project Settings:
   - **Framework Preset**: `Other`
   - **Build Command**:
     ```bash
     bash scripts/vercel-build.sh
     ```
   - **Output Directory**: `build/web`
4. Cấu hình Environment Variable (tùy chọn nếu muốn override dynamic build):
   - `BACKEND_BASE_URL`: `https://calories-tracking-api.onrender.com` *(Lưu ý: KHÔNG thêm `/api` ở cuối URL)*
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
- **Kỳ vọng**: HTTP 200 OK `{"message":"Meal logged successfully."}`.

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
- Truy cập trực tiếp đường dẫn sâu (ví dụ: `https://<tên-project>.vercel.app/goal-setup`).
- Tải lại trang (F5).
- **Kỳ vọng**: Ứng dụng tải lên bình thường, không bị lỗi 404.

---
