import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/scanner/services/scanner_camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

CameraDescription camera(String name, CameraLensDirection direction) {
  return CameraDescription(
    name: name,
    lensDirection: direction,
    sensorOrientation: 0,
  );
}

class FakePlatform implements ScannerCameraPlatform {
  FakePlatform({
    List<CameraDescription>? cameras,
    this.permission = ScannerCameraPermission.granted,
    this.web = false,
  }) : cameras = cameras ?? <CameraDescription>[];

  List<CameraDescription> cameras;
  ScannerCameraPermission permission;
  bool web;
  Object? permissionError;
  Object? camerasError;
  int openSettingsCalls = 0;
  final Map<String, Object> initFailures = <String, Object>{};
  final Map<String, Completer<void>> initGates = <String, Completer<void>>{};
  final List<FakeController> created = <FakeController>[];
  Future<ScannerCameraController> Function(CameraDescription)?
  controllerFactory;
  int createCount = 0;

  @override
  bool get isWeb => web;

  @override
  Future<ScannerCameraPermission> requestPermission() async {
    if (permissionError != null) throw permissionError!;
    return permission;
  }

  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (camerasError != null) throw camerasError!;
    return cameras;
  }

  @override
  Future<ScannerCameraController> createController(
    CameraDescription description,
  ) async {
    createCount++;
    final factory = controllerFactory;
    if (factory != null) return factory(description);
    final controller = FakeController(description);
    controller.initializeError = initFailures[description.name];
    controller.initializeGate = initGates[description.name];
    created.add(controller);
    return controller;
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls++;
    return true;
  }
}

class FakeController implements ScannerCameraController {
  FakeController(this.description);

  @override
  final CameraDescription description;
  @override
  bool initialized = false;
  bool disposed = false;
  bool initializeSetsInitialized = true;
  int initializeCalls = 0;
  int disposeCalls = 0;
  int captureCalls = 0;
  int flashCalls = 0;
  FlashMode? lastFlashMode;
  Completer<XFile>? captureGate;
  Completer<void>? flashGate;

  Object? initializeError;
  Completer<void>? initializeGate;

  @override
  double get aspectRatio => 4 / 3;

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (initializeGate != null) await initializeGate!.future;
    if (initializeError != null) throw initializeError!;
    initialized = initializeSetsInitialized;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
  }

  @override
  Future<XFile> takePicture() async {
    captureCalls++;
    if (captureGate != null) return captureGate!.future;
    return XFile('capture-$captureCalls.jpg');
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    flashCalls++;
    lastFlashMode = mode;
    if (flashGate != null) await flashGate!.future;
  }
}

void main() {
  group('camera selection', () {
    test('front then back selects back', () async {
      final platform = FakePlatform(
        cameras: [
          camera('front', CameraLensDirection.front),
          camera('back', CameraLensDirection.back),
        ],
      );
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(session.state.selectedCamera?.name, 'back');
      expect(session.state.status, ScannerCameraStatus.ready);
    });

    test('back then front selects back', () async {
      final platform = FakePlatform(
        cameras: [
          camera('back', CameraLensDirection.back),
          camera('front', CameraLensDirection.front),
        ],
      );
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(session.state.selectedCamera?.name, 'back');
    });

    test('front only selects front', () async {
      final platform = FakePlatform(
        cameras: [camera('front', CameraLensDirection.front)],
      );
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(session.state.selectedCamera?.name, 'front');
    });

    test('back only selects back', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(session.state.selectedCamera?.name, 'back');
    });

    test('external only selects external', () async {
      final platform = FakePlatform(
        cameras: [camera('external', CameraLensDirection.external)],
      );
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(session.state.selectedCamera?.name, 'external');
    });

    test('empty camera list becomes unavailable', () async {
      final session = ScannerCameraSession(platform: FakePlatform());

      await session.start();

      expect(session.state.status, ScannerCameraStatus.unavailable);
      expect(session.state.failure?.kind, ScannerCameraFailureKind.noCamera);
    });

    test('multiple rear cameras choose deterministic name', () async {
      final platform = FakePlatform(
        cameras: [
          camera('rear-z', CameraLensDirection.back),
          camera('rear-a', CameraLensDirection.back),
        ],
      );
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(session.state.selectedCamera?.name, 'rear-a');
    });
  });

  group('switching', () {
    test('switches rear to front and front to rear', () async {
      final platform = FakePlatform(
        cameras: [
          camera('back', CameraLensDirection.back),
          camera('front', CameraLensDirection.front),
        ],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();

      await session.switchLensDirection();
      expect(
        session.state.selectedCamera?.lensDirection,
        CameraLensDirection.front,
      );
      await session.switchLensDirection();
      expect(
        session.state.selectedCamera?.lensDirection,
        CameraLensDirection.back,
      );
      expect(platform.createCount, 3);
    });

    test('does nothing when no opposite direction exists', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();

      expect(session.canSwitchLens, isFalse);
      await session.switchLensDirection();

      expect(session.state.selectedCamera?.name, 'back');
      expect(platform.createCount, 1);
    });

    test('rapid switches are serialized with one active controller', () async {
      final platform = FakePlatform(
        cameras: [
          camera('back', CameraLensDirection.back),
          camera('front', CameraLensDirection.front),
        ],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();

      final first = session.switchLensDirection();
      final second = session.switchLensDirection();
      await Future.wait([first, second]);

      expect(
        session.state.selectedCamera?.lensDirection,
        CameraLensDirection.back,
      );
      expect(platform.created.where((c) => !c.disposed).length, 1);
    });

    test('failed lens switch recovers to the previous camera', () async {
      final platform = FakePlatform(
        cameras: [
          camera('back', CameraLensDirection.back),
          camera('front', CameraLensDirection.front),
        ],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();
      platform.initFailures['front'] = CameraException(
        'cameraNotReadable',
        'private plugin detail',
      );

      await session.switchLensDirection();

      expect(session.state.status, ScannerCameraStatus.ready);
      expect(session.state.selectedCamera?.name, 'back');
      expect(platform.created[1].description.name, 'front');
      expect(platform.created[1].disposed, isTrue);
      expect(platform.createCount, 3);
    });
  });

  group('recovery and generations', () {
    test('a successful start clears an old unavailable failure', () async {
      final platform = FakePlatform();
      final session = ScannerCameraSession(platform: platform);
      await session.start();
      expect(session.state.status, ScannerCameraStatus.unavailable);

      platform.cameras = [camera('back', CameraLensDirection.back)];
      await session.retry();

      expect(session.state.status, ScannerCameraStatus.ready);
      expect(session.state.failure, isNull);
    });

    test('failed preferred rear recovers to another camera', () async {
      final platform = FakePlatform(
        cameras: [
          camera('back', CameraLensDirection.back),
          camera('front', CameraLensDirection.front),
        ],
      );
      platform.initFailures['back'] = CameraException('CameraAccess', 'denied');
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(session.state.status, ScannerCameraStatus.ready);
      expect(session.state.selectedCamera?.name, 'front');
      expect(platform.created.first.disposed, isTrue);
    });

    test('retry reaches ready after an initialization failure', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final session = ScannerCameraSession(platform: platform);
      final firstController = platform.created;

      platform.controllerFactory = (description) async {
        final controller = FakeController(description);
        if (firstController.isEmpty) {
          controller.initializeError = CameraException('CameraInUse', 'busy');
        }
        firstController.add(controller);
        return controller;
      };

      await session.start();
      expect(session.state.status, ScannerCameraStatus.error);
      await session.retry();
      expect(session.state.status, ScannerCameraStatus.ready);
    });

    test('stale initialization cannot overwrite the latest start', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final gate = Completer<void>();
      platform.controllerFactory = (description) async {
        final controller = FakeController(description)..initializeGate = gate;
        platform.created.add(controller);
        return controller;
      };
      final session = ScannerCameraSession(platform: platform);

      final first = session.start();
      await Future<void>.delayed(Duration.zero);
      platform.cameras = [camera('front', CameraLensDirection.front)];
      final latest = session.start();
      gate.complete();
      await Future.wait([first, latest]);

      expect(session.state.selectedCamera?.name, 'front');
      expect(platform.created.first.disposed, isTrue);
    });

    test('failed and stale controllers are disposed', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final controller = FakeController(platform.cameras.first)
        ..initializeError = CameraException('CameraInUse', 'busy');
      platform.controllerFactory = (_) async {
        platform.created.add(controller);
        return controller;
      };
      final session = ScannerCameraSession(platform: platform);

      await session.start();

      expect(controller.disposed, isTrue);
    });

    test(
      'controller must report initialized before it can become active',
      () async {
        final platform = FakePlatform(
          cameras: [camera('back', CameraLensDirection.back)],
        );
        final controller = FakeController(platform.cameras.single)
          ..initializeSetsInitialized = false;
        platform.controllerFactory = (_) async {
          platform.created.add(controller);
          return controller;
        };
        final session = ScannerCameraSession(platform: platform);

        await session.start();

        expect(session.state.status, ScannerCameraStatus.error);
        expect(controller.disposed, isTrue);
      },
    );

    test(
      'permanent denial code is classified and sanitized without details',
      () async {
        final platform = FakePlatform()
          ..camerasError = CameraException(
            'Camera Access Permanently Denied!',
            'secret plugin description',
          );
        final session = ScannerCameraSession(platform: platform);

        await session.start();

        expect(
          session.state.failure?.kind,
          ScannerCameraFailureKind.permissionDeniedPermanently,
        );
        expect(
          session.state.failure?.code,
          'Camera_Access_Permanently_Denied_',
        );
        expect(session.state.failure?.code, isNot(contains('secret')));
      },
    );

    test('openAppSettings delegates to the injected platform', () async {
      final platform = FakePlatform();
      final session = ScannerCameraSession(platform: platform);

      expect(await session.openAppSettings(), isTrue);
      expect(platform.openSettingsCalls, 1);
    });

    test(
      'permission request exceptions become a sanitized failure state',
      () async {
        final platform = FakePlatform()
          ..permissionError = CameraException(
            'CameraAccessDeniedWithoutPrompt',
            'private permission details',
          );
        final session = ScannerCameraSession(platform: platform);

        await session.start();

        expect(
          session.state.status,
          ScannerCameraStatus.permissionDeniedPermanently,
        );
        expect(
          session.state.failure?.kind,
          ScannerCameraFailureKind.permissionDeniedPermanently,
        );
        expect(session.state.failure?.code, 'CameraAccessDeniedWithoutPrompt');
        expect(session.state.failure?.code, isNot(contains('private')));
      },
    );

    test(
      'CameraException codes map to safe failure kinds and statuses',
      () async {
        final cases =
            <
              ({
                String code,
                ScannerCameraFailureKind kind,
                ScannerCameraStatus status,
              })
            >[
              (
                code: 'CameraAccessDenied',
                kind: ScannerCameraFailureKind.permissionDenied,
                status: ScannerCameraStatus.permissionDenied,
              ),
              (
                code: 'CameraAccessDeniedWithoutPrompt',
                kind: ScannerCameraFailureKind.permissionDeniedPermanently,
                status: ScannerCameraStatus.permissionDeniedPermanently,
              ),
              (
                code: 'CameraAccessRestricted',
                kind: ScannerCameraFailureKind.permissionDeniedPermanently,
                status: ScannerCameraStatus.permissionDeniedPermanently,
              ),
              (
                code: 'cameraNotFound',
                kind: ScannerCameraFailureKind.noCamera,
                status: ScannerCameraStatus.unavailable,
              ),
              (
                code: 'cameraNotReadable',
                kind: ScannerCameraFailureKind.notReadable,
                status: ScannerCameraStatus.error,
              ),
              (
                code: 'cameraAccess',
                kind: ScannerCameraFailureKind.cameraInUse,
                status: ScannerCameraStatus.error,
              ),
              (
                code: 'cameraTypeNotSupported',
                kind: ScannerCameraFailureKind.unsupported,
                status: ScannerCameraStatus.unavailable,
              ),
              (
                code: 'SecurityError',
                kind: ScannerCameraFailureKind.unsupported,
                status: ScannerCameraStatus.unavailable,
              ),
              (
                code: 'OverconstrainedError',
                kind: ScannerCameraFailureKind.unsupported,
                status: ScannerCameraStatus.unavailable,
              ),
            ];

        for (final testCase in cases) {
          final platform = FakePlatform()
            ..camerasError = CameraException(testCase.code, 'private detail');
          final session = ScannerCameraSession(platform: platform);

          await session.start();

          expect(
            session.state.failure?.kind,
            testCase.kind,
            reason: testCase.code,
          );
          expect(session.state.status, testCase.status, reason: testCase.code);
        }
      },
    );
  });

  group('lifecycle, flash, and capture', () {
    test(
      'suspend and resume are idempotent and resume reinitializes',
      () async {
        final platform = FakePlatform(
          cameras: [camera('back', CameraLensDirection.back)],
        );
        final session = ScannerCameraSession(platform: platform);
        await session.start();

        await session.suspend();
        await session.suspend();
        expect(session.state.controller, isNull);
        await session.resume();
        await session.resume();

        expect(session.state.status, ScannerCameraStatus.ready);
        expect(platform.created.where((c) => !c.disposed).length, 1);
      },
    );

    test('unsupported flash remains off', () async {
      final platform = FakePlatform(
        cameras: [camera('front', CameraLensDirection.front)],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();

      final changed = await session.setFlashEnabled(true);

      expect(changed, isFalse);
      expect(session.state.flashEnabled, isFalse);
      expect(platform.created.single.flashCalls, 0);
    });

    test('capture enters busy and prevents duplicate capture', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();
      final gate = Completer<XFile>();
      platform.created.single.captureGate = gate;

      final first = session.capture();
      final second = session.capture();
      expect(session.state.status, ScannerCameraStatus.busy);
      expect(await second, isNull);
      gate.complete(XFile('meal.jpg'));
      expect((await first)?.path, 'meal.jpg');
      expect(session.state.status, ScannerCameraStatus.ready);
      expect(platform.created.single.captureCalls, 1);
    });

    test('lifecycle disposal waits for an active capture', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();
      final controller = platform.created.single;
      final gate = Completer<XFile>();
      controller.captureGate = gate;

      final capture = session.capture();
      final suspend = session.suspend();
      await Future<void>.delayed(Duration.zero);

      expect(controller.disposed, isFalse);
      gate.complete(XFile('meal.jpg'));
      expect(await capture, isNull);
      await suspend;
      expect(controller.disposed, isTrue);
    });

    test('lifecycle disposal waits for an active flash command', () async {
      final platform = FakePlatform(
        cameras: [camera('back', CameraLensDirection.back)],
      );
      final session = ScannerCameraSession(platform: platform);
      await session.start();
      final controller = platform.created.single;
      final gate = Completer<void>();
      controller.flashGate = gate;

      final flash = session.setFlashEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.flashCalls, 1);
      final suspend = session.suspend();
      await Future<void>.delayed(Duration.zero);

      expect(controller.disposed, isFalse);
      gate.complete();
      expect(await flash, isFalse);
      await suspend;
      expect(controller.disposed, isTrue);
      expect(session.state.flashEnabled, isFalse);
    });
  });
}
