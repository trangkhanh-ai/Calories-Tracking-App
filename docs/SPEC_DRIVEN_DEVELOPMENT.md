# Hướng dẫn chi tiết: Spec-Driven Development (SDD) và Ứng dụng thực tế

Tài liệu này được tổng hợp từ nguồn chính thức của **GitHub Spec-Kit**, nhằm giải thích khái niệm Spec-Driven Development (Phát triển hướng Đặc tả) và cách nhóm chúng ta áp dụng phương pháp này vào dự án **Calories-Tracking-App**.

---

## 1. Spec-Driven Development (SDD) là gì?

**Sự Đảo Ngược Quyền Lực (The Power Inversion)**
Trong nhiều thập kỷ, Code luôn là "vua". Các tài liệu đặc tả (Specs), yêu cầu (PRD), hay thiết kế thường chỉ đóng vai trò "giàn giáo" hướng dẫn lập trình viên, và nhanh chóng bị lỗi thời ngay khi dòng code đầu tiên được viết ra. Code là sự thật duy nhất.

**Spec-Driven Development (SDD)** đảo ngược hoàn toàn cấu trúc quyền lực này:
> **Tài liệu Đặc tả không phục vụ cho Code. Code phải phục vụ cho Tài liệu Đặc tả.**

Trong SDD, tài liệu đặc tả trở thành *Executable Specifications* (Đặc tả có thể thực thi). Đặc tả chính là Nguồn Chân Lý Duy Nhất (Single Source of Truth). Code chỉ là kết quả phái sinh, được sinh ra để thỏa mãn chính xác những gì đặc tả đã quy định. Khi phần mềm cần nâng cấp, lập trình viên sẽ "bảo trì đặc tả" trước, sau đó code sẽ được tạo/sửa đổi tương ứng.

---

## 2. Các Nguyên Tắc Cốt Lõi (Core Principles)

Dựa trên "Hiến pháp" (Constitution) của GitHub Spec-Kit, SDD vận hành trên các nguyên tắc bất di bất dịch sau:

1. **Đặc tả là ngôn ngữ chung (Specifications as the Lingua Franca):** Tư duy phát triển xoay quanh việc định nghĩa "Cái gì" (What) và "Tại sao" (Why) thông qua ngôn ngữ tự nhiên, trước khi đụng đến "Làm như thế nào" (How).
2. **Sự chính xác và Không mơ hồ (Executable & Unambiguous):** Đặc tả phải đủ chi tiết đến mức máy móc (AI/Automation) có thể đọc và sinh ra code. Bất kỳ sự mơ hồ nào cũng phải được đánh dấu `[NEEDS CLARIFICATION]`.
3. **Tuân thủ Test-First (Điều khoản III):** KHÔNG BAO GIỜ viết code chức năng trước khi viết test. Đặc tả phải bao gồm tiêu chí chấp nhận (Acceptance Criteria), từ đó sinh ra Unit Test trước, sau đó mới viết code để pass bài test đó.
4. **Nguyên tắc Đơn giản hóa (Articles VII & VIII):** Bắt đầu với kiến trúc đơn giản nhất có thể. Không "Over-engineering" (làm phức tạp hóa vấn đề hoặc đoán trước tương lai).
5. **Cải tiến liên tục (Continuous Refinement):** Feedback từ quá trình chạy thực tế (Lỗi, Crash, Hiệu năng) sẽ được đưa ngược lại để cập nhật tài liệu Đặc tả.

---

## 3. Quy trình làm việc (The Workflow)

Quy trình phát triển một tính năng theo SDD trải qua 4 bước chuẩn hóa:

1. **Specify (Đặc tả):** Xác định chính xác yêu cầu của tính năng, các kịch bản người dùng (User Stories). *Tuyệt đối không bàn về công nghệ ở bước này.*
2. **Plan (Lập kế hoạch):** Lựa chọn Tech-stack (Công nghệ), thiết kế luồng dữ liệu, tạo API Contract.
3. **Tasks (Chia việc):** Biến bản kế hoạch thành các checklist công việc cụ thể. Các task nào không phụ thuộc nhau có thể làm song song `[P]`.
4. **Implement (Triển khai):** Viết code tuân thủ nghiêm ngặt 100% theo bản Đặc tả đã chốt.

---

## 4. Áp dụng SDD vào dự án Calories-Tracking-App

Trong đồ án này, chúng ta đã ứng dụng triệt để triết lý SDD để kết nối 2 thành phần phức tạp: **Ứng dụng Flutter (Front-end)** và **Google Gemini Vision AI (Back-end logic)**.

### Bước 1 & 2: Specify và Plan (Tạo nguồn chân lý)
Thay vì code thẳng vào màn hình ứng dụng rồi "cầu nguyện" con AI Gemini sẽ trả về đúng định dạng, chúng ta đã dừng lại và xây dựng file `docs/API_SPEC.md`.
- Đặc tả rõ AI bắt buộc trả về một file `JSON` với các trường cụ thể: `total_calories`, `total_protein`, mảng `items`.
- Kế hoạch xử lý các ngoại lệ được quy định bằng văn bản: *Nếu ảnh tối (`low_light`) thì hiển thị cảnh báo; Nếu không có đồ ăn (`food_detected: false`) thì chặn kết quả.*

### Bước 3 & 4: Implement (Triển khai chính xác tuyệt đối)
- Team làm giao diện (UI) thiết kế toàn bộ màn hình `ResultsScreen` chỉ dựa vào bản JSON giả lập từ Spec.
- Team AI (Logic) code hàm gọi API Gemini và ép kiểu (Prompt Tuning) để Gemini xuất ra đúng cấu trúc JSON đó.
- **Kết quả:** Khi ghép nối Code, mọi thứ hoạt động khớp nhau 100%. App không bị crash vì lỗi kiểu dữ liệu hay thiếu trường `null`, nhờ vào sự bảo vệ của Đặc tả.

### Định hướng tiếp theo cho đồ án
Để nâng cấp ứng dụng chuẩn SDD hơn nữa, chúng ta có thể:
1. **Viết Unit Test (Test-Driven):** Căn cứ vào Spec, viết test cho hàm `parseJson()` trước, sau đó mới viết code parsing.
2. **Tự động hóa (Automation):** Dùng công cụ để tự động đọc file `API_SPEC.md` và sinh ra class `FoodAnalysisResult.dart` thay vì tự gõ tay.
