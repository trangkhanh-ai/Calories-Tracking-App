import 'dart:async';

import 'package:camera/camera.dart' as camera_plugin;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

/// Permission result kept independent from permission_handler for test fakes.
enum ScannerCameraPermission { granted, denied, permanentlyDenied }

/// Lifecycle and operational state exposed to scanner UI.
enum ScannerCameraStatus {
  loading,
  ready,
  switching,
  permissionDenied,
  permissionDeniedPermanently,
  unavailable,
  busy,
  error,
}

enum ScannerCameraFailureKind {
  permissionDenied,
  permissionDeniedPermanently,
  noCamera,
  cameraInUse,
  notReadable,
  initializationFailed,
  unsupported,
}

class ScannerCameraFailure {
  const ScannerCameraFailure({required this.kind, this.code});

  final ScannerCameraFailureKind kind;

  /// Only a sanitized CameraException code is retained; descriptions/stacks
  /// are deliberately excluded from state.
  final String? code;
}

class ScannerCameraState {
  const ScannerCameraState({
    this.status = ScannerCameraStatus.loading,
    this.availableCameras = const <CameraDescription>[],
    this.selectedCamera,
    this.controller,
    this.failure,
    this.flashEnabled = false,
    this.flashSupported = false,
    this.isCapturing = false,
    this.lastCapture,
  });

  final ScannerCameraStatus status;
  final List<CameraDescription> availableCameras;
  final CameraDescription? selectedCamera;
  final ScannerCameraController? controller;
  final ScannerCameraFailure? failure;
  final bool flashEnabled;
  final bool flashSupported;
  final bool isCapturing;
  final XFile? lastCapture;

  ScannerCameraState copyWith({
    ScannerCameraStatus? status,
    List<CameraDescription>? availableCameras,
    CameraDescription? selectedCamera,
    bool clearSelectedCamera = false,
    ScannerCameraController? controller,
    bool clearController = false,
    ScannerCameraFailure? failure,
    bool clearFailure = false,
    bool? flashEnabled,
    bool? flashSupported,
    bool? isCapturing,
    XFile? lastCapture,
    bool clearLastCapture = false,
  }) {
    return ScannerCameraState(
      status: status ?? this.status,
      availableCameras: availableCameras ?? this.availableCameras,
      selectedCamera: clearSelectedCamera
          ? null
          : (selectedCamera ?? this.selectedCamera),
      controller: clearController ? null : (controller ?? this.controller),
      failure: clearFailure ? null : (failure ?? this.failure),
      flashEnabled: flashEnabled ?? this.flashEnabled,
      flashSupported: flashSupported ?? this.flashSupported,
      isCapturing: isCapturing ?? this.isCapturing,
      lastCapture: clearLastCapture ? null : (lastCapture ?? this.lastCapture),
    );
  }
}

/// Injectable camera boundary. Production uses [PluginScannerCameraPlatform];
/// tests provide a hand-written fake with no plugin channel calls.
abstract interface class ScannerCameraPlatform {
  bool get isWeb;

  Future<ScannerCameraPermission> requestPermission();

  Future<List<CameraDescription>> availableCameras();

  Future<ScannerCameraController> createController(
    CameraDescription description,
  );

  Future<bool> openAppSettings();
}

/// Small controller boundary used by the session and scanner widgets.
abstract interface class ScannerCameraController {
  CameraDescription get description;

  bool get initialized;

  double get aspectRatio;

  Widget buildPreview();

  Future<void> initialize();

  Future<void> dispose();

  Future<XFile> takePicture();

  Future<void> setFlashMode(FlashMode mode);
}

class PluginScannerCameraPlatform implements ScannerCameraPlatform {
  const PluginScannerCameraPlatform();

  @override
  bool get isWeb => kIsWeb;

  @override
  Future<ScannerCameraPermission> requestPermission() async {
    if (kIsWeb) return ScannerCameraPermission.granted;
    final status = await permissions.Permission.camera.request();
    if (status.isPermanentlyDenied || status.isRestricted) {
      return ScannerCameraPermission.permanentlyDenied;
    }
    if (status.isGranted) return ScannerCameraPermission.granted;
    return ScannerCameraPermission.denied;
  }

  @override
  Future<List<CameraDescription>> availableCameras() {
    return camera_plugin.availableCameras();
  }

  @override
  Future<ScannerCameraController> createController(
    CameraDescription description,
  ) async {
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    return _PluginScannerCameraController(controller, description);
  }

  @override
  Future<bool> openAppSettings() => permissions.openAppSettings();
}

class _PluginScannerCameraController implements ScannerCameraController {
  _PluginScannerCameraController(this._controller, this.description);

  final CameraController _controller;

  @override
  final CameraDescription description;

  @override
  bool get initialized => _controller.value.isInitialized;

  @override
  double get aspectRatio => _controller.value.aspectRatio;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> dispose() => _controller.dispose();

  @override
  Future<XFile> takePicture() => _controller.takePicture();

  @override
  Future<void> setFlashMode(FlashMode mode) => _controller.setFlashMode(mode);
}

class ScannerCameraSession extends ChangeNotifier {
  ScannerCameraSession({ScannerCameraPlatform? platform})
    : _platform = platform ?? const PluginScannerCameraPlatform();

  final ScannerCameraPlatform _platform;
  ScannerCameraState _state = const ScannerCameraState();
  ScannerCameraController? _controller;
  Future<void> _serial = Future<void>.value();
  Future<XFile?>? _captureInFlight;
  int _generation = 0;
  bool _closed = false;
  bool _suspended = false;
  bool _flashDisabledForController = false;

  ScannerCameraState get state => _state;
  bool get isWeb => _platform.isWeb;
  bool get canSwitchLens => _canSwitchLens(_state.availableCameras);
  bool get canUseFlash => _state.flashSupported && !_flashDisabledForController;

  /// Starts (or restarts) camera discovery and initialization.
  Future<void> start() => _requestStart();

  Future<void> retry() => _requestStart();

  Future<void> _requestStart() {
    final token = ++_generation;
    _suspended = false;
    _publish(
      _state.copyWith(
        status: ScannerCameraStatus.loading,
        clearFailure: true,
        clearSelectedCamera: true,
        clearController: true,
        flashEnabled: false,
        flashSupported: false,
      ),
    );
    return _enqueue(() => _startOperation(token));
  }

  Future<void> _startOperation(int token) async {
    if (!_isCurrent(token)) return;
    await _detachController();
    if (!_isCurrent(token)) return;

    ScannerCameraPermission permission;
    try {
      permission = await _platform.requestPermission();
    } catch (error) {
      if (_isCurrent(token)) _publishFailure(_failureFor(error));
      return;
    }
    if (!_isCurrent(token)) return;
    if (permission != ScannerCameraPermission.granted) {
      final permanent = permission == ScannerCameraPermission.permanentlyDenied;
      _publish(
        _state.copyWith(
          status: permanent
              ? ScannerCameraStatus.permissionDeniedPermanently
              : ScannerCameraStatus.permissionDenied,
          failure: ScannerCameraFailure(
            kind: permanent
                ? ScannerCameraFailureKind.permissionDeniedPermanently
                : ScannerCameraFailureKind.permissionDenied,
          ),
          clearController: true,
          clearSelectedCamera: true,
          flashEnabled: false,
          flashSupported: false,
        ),
      );
      return;
    }

    List<CameraDescription> cameras;
    try {
      cameras = List<CameraDescription>.unmodifiable(
        await _platform.availableCameras(),
      );
    } catch (error) {
      if (_isCurrent(token)) _publishFailure(_failureFor(error));
      return;
    }
    if (!_isCurrent(token)) return;
    _publish(
      _state.copyWith(
        availableCameras: cameras,
        clearFailure: true,
        clearSelectedCamera: true,
        clearController: true,
        flashEnabled: false,
        flashSupported: false,
      ),
    );
    if (cameras.isEmpty) {
      _publish(
        _state.copyWith(
          status: ScannerCameraStatus.unavailable,
          failure: const ScannerCameraFailure(
            kind: ScannerCameraFailureKind.noCamera,
          ),
        ),
      );
      return;
    }

    await _initializeCandidates(_orderedCandidates(cameras), token);
  }

  Future<void> _initializeCandidates(
    List<CameraDescription> candidates,
    int token,
  ) async {
    ScannerCameraFailure? lastFailure;
    for (final description in candidates) {
      if (!_isCurrent(token)) return;
      ScannerCameraController? candidate;
      try {
        candidate = await _platform.createController(description);
        await candidate.initialize();
        if (!candidate.initialized) {
          lastFailure = const ScannerCameraFailure(
            kind: ScannerCameraFailureKind.initializationFailed,
          );
          await _disposeQuietly(candidate);
          continue;
        }
      } catch (error) {
        lastFailure = _failureFor(error);
        if (candidate != null) await _disposeQuietly(candidate);
        continue;
      }
      if (!_isCurrent(token)) {
        await _disposeQuietly(candidate);
        return;
      }
      _controller = candidate;
      _flashDisabledForController = false;
      final supportsFlash =
          !_platform.isWeb &&
          description.lensDirection == CameraLensDirection.back;
      _publish(
        _state.copyWith(
          status: ScannerCameraStatus.ready,
          selectedCamera: description,
          controller: candidate,
          clearFailure: true,
          flashEnabled: false,
          flashSupported: supportsFlash,
          isCapturing: false,
        ),
      );
      return;
    }
    if (_isCurrent(token)) {
      _publishFailure(
        lastFailure ??
            const ScannerCameraFailure(
              kind: ScannerCameraFailureKind.initializationFailed,
            ),
      );
    }
  }

  Future<void> switchLensDirection() {
    if (_closed || !_canSwitchLens(_state.availableCameras)) {
      return Future<void>.value();
    }
    final token = _generation;
    _publish(
      _state.copyWith(
        status: ScannerCameraStatus.switching,
        clearFailure: true,
        flashEnabled: false,
        flashSupported: false,
      ),
    );
    return _enqueue(() => _switchOperation(token));
  }

  Future<void> _switchOperation(int token) async {
    if (!_isCurrent(token)) return;
    final previous = _state.selectedCamera;
    if (previous == null) return;
    final targetDirection = previous.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final target = _pickPrimary(
      _state.availableCameras
          .where((camera) => camera.lensDirection == targetDirection)
          .toList(),
    );
    if (target == null) return;
    await _detachController();
    if (!_isCurrent(token)) return;
    await _initializeCandidates(<CameraDescription>[target, previous], token);
  }

  Future<void> suspend() {
    if (_closed || _suspended) return Future<void>.value();
    _suspended = true;
    final token = ++_generation;
    _publish(
      _state.copyWith(
        status: ScannerCameraStatus.loading,
        clearController: true,
        flashEnabled: false,
        flashSupported: false,
      ),
    );
    return _enqueue(() async {
      if (!_isCurrent(token)) return;
      await _detachController();
    });
  }

  Future<void> resume() {
    if (_closed || !_suspended && _controller != null) {
      return Future<void>.value();
    }
    return _requestStart();
  }

  Future<XFile?> capture() {
    final inFlight = _captureInFlight;
    if (inFlight != null) return Future<XFile?>.value(null);
    final controller = _controller;
    if (_state.status != ScannerCameraStatus.ready ||
        controller == null ||
        !controller.initialized) {
      return Future<XFile?>.value(null);
    }
    _publish(
      _state.copyWith(status: ScannerCameraStatus.busy, isCapturing: true),
    );
    final token = _generation;
    final future = _enqueue(() => _captureOperation(controller, token));
    _captureInFlight = future;
    future.whenComplete(() {
      if (identical(_captureInFlight, future)) _captureInFlight = null;
    });
    return future;
  }

  Future<XFile?> _captureOperation(
    ScannerCameraController controller,
    int token,
  ) async {
    try {
      final capture = await controller.takePicture();
      if (!_isCurrent(token) || !identical(_controller, controller)) {
        return null;
      }
      _publish(
        _state.copyWith(
          status: ScannerCameraStatus.ready,
          isCapturing: false,
          lastCapture: capture,
        ),
      );
      return capture;
    } catch (error) {
      if (_isCurrent(token)) {
        _publish(
          _state.copyWith(
            status: ScannerCameraStatus.error,
            isCapturing: false,
            failure: _failureFor(error),
          ),
        );
      }
      return null;
    }
  }

  Future<bool> toggleFlash() => setFlashEnabled(!_state.flashEnabled);

  Future<bool> openAppSettings() => _platform.openAppSettings();

  Future<bool> setFlashEnabled(bool enabled) {
    if (_closed || !canUseFlash || _controller == null) {
      if (_state.flashEnabled) {
        _publish(_state.copyWith(flashEnabled: false));
      }
      return Future<bool>.value(false);
    }
    final controller = _controller!;
    final token = _generation;
    return _enqueue(() => _setFlashOperation(controller, enabled, token));
  }

  Future<bool> _setFlashOperation(
    ScannerCameraController controller,
    bool enabled,
    int token,
  ) async {
    if (!_isCurrent(token) ||
        !identical(_controller, controller) ||
        !canUseFlash) {
      return false;
    }
    try {
      await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      if (!_isCurrent(token) || !identical(_controller, controller)) {
        if (enabled) {
          try {
            await controller.setFlashMode(FlashMode.off);
          } catch (_) {}
        }
        return false;
      }
      _publish(_state.copyWith(flashEnabled: enabled));
      return true;
    } catch (_) {
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (_isCurrent(token) && identical(_controller, controller)) {
        _flashDisabledForController = true;
        _publish(_state.copyWith(flashEnabled: false, flashSupported: false));
      }
      return false;
    }
  }

  Future<void> shutdown() {
    if (_closed) return Future<void>.value();
    _closed = true;
    ++_generation;
    return _enqueue(() async {
      await _detachController();
      _publish(
        _state.copyWith(
          status: ScannerCameraStatus.unavailable,
          clearController: true,
          clearSelectedCamera: true,
          flashEnabled: false,
          flashSupported: false,
        ),
      );
    });
  }

  Future<void> _detachController() async {
    final previous = _controller;
    _controller = null;
    if (previous != null) await _disposeQuietly(previous);
    if (!_closed) {
      _publish(
        _state.copyWith(
          clearController: true,
          clearSelectedCamera: true,
          flashEnabled: false,
          flashSupported: false,
        ),
      );
    }
  }

  Future<void> _disposeQuietly(ScannerCameraController controller) async {
    try {
      await controller.dispose();
    } catch (_) {}
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _serial.then<T>((_) => operation());
    _serial = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  bool _isCurrent(int token) => !_closed && token == _generation;

  void _publish(ScannerCameraState state) {
    _state = state;
    if (!_closed) notifyListeners();
  }

  void _publishFailure(ScannerCameraFailure failure) {
    final status = switch (failure.kind) {
      ScannerCameraFailureKind.permissionDenied =>
        ScannerCameraStatus.permissionDenied,
      ScannerCameraFailureKind.permissionDeniedPermanently =>
        ScannerCameraStatus.permissionDeniedPermanently,
      ScannerCameraFailureKind.noCamera ||
      ScannerCameraFailureKind.unsupported => ScannerCameraStatus.unavailable,
      _ => ScannerCameraStatus.error,
    };
    _publish(
      _state.copyWith(
        status: status,
        failure: failure,
        clearController: true,
        clearSelectedCamera: true,
        flashEnabled: false,
        flashSupported: false,
      ),
    );
  }

  List<CameraDescription> _orderedCandidates(List<CameraDescription> cameras) {
    final ordered = <CameraDescription>[];
    for (final direction in <CameraLensDirection>[
      CameraLensDirection.back,
      CameraLensDirection.front,
      CameraLensDirection.external,
    ]) {
      final matching = cameras
          .where((camera) => camera.lensDirection == direction)
          .toList();
      matching.sort((a, b) => a.name.compareTo(b.name));
      ordered.addAll(matching);
    }
    ordered.addAll(cameras.where((camera) => !ordered.contains(camera)));
    return ordered;
  }

  CameraDescription? _pickPrimary(List<CameraDescription> cameras) {
    if (cameras.isEmpty) return null;
    cameras.sort((a, b) => a.name.compareTo(b.name));
    return cameras.first;
  }

  bool _canSwitchLens(List<CameraDescription> cameras) {
    final selected = _state.selectedCamera;
    if (selected == null) return false;
    final opposite = selected.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    return cameras.any((camera) => camera.lensDirection == opposite);
  }

  ScannerCameraFailure _failureFor(Object error) {
    if (error is CameraException) {
      final code = _sanitizeCode(error.code);
      return ScannerCameraFailure(kind: _kindForCode(code), code: code);
    }
    return const ScannerCameraFailure(
      kind: ScannerCameraFailureKind.initializationFailed,
    );
  }

  ScannerCameraFailureKind _kindForCode(String? code) {
    final value = (code ?? '').toLowerCase();
    if (value.contains('withoutprompt') ||
        value.contains('without_prompt') ||
        value.contains('permanent') ||
        value.contains('restricted')) {
      return ScannerCameraFailureKind.permissionDeniedPermanently;
    }
    if (value.contains('permission') || value.contains('denied')) {
      return ScannerCameraFailureKind.permissionDenied;
    }
    if (value.contains('cameraaccess') && !value.contains('denied')) {
      return ScannerCameraFailureKind.cameraInUse;
    }
    if (value.contains('inuse') ||
        value.contains('in_use') ||
        value.contains('busy')) {
      return ScannerCameraFailureKind.cameraInUse;
    }
    if (value.contains('cameranotreadable') ||
        value.contains('notreadable') ||
        value.contains('not_readable')) {
      return ScannerCameraFailureKind.notReadable;
    }
    if (value.contains('cameranotfound') ||
        value.contains('no_camera') ||
        value.contains('nocamera') ||
        value.contains('notfound')) {
      return ScannerCameraFailureKind.noCamera;
    }
    if (value.contains('unsupported') ||
        value.contains('notsupported') ||
        value.contains('not_supported') ||
        value.contains('cameratype') ||
        value.contains('security') ||
        value.contains('overconstrained')) {
      return ScannerCameraFailureKind.unsupported;
    }
    return ScannerCameraFailureKind.initializationFailed;
  }

  String? _sanitizeCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized;
  }
}

typedef ScannerCameraCoordinator = ScannerCameraSession;
typedef ScannerCameraService = ScannerCameraSession;
