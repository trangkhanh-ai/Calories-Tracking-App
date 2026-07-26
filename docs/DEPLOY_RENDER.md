# Deploy Flutter Web trên Vercel, .NET trên Render và PostgreSQL trên Neon

## PR14 Render Operator Checklist

Use this checklist for the controlled release; the longer sections below remain
the general platform guide.

### Before applying the Blueprint

- Deploy the reviewed commit only. Confirm `render.yaml` defines one Docker web
  service, readiness path `/health`, `SEEDING__ENABLED=true`, and no Render
  database resource.
- Create a new, dedicated, empty Neon database. Existing schemas, legacy data,
  or shared databases are outside the verified PR14 deployment path.
- Rotate the historically exposed Gemini key and generate a new random JWT key
  of at least 32 characters.
- Confirm all dashboard-managed entries remain `sync: false`:
  `ConnectionStrings__DefaultConnection`, `JWT__KEY`, `GEMINI__APIKEY`, and
  `CORS__ALLOWEDORIGINS__0`.
- `sync: false` prompts only during initial Blueprint creation. On an existing
  service, inspect and update these values directly in the Render Dashboard;
  applying a Blueprint update does not prompt for them again.

### Required values

```text
ASPNETCORE_ENVIRONMENT=Production
HOSTING__BEHINDTLSTERMINATINGPROXY=true
SEEDING__ENABLED=true
ConnectionStrings__DefaultConnection=postgresql://<user>:<password>@<neon-host>/<database>?sslmode=require&channel_binding=require
JWT__KEY=<RANDOM_SECRET_AT_LEAST_32_CHARACTERS>
GEMINI__APIKEY=<NEWLY_ROTATED_GEMINI_KEY>
CORS__ALLOWEDORIGINS__0=https://<project>.vercel.app
```

Render terminates public TLS and forwards requests to the HTTP container. Proxy
mode is an explicit security boundary: forwarded headers are trusted only for
the immediate Render hop with `ForwardLimit=1`. The middleware resolves client
IP before rate limiting, so do not enable proxy mode on a directly exposed
container or behind an unreviewed chain that could spoof forwarded IPs. The app
disables its own HTTPS redirection in proxy mode because Render redirects at the
edge. Ordinary Development keeps proxy mode off and does not trust forwarded
headers.

### Startup evidence

Inspect Render logs and record sanitized evidence that:

1. PostgreSQL migrations complete successfully.
2. The first USDA import reports `USDA seed completed` with a plausible count.
3. A restart reports `already completed` instead of importing from row one.
4. No connection string, JWT, Gemini key, SQL parameter, or image content is
   printed.

`/health/live` is liveness and must return HTTP 200 with `{"status":"ok"}`
without querying Neon. `/health` is database readiness and must return the same
body with HTTP 200 only when Neon is reachable; Render monitors `/health`.

### Rollback and release decision

- Roll back Render to the last known-good immutable commit/image.
- Keep Neon intact, never apply an automatic down-migration, and never insert,
  delete, or edit `__EFMigrationsHistory` rows manually.
- Verify schema compatibility before the old application receives traffic. If
  uncertain, restore or branch from the recorded Neon recovery point into a
  separate database and validate it first.
- Repeat both health checks plus authentication, seeded search, and a database
  write/read check after rollback.

The CI smoke environment does not equal Render/Neon/Vercel staging. It cannot
prove provider TLS termination, cold start behavior, production CORS, DNS, or
dashboard configuration. Without authorized staging access, record these items
as `NOT RUN` and require human approval before production deployment.

Tài liệu này mô tả nền tảng production của Calories Tracking App:

- Flutter Web trên Vercel.
- .NET 9 API dưới dạng một Render Web Service Free.
- PostgreSQL trên Neon Free.

Không tạo Render Postgres. Không đưa JWT key, Gemini key hoặc Neon connection string vào source, Flutter build hay GitHub Repository Variables.

## 1. Chuẩn bị Neon Free

1. Tạo project PostgreSQL trên Neon Free.
2. Mở trang **Connection Details** và sao chép PostgreSQL URI.
3. Giữ các tham số TLS mà Neon cung cấp, đặc biệt:

   ```text
   postgresql://<user>:<password>@<host>/<database>?sslmode=require&channel_binding=require
   ```

4. Không ghi URI thật vào file, issue, log hoặc tài liệu. URI chỉ được nhập vào Render bằng biến `ConnectionStrings__DefaultConnection`.

Backend hỗ trợ cả PostgreSQL URI và Npgsql keyword connection string. Production từ chối SQLite hoặc connection string không hợp lệ. EF Core tự chạy bộ migration PostgreSQL khi API khởi động; production không dùng `EnsureCreated`.

## 2. Tạo Render Blueprint

1. Fork hoặc push branch đã review lên GitHub.
2. Trong Render, chọn **New > Blueprint** và kết nối repository.
3. Render đọc `render.yaml`. Trước khi Apply, xác nhận Blueprint có:
   - đúng một service loại `web`;
   - runtime `docker`;
   - plan `free`;
   - health check `/health`;
   - không có mục `databases` hoặc Render Postgres.
4. Nhập các biến được đánh dấu `sync: false`:

   | Biến | Giá trị |
   |---|---|
   | `ConnectionStrings__DefaultConnection` | Neon PostgreSQL URI đầy đủ |
   | `JWT__KEY` | Chuỗi bí mật ngẫu nhiên tối thiểu 32 ký tự |
   | `GEMINI__APIKEY` | Gemini API key còn hiệu lực |
   | `CORS__ALLOWEDORIGINS__0` | Origin Vercel, ví dụ `https://<tên-project>.vercel.app` |

`CORS__ALLOWEDORIGINS__0` là origin, không phải URL đầy đủ của repository. Không thêm `/Calories-Tracking-App`, query string hoặc dấu `/` cuối.

## 3. Kiểm tra API và health endpoint

API cung cấp hai health endpoint với mục đích khác nhau:

- `GET /health/live` là process liveness: chỉ xác nhận process/API đang phục vụ request, không truy cập database và trả HTTP 200 khi process còn sống.
- `GET /health` là database readiness: kiểm tra kết nối database, trả HTTP 200 khi database truy cập được và HTTP 503 khi service chưa sẵn sàng.

Render dùng `/health` theo `healthCheckPath` trong `render.yaml`. HTTP 503 từ endpoint này có nghĩa service chưa sẵn sàng truy cập database; điều đó không nhất thiết có nghĩa process API đã chết. Health response chỉ trả trạng thái chung, không chứa exception hoặc connection string.

Sau khi Render báo service chạy, dùng URL thật trên dashboard:

```bash
curl --fail --show-error https://<service-name>.onrender.com/health
```

Kết quả mong đợi:

```json
{"status":"ok"}
```

Render Free có thể cold start sau thời gian không hoạt động. Lần gọi đầu có thể chậm; chỉ kết luận lỗi sau khi kiểm tra Render logs và thử lại.

Để kiểm tra riêng process liveness mà không phụ thuộc database:

```bash
curl --fail --show-error https://<service-name>.onrender.com/health/live
```

Nếu API không khởi động, kiểm tra log theo thứ tự:

1. Production connection string có phải PostgreSQL/Neon hay không.
2. `JWT__KEY` có tối thiểu 32 ký tự hay không.
3. `GEMINI__APIKEY` có bị thiếu hay không.
4. CORS có phải một hoặc nhiều HTTPS origin an toàn hay không.
5. Migration PostgreSQL có chạy thành công hay không.

Không dán giá trị secret vào log, issue hoặc pull request khi xử lý lỗi.

## 4. Cấu hình Vercel

Trên Vercel dashboard:

1. Import GitHub repository.
2. Thiết lập Environment Variable trong phần Settings > Environment Variables:

   ```text
   BACKEND_BASE_URL=https://<service-name>.onrender.com
   ```

Giá trị này là cấu hình công khai cho Flutter Web, không phải secret. Không thêm `/api`, path khác hoặc dấu `/` cuối. Workflow từ chối giá trị thiếu, HTTP, malformed hoặc loopback.

Vercel sẽ tự động đọc `vercel.json` và chạy script `scripts/vercel-build.sh` khi có commit vào `main`.

## 5. Kiểm tra end-to-end

Chỉ tuyên bố deploy hoàn tất sau khi kiểm tra URL thật:

1. `GET https://<service-name>.onrender.com/health` trả HTTP 200.
2. Kiểm tra CORS preflight: `curl -i -X OPTIONS https://<service-name>.onrender.com/health -H "Origin: https://<tên-project>.vercel.app" -H "Access-Control-Request-Method: GET"` trả HTTP 204.
3. Mở URL Vercel và kiểm tra trang tải không có mixed-content error.
4. Truy cập URL sâu trên Vercel (vd: `/goal-setup`) và tải lại trang để kiểm tra rewrite SPA không lỗi 404.
5. Đăng ký hoặc đăng nhập để xác minh request API đi đến Render.
6. Kiểm tra Browser DevTools để xác nhận response có CORS hợp lệ.
7. Thử một request phân tích ảnh sau khi có JWT để xác minh Gemini key hoạt động.
8. Restart/redeploy Render rồi kiểm tra dữ liệu vẫn tồn tại trên Neon.

Nếu chưa có credential, quyền GitHub/Render hoặc URL thật, ghi rõ các bước chưa kiểm tra; không suy diễn rằng deployment đã thành công.

## 6. Rollback và bảo mật

- Rollback ứng dụng bằng một commit/redeploy đã biết tốt; không thay đổi hoặc xóa Neon project trong quá trình rollback ứng dụng.
- Không force-push hoặc rewrite Git history trong quy trình deploy này.
- Nếu key từng xuất hiện trong Git history hoặc bundle, phải revoke/rotate tại nhà cung cấp. Xóa key khỏi phiên bản hiện tại không vô hiệu hóa bản đã lộ.
- Không đưa `ConnectionStrings__DefaultConnection`, `JWT__KEY` hoặc `GEMINI__APIKEY` vào Flutter `--dart-define`.
