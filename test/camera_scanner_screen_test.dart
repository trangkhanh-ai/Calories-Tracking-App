import 'dart:async';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/scanner/screens/camera_scanner_screen.dart';
import 'package:flutter_application_1/features/scanner/models/food_analysis_result.dart';
import 'package:flutter_application_1/features/scanner/providers/scanner_provider.dart';
import 'package:flutter_application_1/features/scanner/services/scanner_camera_service.dart';
import 'package:flutter_application_1/features/scanner/services/scanner_image_source.dart';
import 'package:flutter_application_1/features/scanner/services/gemini_vision_service.dart';
import 'package:flutter_application_1/features/scanner/widgets/capture_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CameraDescription _camera(String name, CameraLensDirection direction) {
  return CameraDescription(
    name: name,
    lensDirection: direction,
    sensorOrientation: 0,
  );
}

class _FakePlatform implements ScannerCameraPlatform {
  _FakePlatform({
    required this.cameras,
    this.permission = ScannerCameraPermission.granted,
    this.web = false,
  });

  List<CameraDescription> cameras;
  ScannerCameraPermission permission;
  bool web;
  final List<_FakeController> controllers = <_FakeController>[];
  Completer<void>? initializationGate;

  @override
  bool get isWeb => web;

  @override
  Future<ScannerCameraPermission> requestPermission() async => permission;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<ScannerCameraController> createController(
    CameraDescription description,
  ) async {
    final controller = _FakeController(description)
      ..initializeGate = initializationGate;
    controllers.add(controller);
    return controller;
  }

  @override
  Future<bool> openAppSettings() async => true;
}

class _FakeController implements ScannerCameraController {
  _FakeController(this.description);

  @override
  final CameraDescription description;
  Completer<void>? initializeGate;
  Completer<XFile>? captureGate;
  @override
  bool initialized = false;
  bool disposed = false;

  @override
  double get aspectRatio => 4 / 3;

  @override
  Widget buildPreview() =>
      const ColoredBox(key: ValueKey('fake-preview'), color: Colors.black);

  @override
  Future<void> initialize() async {
    if (initializeGate != null) await initializeGate!.future;
    initialized = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<XFile> takePicture() async {
    final gate = captureGate;
    return gate == null ? XFile('capture.jpg') : gate.future;
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {}
}

class _FakeImageSource implements ScannerImageSource {
  int rearCaptureCalls = 0;
  int galleryCalls = 0;

  @override
  Future<XFile?> captureRearCamera() async {
    rearCaptureCalls++;
    return null;
  }

  @override
  Future<XFile?> pickGallery() async {
    galleryCalls++;
    return null;
  }
}

class _BlockingGeminiService extends GeminiVisionService {
  final Completer<FoodAnalysisResult> result = Completer<FoodAnalysisResult>();

  @override
  Future<FoodAnalysisResult> analyzeImage(
    String imagePath, {
    int maxAttempts = GeminiVisionService.defaultMaxAttempts,
    CancelToken? cancelToken,
  }) {
    return result.future;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakePlatform platform,
  required _FakeImageSource imageSource,
  List<Override> overrides = const <Override>[],
}) async {
  final session = ScannerCameraSession(platform: platform);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: CameraScannerScreen(
          cameraSession: session,
          imageSource: imageSource,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpCameraFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('shows a loading shell while camera initializes', (tester) async {
    final gate = Completer<void>();
    final platform = _FakePlatform(
      cameras: [_camera('back', CameraLensDirection.back)],
    )..initializationGate = gate;
    final imageSource = _FakeImageSource();

    await _pumpScreen(tester, platform: platform, imageSource: imageSource);

    expect(find.byKey(const ValueKey('camera-loading')), findsOneWidget);

    gate.complete();
    await _pumpCameraFrames(tester);
  });

  testWidgets('shows the ready preview shell after initialization', (
    tester,
  ) async {
    final platform = _FakePlatform(
      cameras: [_camera('back', CameraLensDirection.back)],
    );
    final imageSource = _FakeImageSource();

    await _pumpScreen(tester, platform: platform, imageSource: imageSource);
    await _pumpCameraFrames(tester);

    expect(find.byKey(const ValueKey('camera-preview-shell')), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);
  });

  testWidgets('permission denied state offers retry and gallery recovery', (
    tester,
  ) async {
    final platform = _FakePlatform(
      cameras: [_camera('back', CameraLensDirection.back)],
      permission: ScannerCameraPermission.denied,
    );
    final imageSource = _FakeImageSource();

    await _pumpScreen(tester, platform: platform, imageSource: imageSource);
    await _pumpCameraFrames(tester);

    expect(
      find.byKey(const ValueKey('camera-permission-denied')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('camera-retry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('camera-gallery-fallback')),
      findsOneWidget,
    );
  });

  testWidgets('unavailable web state offers rear capture and gallery', (
    tester,
  ) async {
    final platform = _FakePlatform(cameras: const [], web: true);
    final imageSource = _FakeImageSource();

    await _pumpScreen(tester, platform: platform, imageSource: imageSource);
    await _pumpCameraFrames(tester);

    expect(find.byKey(const ValueKey('camera-fallback')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-rear-fallback')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('camera-gallery-fallback')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('camera-rear-fallback')));
    await tester.tap(find.byKey(const ValueKey('camera-gallery-fallback')));
    expect(imageSource.rearCaptureCalls, 1);
    expect(imageSource.galleryCalls, 1);
  });

  testWidgets('successful retry replaces the unavailable fallback', (
    tester,
  ) async {
    final platform = _FakePlatform(cameras: const []);
    final imageSource = _FakeImageSource();

    await _pumpScreen(tester, platform: platform, imageSource: imageSource);
    await _pumpCameraFrames(tester);
    expect(find.byKey(const ValueKey('camera-fallback')), findsOneWidget);

    platform.cameras = [_camera('back', CameraLensDirection.back)];
    await tester.tap(find.byKey(const ValueKey('camera-retry')));
    await _pumpCameraFrames(tester);

    expect(find.byKey(const ValueKey('camera-preview-shell')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-fallback')), findsNothing);
  });

  testWidgets('permanently denied native permission offers settings action', (
    tester,
  ) async {
    final platform = _FakePlatform(
      cameras: [_camera('back', CameraLensDirection.back)],
      permission: ScannerCameraPermission.permanentlyDenied,
    );
    final imageSource = _FakeImageSource();

    await _pumpScreen(tester, platform: platform, imageSource: imageSource);
    await _pumpCameraFrames(tester);

    expect(
      find.byKey(const ValueKey('camera-permission-permanent')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('camera-open-settings')), findsOneWidget);
  });

  testWidgets(
    'does not resume the camera after analysis completes in the background',
    (tester) async {
      final platform = _FakePlatform(
        cameras: [_camera('back', CameraLensDirection.back)],
      );
      final imageSource = _FakeImageSource();
      final gemini = _BlockingGeminiService();

      await _pumpScreen(
        tester,
        platform: platform,
        imageSource: imageSource,
        overrides: [geminiServiceProvider.overrideWithValue(gemini)],
      );
      await _pumpCameraFrames(tester);
      await tester.tap(find.byType(CaptureButton));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gemini.result.complete(
        const FoodAnalysisResult(
          foodDetected: false,
          items: <NutritionInfo>[],
          imageQuality: 'good',
          notes: '',
          imagePath: 'capture.jpg',
        ),
      );
      await _pumpCameraFrames(tester);
      await tester.tap(find.text('Thử lại'));
      await _pumpCameraFrames(tester);

      expect(platform.controllers, hasLength(1));
      expect(platform.controllers.single.disposed, isTrue);
    },
  );

  testWidgets('defers lifecycle resume until in-flight analysis completes', (
    tester,
  ) async {
    final platform = _FakePlatform(
      cameras: [_camera('back', CameraLensDirection.back)],
    );
    final imageSource = _FakeImageSource();
    final gemini = _BlockingGeminiService();

    await _pumpScreen(
      tester,
      platform: platform,
      imageSource: imageSource,
      overrides: [geminiServiceProvider.overrideWithValue(gemini)],
    );
    await _pumpCameraFrames(tester);
    await tester.tap(find.byType(CaptureButton));
    await _pumpCameraFrames(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _pumpCameraFrames(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpCameraFrames(tester);

    expect(platform.controllers, hasLength(1));

    gemini.result.complete(
      const FoodAnalysisResult(
        foodDetected: false,
        items: <NutritionInfo>[],
        imageQuality: 'good',
        notes: '',
        imagePath: 'capture.jpg',
      ),
    );
    await _pumpCameraFrames(tester);
    await tester.tap(find.text('Thử lại'));
    await _pumpCameraFrames(tester);

    expect(platform.controllers, hasLength(2));
    expect(platform.controllers.last.disposed, isFalse);
  });

  testWidgets('disables gallery and lens switching while capture is busy', (
    tester,
  ) async {
    final platform = _FakePlatform(
      cameras: [
        _camera('back', CameraLensDirection.back),
        _camera('front', CameraLensDirection.front),
      ],
    );
    final imageSource = _FakeImageSource();
    final gemini = _BlockingGeminiService();
    gemini.result.complete(
      const FoodAnalysisResult(
        foodDetected: false,
        items: <NutritionInfo>[],
        imageQuality: 'good',
        notes: '',
        imagePath: 'capture.jpg',
      ),
    );

    await _pumpScreen(
      tester,
      platform: platform,
      imageSource: imageSource,
      overrides: [geminiServiceProvider.overrideWithValue(gemini)],
    );
    await _pumpCameraFrames(tester);
    final captureGate = Completer<XFile>();
    platform.controllers.single.captureGate = captureGate;

    await tester.tap(find.byType(CaptureButton));
    await tester.pump();

    final galleryGesture = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.text('Thư viện'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    final switchGesture = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.text('Đổi camera'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );

    expect(galleryGesture.onTap, isNull);
    expect(switchGesture.onTap, isNull);

    captureGate.complete(XFile('capture.jpg'));
    await _pumpCameraFrames(tester);
    await tester.tap(find.text('Thử lại'));
    await _pumpCameraFrames(tester);
  });
}
