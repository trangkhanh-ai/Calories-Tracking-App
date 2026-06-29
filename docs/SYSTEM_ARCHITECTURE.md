# 📊 Phân Tích Luồng Hoạt Động Dữ Liệu - Calories-Tracking-App

---

## 1. Kiến Trúc Tổng Quan (Architecture Overview)

```mermaid
graph TB
    subgraph "🖥️ FRONTEND - Flutter Web"
        UI["🎨 Giao diện người dùng<br/>(Flutter Widgets)"]
        PROV["📦 State Management<br/>(Riverpod Providers)"]
        SVC["🔌 API Services<br/>(Dio HTTP Client)"]
        LOCAL["💾 Local Storage<br/>(Isar & SharedPreferences)"]
    end

    subgraph "🛡️ PROXY LAYER"
        EXPRESS["🚀 Node.js Express Proxy<br/>(localhost:3000)"]
    end

    subgraph "☁️ EXTERNAL API"
        GEMINI["🤖 Google Gemini AI<br/>(Vision API)"]
    end

    subgraph "⚙️ BACKEND - .NET 8 API"
        CTRL["🎯 Controllers<br/>(API Endpoints)"]
        BIZ["🧠 Application Services<br/>(Business Logic)"]
        REPO["📂 Repositories<br/>(Data Access)"]
        AUTH_MW["🔐 JWT Middleware<br/>(Authentication)"]
    end

    subgraph "🗄️ DATABASE - SQLite"
        DB_USER["👤 Users"]
        DB_FOOD["🍕 Foods<br/>(USDA Dataset)"]
        DB_LOG["📅 DailyLogs"]
        DB_MEAL["🍽️ MealItems"]
    end

    UI --> PROV
    PROV --> SVC
    SVC -->|"HTTP REST<br/>localhost:5210"| AUTH_MW
    SVC -->|"JWT Token"| LOCAL
    UI -->|"📷 Ảnh chụp (Base64)"| EXPRESS
    EXPRESS -->|"Gắn API Key an toàn"| GEMINI

    AUTH_MW --> CTRL
    CTRL --> BIZ
    BIZ --> REPO
    REPO --> DB_USER
    REPO --> DB_FOOD
    REPO --> DB_LOG
    REPO --> DB_MEAL

    style UI fill:#4FC3F7,color:#000
    style GEMINI fill:#FF7043,color:#fff
    style CTRL fill:#66BB6A,color:#000
    style DB_USER fill:#FFD54F,color:#000
    style DB_FOOD fill:#FFD54F,color:#000
    style DB_LOG fill:#FFD54F,color:#000
    style DB_MEAL fill:#FFD54F,color:#000
```

---

## 2. Sơ Đồ Database (Entity Relationship)

```mermaid
erDiagram
    Users {
        int Id PK
        string Username UK
        string PasswordHash
        string Email UK
        string DisplayName
        string AvatarUrl
        decimal Height
        decimal Weight
        int Age
        string Gender
        int TargetCalories
    }

    Foods {
        int Id PK
        int FdcId
        string Name
        string SourceType
        decimal CaloriesPer100g
        decimal Protein
        decimal Carbs
        decimal Fat
        decimal Sugar
        decimal Fiber
        decimal Sodium
    }

    DailyLogs {
        int Id PK
        int UserId FK
        date Date
        decimal TotalCaloriesConsumed
    }

    MealItems {
        int Id PK
        int DailyLogId FK
        int FoodId FK
        decimal Quantity
        decimal TotalCalories
        string MealType
    }

    Users ||--o{ DailyLogs : "has many"
    DailyLogs ||--o{ MealItems : "contains"
    Foods ||--o{ MealItems : "referenced by"
```

---

## 3. Luồng Từng Tính Năng

### 🔐 Luồng 1: Đăng Ký / Đăng Nhập (Auth)

```mermaid
sequenceDiagram
    participant U as 👤 Người dùng
    participant F as 📱 Flutter UI
    participant S as 💾 SharedPreferences
    participant A as ⚙️ AuthController
    participant DB as 🗄️ SQLite

    Note over U,DB: === ĐĂNG KÝ ===
    U->>F: Nhập Username, Email, Password
    F->>A: POST /api/auth/register
    A->>DB: Tạo User mới (hash password)
    DB-->>A: User đã tạo
    A-->>F: JWT Token + User Info
    F->>S: Lưu JWT Token vào SharedPreferences

    Note over U,DB: === ĐĂNG NHẬP ===
    U->>F: Nhập Username + Password
    F->>A: POST /api/auth/login
    A->>DB: Kiểm tra User + so sánh hash
    DB-->>A: User hợp lệ
    A-->>F: JWT Token + User Info
    F->>S: Lưu JWT Token

    Note over F,A: Mọi request sau đó đều gắn<br/>Header: Authorization: Bearer {token}
```

### 📅 Luồng 2: Xem Nhật Ký Hôm Nay (Diary - Trang Chủ)

```mermaid
sequenceDiagram
    participant U as 👤 Người dùng
    participant F as 📱 Flutter UI
    participant P as 📦 DiaryProvider
    participant A as ⚙️ DiaryController
    participant SVC as 🧠 DiaryService
    participant DB as 🗄️ SQLite

    U->>F: Mở app / Về trang chủ
    F->>P: Đọc dailyDiaryProvider
    P->>A: GET /api/diary/daily?date=2026-06-27
    Note right of A: JWT → lấy userId từ token
    A->>SVC: GetDailyDiaryAsync(userId, date)
    SVC->>DB: Query DailyLogs + MealItems + Foods
    DB-->>SVC: Dữ liệu ngày hôm nay
    SVC->>SVC: Tính TargetCalories từ BMR
    SVC-->>A: DailyDiaryDto
    A-->>P: JSON Response
    P-->>F: Cập nhật UI

    Note over F: Hiển thị:<br/>- Tổng Calo đã ăn<br/>- Mục tiêu Calo<br/>- Danh sách bữa Sáng/Trưa/Tối/Ăn vặt
```

### 🔍 Luồng 3: Tra Cứu Dinh Dưỡng (Food Search)

```mermaid
sequenceDiagram
    participant U as 👤 Người dùng
    participant F as 📱 FoodSearchScreen
    participant SVC as 🔌 FoodSearchService
    participant A as ⚙️ FoodController
    participant DB as 🗄️ SQLite (USDA)

    U->>F: Mở trang Nutrition Lookup
    F->>SVC: loadFoods → searchFoods("")
    SVC->>A: GET /api/food/search
    A->>DB: SELECT TOP 24 FROM Foods
    DB-->>A: 8 món phổ biến (deduplicated)
    A-->>SVC: JSON danh sách
    SVC-->>F: Hiển thị "Popular foods"

    U->>F: Gõ "banana"
    Note over F: Debounce 400ms
    F->>SVC: searchFoods("banana")
    SVC->>A: GET /api/food/search?query=banana
    A->>DB: SELECT WHERE Name LIKE '%banana%'
    DB-->>A: Kết quả tìm kiếm
    A-->>SVC: JSON danh sách
    SVC-->>F: Hiển thị "Suggestions"

    U->>F: Bấm chọn "Banana, raw"
    F->>F: Hiện bảng dinh dưỡng chi tiết
    Note over F: Protein, Carbs, Fat,<br/>Sugar, Fiber, Sodium
```

### ➕ Luồng 4: Thêm Vào Nhật Ký (Add to Diary)

```mermaid
sequenceDiagram
    participant U as 👤 Người dùng
    participant F as 📱 FoodSearchScreen
    participant BS as 📋 BottomSheet
    participant API as 🔌 DiaryApiService
    participant A as ⚙️ DiaryController
    participant SVC as 🧠 DiaryService
    participant DB as 🗄️ SQLite

    U->>F: Bấm "Add to Diary"
    F->>BS: Mở BottomSheet
    BS->>U: Hiện form (Quantity, MealType)
    U->>BS: Nhập 150g, chọn "Lunch"
    U->>BS: Bấm "Save to Diary"

    BS->>API: logMeal(foodName, calories, 150, "Lunch", today)
    API->>A: POST /api/diary
    A->>SVC: LogMealAsync(userId, request)

    SVC->>DB: Tìm Food theo tên
    alt Food đã có trong DB
        DB-->>SVC: Food record
    else Food chưa có
        SVC->>DB: INSERT Food mới
        DB-->>SVC: Food ID mới
    end

    SVC->>DB: Tìm DailyLog hôm nay
    alt DailyLog đã có
        DB-->>SVC: DailyLog record
    else DailyLog chưa có
        SVC->>DB: INSERT DailyLog mới
    end

    SVC->>SVC: Tính calories = CaloriesPer100g × 150 / 100
    SVC->>DB: INSERT MealItem
    SVC->>DB: UPDATE DailyLog.TotalCaloriesConsumed
    DB-->>SVC: OK

    SVC-->>A: Success
    A-->>API: 200 OK
    API-->>F: Thành công

    F->>F: ref.invalidate(dailyDiaryProvider)
    Note over F: → Trang chủ tự động<br/>tải lại dữ liệu mới!
    F->>U: SnackBar "Banana added to Lunch!"
```

### 📷 Luồng 5: Quét Món Ăn Bằng AI (Scanner)

```mermaid
sequenceDiagram
    participant U as 👤 Người dùng
    participant F as 📱 ScannerScreen
    participant SVC as 🤖 GeminiVisionService
    participant PROXY as 🚀 Express Proxy
    participant AI as ☁️ Google Gemini API
    participant F2 as 📱 Kết quả

    U->>F: Bấm "Quét Món Ăn"
    U->>F: Chụp ảnh / Chọn ảnh từ thư viện

    F->>SVC: analyzeImage(imagePath)
    SVC->>SVC: Nén ảnh → 800px, JPEG 70%
    SVC->>SVC: Encode Base64

    loop Retry tối đa 3 lần
        SVC->>PROXY: POST http://localhost:3000/api/analyze-food<br/>(Base64 Image)
        PROXY->>PROXY: Đọc GEMINI_API_KEY từ file .env
        PROXY->>AI: POST Gemini API<br/>(System Prompt + Base64 Image + API Key)
        Note right of AI: AI phân tích ảnh:<br/>- Nhận diện món ăn<br/>- Ước lượng Calo<br/>- Tính Protein/Carbs/Fat
        AI-->>PROXY: JSON Response
        PROXY-->>SVC: Trả lại JSON nguyên bản
    end

    SVC->>SVC: Parse JSON → FoodAnalysisResult
    SVC-->>F2: Hiển thị kết quả

    Note over F2: Hiện danh sách món:<br/>- Tên (VN + EN)<br/>- Khẩu phần<br/>- Calories, Protein, Carbs, Fat<br/>- Độ tin cậy (confidence)
```

### 👤 Luồng 6: Quản Lý Hồ Sơ & Avatar Toàn Cục (Profile)

```mermaid
sequenceDiagram
    participant U as 👤 Người dùng
    participant F as 📱 UI (Home / Profile)
    participant P as 📦 ProfileProvider
    participant A as ⚙️ ProfileController
    participant SVC as 🧠 ProfileService
    participant DB as 🗄️ SQLite

    U->>F: Mở app (Trang chủ hoặc Profile)
    F->>P: watch(profileProvider)
    P->>A: GET /api/profile/me
    A->>SVC: GetProfileAsync(userId)
    SVC->>DB: SELECT User WHERE Id = userId
    DB-->>SVC: User record
    SVC-->>A: ProfileResponse
    A-->>P: JSON (name, avatar, height, weight, etc.)
    P-->>F: Cập nhật UI toàn cục (Avatar trên thanh điều hướng)

    U->>F: Đổi Avatar (Chọn 1 trong 10 ảnh mặc định)
    F->>A: GET /api/profile/default-avatars
    A-->>F: Trả về danh sách URL ảnh mẫu
    
    U->>F: Nhập Weight=65, Height=170 + Chọn Avatar
    F->>A: PATCH /api/profile/me (JSON body)
    A->>SVC: UpdateProfileAsync(userId, request)
    SVC->>DB: UPDATE User SET Weight=65, AvatarUrl=...
    DB-->>SVC: OK
    SVC-->>A: Updated ProfileResponse
    A-->>F: JSON cập nhật
    F->>P: refresh(profileProvider) -> tải lại dữ liệu mới
    F->>U: Hiện thông báo thành công

    Note over F: TargetCalories được tính tự động<br/>từ BMR (Mifflin-St Jeor)
```

---

## 4. Tổng Hợp API Endpoints

| # | Method | Endpoint | Đăng nhập? | Mô tả | Trạng thái |
|---|--------|----------|-----------|-------|-----------|
| 1 | POST | `/api/auth/register` | 🔓 Công khai | Đăng ký tài khoản mới | ✅ Hoạt động |
| 2 | POST | `/api/auth/login` | 🔓 Công khai | Đăng nhập, nhận JWT token | ✅ Hoạt động |
| 3 | GET | `/api/diary/daily?date=` | 🔒 Cần đăng nhập | Lấy nhật ký ăn uống theo ngày | ✅ Hoạt động |
| 4 | POST | `/api/diary` | 🔒 Cần đăng nhập | Thêm món ăn vào nhật ký | ✅ Hoạt động |
| 5 | GET | `/api/diary/stats?start=&end=` | 🔒 Cần đăng nhập | Thống kê Calo theo khoảng thời gian | ✅ Hoạt động |
| 6 | GET | `/api/food/search?query=` | 🔓 Công khai* | Tìm kiếm thực phẩm trong USDA | ✅ Hoạt động |
| 7 | GET | `/api/profile/me` | 🔒 Cần đăng nhập | Lấy thông tin hồ sơ | ✅ Hoạt động |
| 8 | PATCH | `/api/profile/me` | 🔒 Cần đăng nhập | Cập nhật hồ sơ | ✅ Hoạt động |
| 9 | GET | `/api/profile/default-avatars` | 🔓 Công khai | Danh sách avatar mặc định | ✅ Hoạt động |

> **Chú thích cột "Đăng nhập?":**
> - 🔓 **Công khai** = Không cần đăng nhập, ai cũng gọi được API này
> - 🔒 **Cần đăng nhập** = Phải gửi kèm JWT Token (phải đăng nhập trước)
>
> *\* FoodController hiện tạm tắt `[Authorize]` để dễ test, khi đưa lên production nên bật lại*

---

## 5. Luồng Dữ Liệu Tổng Hợp (Full Picture)

```mermaid
flowchart LR
    subgraph Frontend
        A["📱 Flutter Web App"]
    end

    subgraph Auth
        B["🔐 JWT Token & Diary<br/>(SharedPreferences & Isar)"]
    end

    subgraph Proxy
        P["🚀 Express.js Proxy<br/>(localhost:3000)"]
    end

    subgraph Backend
        C["⚙️ .NET 8 API<br/>(localhost:5210)"]
    end

    subgraph Database
        D["🗄️ SQLite<br/>(calories.db)"]
    end

    subgraph ExternalAI
        E["🤖 Gemini Vision<br/>(Google Cloud)"]
    end

    subgraph Data
        F["📊 USDA Dataset<br/>(usda_calorie_dataset.csv)"]
    end

    A -->|"HTTP + JWT"| C
    A -->|"Lưu/đọc token & offline data"| B
    A -->|"Gửi ảnh Base64"| P
    P -->|"Gắn API Key bảo mật"| E
    C -->|"EF Core"| D
    F -->|"Seeder khởi tạo"| D
    E -->|"JSON kết quả"| P
    P -->|"JSON kết quả"| A

    style A fill:#42A5F5,color:#fff
    style C fill:#66BB6A,color:#fff
    style P fill:#AB47BC,color:#fff
    style D fill:#FFA726,color:#fff
    style E fill:#EF5350,color:#fff
```

> [!IMPORTANT]
> **Điểm đặc biệt được nâng cấp (Bảo mật)**: Tính năng Scanner (Quét ảnh AI) hiện tại gọi qua **Node.js Express Proxy (localhost:3000)** thay vì gọi trực tiếp đến Google Gemini API. Proxy server sẽ tự động đính kèm `GEMINI_API_KEY` lấy từ biến môi trường `.env`. Điều này giúp bảo mật hoàn toàn API Key, tránh bị lộ ở client (Flutter Web/App), đồng thời vẫn giữ được hiệu năng cao và độc lập với Backend .NET chính.
