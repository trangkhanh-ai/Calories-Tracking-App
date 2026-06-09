import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/food_analysis_result.dart';
import '../services/gemini_vision_service.dart';

final geminiServiceProvider = Provider<GeminiVisionService>((ref) {
  return GeminiVisionService();
});

enum ScanStatus { idle, capturing, analyzing, success, error }

class ScanState {
  final ScanStatus status;
  final FoodAnalysisResult? result;
  final String? errorMessage;
  final String? capturedImagePath;

  const ScanState({
    this.status = ScanStatus.idle,
    this.result,
    this.errorMessage,
    this.capturedImagePath,
  });

  ScanState copyWith({
    ScanStatus? status,
    FoodAnalysisResult? result,
    String? errorMessage,
    String? capturedImagePath,
  }) {
    return ScanState(
      status: status ?? this.status,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      capturedImagePath: capturedImagePath ?? this.capturedImagePath,
    );
  }
}

class ScanNotifier extends StateNotifier<ScanState> {
  final GeminiVisionService _service;

  ScanNotifier(this._service) : super(const ScanState());

  Future<FoodAnalysisResult?> analyzeImage(String imagePath) async {
    state = state.copyWith(
      status: ScanStatus.analyzing,
      capturedImagePath: imagePath,
      errorMessage: null,
    );

    try {
      final result = await _service.analyzeImage(imagePath);
      state = state.copyWith(
        status: ScanStatus.success,
        result: result,
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        status: ScanStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      return null;
    }
  }

  void reset() {
    state = const ScanState();
  }
}

final scanProvider = StateNotifierProvider<ScanNotifier, ScanState>((ref) {
  return ScanNotifier(ref.read(geminiServiceProvider));
});
