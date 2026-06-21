# 🍏 Calories Tracking App (AI-Powered)

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Gemini AI](https://img.shields.io/badge/Gemini_AI-%238E75B2.svg?style=for-the-badge&logo=google&logoColor=white)

A smart Calorie Tracking app that uses **Google Gemini Vision AI** to automatically detect and analyze the nutritional content of your food from a photo.

The project is built on **Flutter**, supports multiple platforms (Web, Android, iOS), and follows a professional **Spec-Driven Development (SDD)** methodology.

---

## ✨ Key Features

- 📸 **Scan Food via Camera/Gallery:** Take a photo of your meal or upload one from your phone for the AI to automatically analyze.
- 🤖 **Google Gemini AI Integration:** Highly accurate analysis of Calories, Protein, Carbs, and Fat for each food item in the image.
- 📊 **Dashboard & Diary:** Track total calories consumed for the day (Home) and review your meal history (Diary).
- 🌐 **Cross-Platform Support:** Runs smoothly on Web (accessible via HTTPS link) and Android devices (`.apk` file).
- 🚀 **Automated CI/CD:** GitHub Actions is configured to automatically build and deploy to GitHub Pages whenever new code is pushed.

---

## 🛠 Tech Stack

The project uses the most modern libraries and techniques in the Flutter ecosystem:
- **Framework:** Flutter (`^3.12.0`), Dart
- **State Management:** `flutter_riverpod`
- **Routing:** `go_router`
- **AI & Networking:** `http` (communicates with the Gemini REST API), `connectivity_plus`
- **Image Processing:** `camera`, `image_picker`, `image`, `cross_file` (supports safe file reading on Web)
- **UI:** `google_fonts`, `lottie` (smooth animations), `cupertino_icons`
- **Local Storage:** `shared_preferences`

---

## 🏗 Project Architecture

The project follows the **Feature-First Architecture** principle, making the codebase easy to extend and maintain:

```text
lib/
├── app/               # Core configuration (Theme, Router config)
├── features/          # Contains the app's main features
│   ├── diary/         # Meal history feature
│   ├── home/          # Home dashboard feature
│   └── scanner/       # Core: Camera handling & Gemini AI integration
│       ├── models/    # Data classes (FoodAnalysisResult...)
│       ├── screens/   # Screens (CameraScannerScreen, ResultsScreen...)
│       ├── services/  # API call logic (GeminiVisionService)
│       └── widgets/   # Shared UI components for this feature
└── shared/            # App-wide shared utilities (utils, constants...)
```

---

## 🌟 Development Methodology: Spec-Driven Development (SDD)

This project is a real-world demonstration of applying the **Spec-Driven Development** methodology. Communication between the Front-end and the AI Model isn't based on guesswork, but on a fixed "Contract" (Specification).

- 📖 **[Read the team's SDD theory and application documentation here](docs/SPEC_DRIVEN_DEVELOPMENT.md)**
- ⚙️ **[View the JSON Specification (API Spec) here](docs/API_SPEC.md)**

*Thanks to applying SDD, the project guarantees 100% consistency in the output data from Gemini AI, completely avoiding JSON parsing errors or app crashes.*

---

## 🚀 Getting Started

### System Requirements
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed (version 3.12.0 or later).
- A Google AI Studio account to obtain an API Key.

### Step 1: Clone the project
```bash
git clone https://github.com/trangkhanh-ai/Calories-Tracking-App.git
cd Calories-Tracking-App
flutter pub get
```

### Step 2: Configure the API Key (REQUIRED)
For security reasons, the Gemini API Key is not pushed to GitHub. You need to set it up manually on your machine:
1. Navigate to the `lib/shared/utils/` folder.
2. Create a new file named `constants.dart` (or copy it from `constants.example.dart` if available).
3. Add the following code to the newly created file and fill in your API Key:
```dart
class AppConstants {
  static const String geminiApiKey = 'ENTER_YOUR_API_KEY_HERE';
}
```

### Step 3: Run the app
- **Run in a Web Browser (recommended for testing):**
  ```bash
  flutter run -d chrome
  ```
- **Run on an Emulator / a real Android device:**
  ```bash
  flutter run
  ```

---

## 📱 iOS Deployment (Apple Devices)

The project has been fully configured with `Info.plist` (Camera, Photo Library, Microphone permissions) and an iOS Deployment Target of >=13.0.
However, to build the app for iOS, you must use a macOS computer (MacBook/Mac Mini) with Xcode installed. Windows machines cannot compile iOS source code.

## 🔗 Live Demo Link
If GitHub Pages has been set up successfully, you can try the app live on any mobile browser via the link:
👉 `https://trangkhanh-ai.github.io/Calories-Tracking-App/`
