# Kế hoạch triển khai: Tùy chỉnh Mục tiêu Calo & Tính toán TDEE/BMI

Hiện tại, ứng dụng đang khóa cứng mục tiêu calo mỗi ngày là `2000 kcal`. Để giúp người dùng cá nhân hóa lộ trình sức khỏe, chúng ta sẽ xây dựng tính năng cho phép người dùng tính toán chỉ số khối cơ thể (BMI), tổng năng lượng tiêu hao (TDEE) và tự động đề xuất/tùy chỉnh mục tiêu calo.

## User Review Required
> [!IMPORTANT]
> - Chúng ta sẽ thêm một màn hình **Hồ sơ (Profile)** mới vào ứng dụng. Bạn muốn màn hình này được truy cập từ đâu? (Ví dụ: Thêm một icon ở góc phải trang chủ (Home), hoặc thêm một tab "Hồ Sơ" vào thanh điều hướng bên dưới - Bottom Navigation Bar).
> - Giao diện tính toán sẽ yêu cầu người dùng nhập: Tuổi, Giới tính, Chiều cao, Cân nặng, Mức độ vận động, và Mục tiêu (Giảm cân / Giữ dáng / Tăng cân). Bạn có đồng ý với các trường thông tin này không?

## Proposed Changes

### Tính năng Tính toán (Core Logic)
#### [NEW] `lib/features/profile/utils/calculator_utils.dart`
- Viết các hàm tính toán y khoa chuẩn:
  - **BMI:** `Cân nặng(kg) / (Chiều cao(m))^2`
  - **BMR (Mifflin-St Jeor):** 
    - Nam: `(10 × kg) + (6.25 × cm) - (5 × tuổi) + 5`
    - Nữ: `(10 × kg) + (6.25 × cm) - (5 × tuổi) - 161`
  - **TDEE:** `BMR × Hệ số vận động`
  - **Khuyến nghị Calo:** Giảm cân (-500 kcal), Giữ nguyên (TDEE), Tăng cân (+500 kcal).

### State Management (Lưu trữ và Quản lý trạng thái)
#### [MODIFY] `lib/features/diary/providers/diary_provider.dart`
- Xóa `final dailyGoalProvider = StateProvider<int>((ref) => 2000);` cũ (vốn đang bị fix cứng).

#### [NEW] `lib/features/profile/providers/settings_provider.dart`
- Khởi tạo `SettingsNotifier` để đọc/ghi mục tiêu Calo từ `SharedPreferences`.
- Cập nhật luồng dữ liệu để toàn bộ ứng dụng (kể cả vòng tròn tiến độ trên trang Chủ) tự động phản hồi khi người dùng đổi mục tiêu.

### Giao diện (UI)
#### [NEW] `lib/features/profile/screens/profile_screen.dart`
- Tạo màn hình Hồ sơ hiển thị form nhập liệu: Tuổi, Giới tính, Cân nặng, Chiều cao.
- Dropdown chọn: Mức độ hoạt động (Ít vận động, Vận động nhẹ, Vận động vừa, Vận động nhiều).
- Dropdown chọn: Mục tiêu (Giảm cân, Giữ cân, Tăng cân).
- Nút "Tính toán & Áp dụng": Hiển thị bảng kết quả BMI, TDEE và gợi ý số Calo cần nạp. Đồng thời lưu con số này làm `daily_goal` mới.

#### [MODIFY] `lib/app/router.dart`
- Thêm đường dẫn (route) mới `/profile` để điều hướng đến `ProfileScreen`.

#### [MODIFY] `lib/features/home/screens/home_screen.dart`
- Thêm nút (icon) "Hồ sơ cá nhân" ở góc phải AppBar để người dùng dễ dàng bấm vào xem và đổi mục tiêu calo.

---

## Verification Plan

### Automated Tests
- Chạy `flutter analyze` để đảm bảo không có lỗi cú pháp.

### Manual Verification
- Chạy ứng dụng trên trình duyệt Chrome (`flutter run -d chrome`).
- Bấm vào nút Hồ sơ ở góc phải trang chủ.
- Nhập thông tin: Nam, 25 tuổi, 175cm, 70kg, Vận động vừa, Mục tiêu Giữ cân.
- Nhấn tính toán: Kiểm tra xem thuật toán có ra kết quả TDEE khoảng 2500-2600 kcal không.
- Nhấn Áp dụng: Quay lại trang chủ, kiểm tra xem vòng tròn tiến độ đã tự động chuyển từ mục tiêu `2000` thành `2500` chưa.
- Tải lại ứng dụng (F5): Kiểm tra xem mục tiêu mới có được lưu lại vào bộ nhớ cục bộ (SharedPreferences) không, hay bị reset về 2000.
