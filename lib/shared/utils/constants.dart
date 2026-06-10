class AppConstants {
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:5210',
  );

  static const String backendAuthToken = String.fromEnvironment(
    'BACKEND_AUTH_TOKEN',
    defaultValue: '',
  );
  
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AIzaSyC8ixXyzLSKTmqi3Ekbs8fU7mW4z3ylJTI', // Dùng key test của người dùng
  );

  static const List<double> servingScales = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static const List<String> servingScaleLabels = [
    '1/2',
    '3/4',
    '1x',
    '1.25x',
    '1.5x',
    '2x',
  ];

  static const List<String> mealTypes = [
    'Bữa Sáng',
    'Bữa Trưa',
    'Bữa Tối',
    'Ăn Vặt',
  ];

  static const List<String> mealTypeEmojis = [
    '🌅',
    '☀️',
    '🌙',
    '🍪',
  ];
}
