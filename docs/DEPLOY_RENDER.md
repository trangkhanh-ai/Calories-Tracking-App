# Deploy Flutter Web, Render Free và Neon Free

Tài liệu này mô tả nền tảng production của Calories Tracking App:

- Flutter Web trên GitHub Pages.
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
   | `CORS__ALLOWEDORIGINS__0` | Origin Pages, ví dụ `https://<owner>.github.io` |

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

## 4. Cấu hình GitHub Pages

Trong GitHub repository:

1. Mở **Settings > Pages** và chọn **GitHub Actions** làm source.
2. Mở **Settings > Secrets and variables > Actions > Variables**.
3. Tạo Repository Variable:

   ```text
   BACKEND_BASE_URL=https://<service-name>.onrender.com
   ```

Giá trị này là cấu hình công khai cho Flutter Web, không phải secret. Không thêm `/api`, path khác hoặc dấu `/` cuối. Workflow từ chối giá trị thiếu, HTTP, malformed hoặc loopback.

Workflow `.github/workflows/deploy.yml` chạy khi push `main` hoặc khi được kích hoạt thủ công. Không push/merge cho đến khi pull request đã được review và test.

## 5. Kiểm tra end-to-end

Chỉ tuyên bố deploy hoàn tất sau khi kiểm tra URL thật:

1. `GET https://<service-name>.onrender.com/health` trả HTTP 200.
2. Mở URL GitHub Pages và kiểm tra trang tải không có mixed-content error.
3. Đăng ký hoặc đăng nhập để xác minh request API đi đến Render.
4. Kiểm tra Browser DevTools để xác nhận response có CORS hợp lệ.
5. Thử một request phân tích ảnh sau khi có JWT để xác minh Gemini key hoạt động.
6. Restart/redeploy Render rồi kiểm tra dữ liệu vẫn tồn tại trên Neon.

Nếu chưa có credential, quyền GitHub/Render hoặc URL thật, ghi rõ các bước chưa kiểm tra; không suy diễn rằng deployment đã thành công.

## 6. Rollback và bảo mật

- Rollback ứng dụng bằng một commit/redeploy đã biết tốt; không thay đổi hoặc xóa Neon project trong quá trình rollback ứng dụng.
- Không force-push hoặc rewrite Git history trong quy trình deploy này.
- Nếu key từng xuất hiện trong Git history hoặc bundle Pages, phải revoke/rotate tại nhà cung cấp. Xóa key khỏi phiên bản hiện tại không vô hiệu hóa bản đã lộ.
- Không đưa `ConnectionStrings__DefaultConnection`, `JWT__KEY` hoặc `GEMINI__APIKEY` vào Flutter `--dart-define`.
