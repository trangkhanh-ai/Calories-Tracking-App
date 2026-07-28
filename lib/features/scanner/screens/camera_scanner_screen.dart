import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../providers/scanner_provider.dart';
import '../services/scanner_camera_service.dart';
import '../services/scanner_image_source.dart';
import '../widgets/capture_button.dart';
import '../widgets/scan_frame_overlay.dart';

class CameraScannerScreen extends ConsumerStatefulWidget {
  const CameraScannerScreen({super.key, this.cameraSession, this.imageSource});

  final ScannerCameraSession? cameraSession;
  final ScannerImageSource? imageSource;

  @override
  ConsumerState<CameraScannerScreen> createState() =>
      _CameraScannerScreenState();
}

class _CameraScannerScreenState extends ConsumerState<CameraScannerScreen>
    with WidgetsBindingObserver {
  late final ScannerCameraSession _cameraSession;
  late final ScannerImageSource _imageSource;
  late final bool _ownsCameraSession;
  bool _isAnalyzing = false;
  bool _isLifecycleResumed = true;
  String _currentTip = '';
  int _tipIndex = 0;
  Timer? _tipTimer;

  static const List<String> _tips = [
    '💡 Đặt món ăn vào giữa khung',
    '☀️ Đảm bảo ánh sáng đầy đủ',
    '📏 Giữ camera cách đồ ăn 20–40cm',
    '✋ Giữ tay thật thẳng để ảnh rõ nét',
    '🍽️ Một món ăn trong khung cho kết quả tốt nhất',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsCameraSession = widget.cameraSession == null;
    _cameraSession = widget.cameraSession ?? ScannerCameraSession();
    _imageSource = widget.imageSource ?? PluginScannerImageSource();
    _cameraSession.addListener(_onCameraStateChanged);
    _currentTip = _tips.first;
    unawaited(_cameraSession.start());
    _startTipRotation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tipTimer?.cancel();
    _cameraSession.removeListener(_onCameraStateChanged);
    if (_ownsCameraSession) {
      unawaited(_cameraSession.shutdown());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isLifecycleResumed = state == AppLifecycleState.resumed;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isAnalyzing) unawaited(_cameraSession.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_cameraSession.suspend());
    }
  }

  void _onCameraStateChanged() {
    if (mounted) setState(() {});
  }

  void _startTipRotation() {
    _tipTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _tipIndex = (_tipIndex + 1) % _tips.length;
        _currentTip = _tips[_tipIndex];
      });
    });
  }

  Future<void> _switchCamera() => _cameraSession.switchLensDirection();

  Future<void> _toggleFlash() async {
    final enabled = await _cameraSession.setFlashEnabled(
      !_cameraSession.state.flashEnabled,
    );
    if (!enabled && mounted) {
      _showErrorSnackBar('Đèn flash không được hỗ trợ trên camera này.');
    }
  }

  Future<void> _captureImage() async {
    try {
      final file = await _cameraSession.capture();
      if (file != null) await _processImage(file);
    } catch (error) {
      debugPrint('Camera capture failed (${error.runtimeType})');
      if (mounted) {
        _showErrorSnackBar('Không thể chụp ảnh. Hãy thử lại.');
      }
    }
  }

  Future<void> _captureWithRearCamera() async {
    try {
      final picked = await _imageSource.captureRearCamera();
      if (picked != null) await _processImage(picked);
    } catch (error) {
      debugPrint('Rear camera picker failed (${error.runtimeType})');
      if (mounted) {
        _showErrorSnackBar(
          'Không thể mở camera sau. Hãy kiểm tra quyền camera của trình duyệt.',
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _imageSource.pickGallery();
      if (picked != null) await _processImage(picked);
    } catch (error) {
      debugPrint('Gallery picker failed (${error.runtimeType})');
      if (mounted) {
        _showErrorSnackBar('Không thể mở thư viện ảnh. Hãy thử lại.');
      }
    }
  }

  Future<void> _processImage(XFile image) async {
    if (_isAnalyzing) return;
    setState(() => _isAnalyzing = true);
    await _cameraSession.suspend();
    var pickAnotherFromGallery = false;

    try {
      pickAnotherFromGallery = await _analyzeImage(image);
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        if (_isLifecycleResumed) await _cameraSession.resume();
      }
    }

    if (pickAnotherFromGallery && mounted) {
      await _pickFromGallery();
    }
  }

  Future<bool> _analyzeImage(XFile image) async {
    if (!mounted) return false;
    _showLoadingOverlay();

    final result = await ref
        .read(scanProvider.notifier)
        .analyzeImage(image.path);

    if (!mounted) return false;
    Navigator.of(context).pop();

    if (result == null) {
      final scanState = ref.read(scanProvider);
      _showErrorSnackBar(scanState.errorMessage ?? 'Không thể phân tích ảnh.');
      return false;
    }

    if (!result.foodDetected) {
      return _showNoFoodDialog();
    }

    if (result.imageQuality == 'low_light') {
      _showQualityWarning(
        '💡 Ảnh hơi tối — kết quả có thể kém chính xác hơn',
        result,
      );
    }

    await context.pushNamed('results', extra: result);
    return false;
  }

  void _showLoadingOverlay() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AnalyzingOverlay(),
    );
  }

  Future<bool> _showNoFoodDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              '🤔 Không tìm thấy thức ăn',
              style: TextStyle(color: AppTheme.onBackground),
            ),
            content: const Text(
              'Hãy đảm bảo khung hình chứa món ăn rõ ràng và ánh sáng đủ.',
              style: TextStyle(color: AppTheme.onSurface),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Thử lại',
                  style: TextStyle(color: AppTheme.primary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Chọn từ thư viện',
                  style: TextStyle(color: AppTheme.onSurface),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showQualityWarning(String message, Object result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.warning,
        action: SnackBarAction(
          label: 'Xem kết quả',
          textColor: Colors.white,
          onPressed: () => context.pushNamed('results', extra: result),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        action: SnackBarAction(
          label: 'Thử lại',
          textColor: Colors.white,
          onPressed: () => unawaited(_cameraSession.retry()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraState = _cameraSession.state;
    final isReady =
        cameraState.status == ScannerCameraStatus.ready ||
        cameraState.status == ScannerCameraStatus.busy;
    final showScannerChrome =
        isReady ||
        cameraState.status == ScannerCameraStatus.loading ||
        cameraState.status == ScannerCameraStatus.switching;
    final actionsLocked =
        cameraState.status == ScannerCameraStatus.busy || _isAnalyzing;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          children: [
            _CameraSurface(
              state: cameraState,
              isWeb: _cameraSession.isWeb,
              onRetry: _cameraSession.retry,
              onCaptureRear: _captureWithRearCamera,
              onPickGallery: _pickFromGallery,
              onOpenSettings: _cameraSession.openAppSettings,
            ),
            if (showScannerChrome)
              const Positioned.fill(child: ScanFrameOverlay()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _IconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => context.pop(),
                    ),
                    const Spacer(),
                    const Text(
                      'Quét Thức Ăn',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_cameraSession.canUseFlash)
                      _IconButton(
                        icon: cameraState.flashEnabled
                            ? Icons.flash_on
                            : Icons.flash_off,
                        onTap: _toggleFlash,
                        active: cameraState.flashEnabled,
                      )
                    else
                      const SizedBox(width: 40),
                  ],
                ),
              ),
            ),
            if (isReady)
              Positioned(
                bottom: 160,
                left: 0,
                right: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    _currentTip,
                    key: ValueKey(_currentTip),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            if (isReady)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 40,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ActionButton(
                          icon: Icons.photo_library_outlined,
                          label: 'Thư viện',
                          onTap: actionsLocked ? null : _pickFromGallery,
                        ),
                        CaptureButton(
                          onTap: _captureImage,
                          isProcessing:
                              cameraState.status == ScannerCameraStatus.busy ||
                              _isAnalyzing,
                        ),
                        _ActionButton(
                          icon: Icons.flip_camera_ios_outlined,
                          label: 'Đổi camera',
                          onTap: !actionsLocked && _cameraSession.canSwitchLens
                              ? _switchCamera
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface({
    required this.state,
    required this.isWeb,
    required this.onRetry,
    required this.onCaptureRear,
    required this.onPickGallery,
    required this.onOpenSettings,
  });

  final ScannerCameraState state;
  final bool isWeb;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCaptureRear;
  final Future<void> Function() onPickGallery;
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final controller = state.controller;
    if (controller != null &&
        (state.status == ScannerCameraStatus.ready ||
            state.status == ScannerCameraStatus.busy)) {
      return Positioned.fill(
        key: const ValueKey('camera-preview-shell'),
        child: Builder(
          builder: (context) {
            final size = MediaQuery.of(context).size;
            final deviceRatio = size.width / size.height;
            final isLandscape =
                MediaQuery.of(context).orientation == Orientation.landscape;
            final previewRatio = isLandscape
                ? controller.aspectRatio
                : (1 / controller.aspectRatio);

            final previewWidth = previewRatio > deviceRatio
                ? size.height * previewRatio
                : size.width;
            final previewHeight = previewRatio > deviceRatio
                ? size.height
                : size.width / previewRatio;

            return ClipRect(
              child: OverflowBox(
                maxWidth: previewWidth,
                maxHeight: previewHeight,
                minWidth: previewWidth,
                minHeight: previewHeight,
                child: SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: controller.buildPreview(),
                ),
              ),
            );
          },
        ),
      );
    }

    if (state.status == ScannerCameraStatus.loading ||
        state.status == ScannerCameraStatus.switching) {
      return Center(
        key: const ValueKey('camera-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(
              state.status == ScannerCameraStatus.switching
                  ? 'Đang đổi camera...'
                  : 'Đang mở camera sau...',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return _CameraUnavailableFallback(
      state: state,
      isWeb: isWeb,
      onRetry: onRetry,
      onCaptureRear: onCaptureRear,
      onPickGallery: onPickGallery,
      onOpenSettings: onOpenSettings,
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: active
              ? Border.all(color: AppTheme.primary, width: 1.5)
              : null,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyzingOverlay extends StatelessWidget {
  const _AnalyzingOverlay();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Đang nhận diện thức ăn...',
              style: TextStyle(
                color: AppTheme.onBackground,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'AI đang phân tích ảnh của bạn',
              style: TextStyle(color: AppTheme.onSurface, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraUnavailableFallback extends StatelessWidget {
  const _CameraUnavailableFallback({
    required this.state,
    required this.isWeb,
    required this.onRetry,
    required this.onCaptureRear,
    required this.onPickGallery,
    required this.onOpenSettings,
  });

  final ScannerCameraState state;
  final bool isWeb;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCaptureRear;
  final Future<void> Function() onPickGallery;
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final failure = state.failure?.kind;
    final permanent =
        state.status == ScannerCameraStatus.permissionDeniedPermanently;
    final permissionDenied =
        state.status == ScannerCameraStatus.permissionDenied || permanent;

    final title = switch (failure) {
      ScannerCameraFailureKind.permissionDenied => 'Quyền camera bị từ chối',
      ScannerCameraFailureKind.permissionDeniedPermanently =>
        'Quyền camera đã bị chặn',
      ScannerCameraFailureKind.noCamera => 'Không tìm thấy camera',
      ScannerCameraFailureKind.cameraInUse => 'Camera đang được sử dụng',
      ScannerCameraFailureKind.notReadable => 'Camera không thể đọc được',
      ScannerCameraFailureKind.unsupported =>
        'Thiết bị hoặc trình duyệt chưa hỗ trợ',
      ScannerCameraFailureKind.initializationFailed ||
      null => 'Camera không khả dụng',
    };

    final instructions = permissionDenied && isWeb
        ? 'Hãy mở cài đặt trang web của trình duyệt, cho phép quyền Camera rồi nhấn Thử lại.'
        : switch (failure) {
            ScannerCameraFailureKind.permissionDenied =>
              'Ứng dụng cần quyền camera để quét thức ăn. Hãy cấp quyền rồi thử lại.',
            ScannerCameraFailureKind.permissionDeniedPermanently =>
              'Hãy mở cài đặt ứng dụng và bật lại quyền Camera.',
            ScannerCameraFailureKind.noCamera =>
              'Không có camera phù hợp. Bạn vẫn có thể chụp nhanh hoặc chọn ảnh có sẵn.',
            ScannerCameraFailureKind.cameraInUse =>
              'Hãy đóng ứng dụng hoặc tab khác đang dùng camera rồi thử lại.',
            ScannerCameraFailureKind.notReadable =>
              'Camera đang bận hoặc không thể đọc luồng hình ảnh. Hãy thử lại sau khi đóng ứng dụng khác.',
            ScannerCameraFailureKind.unsupported =>
              'Camera trực tiếp không hoạt động trong môi trường này. Hãy dùng tùy chọn chụp nhanh hoặc thư viện.',
            ScannerCameraFailureKind.initializationFailed || null =>
              'Không thể khởi tạo camera. Bạn có thể thử lại hoặc dùng ảnh có sẵn.',
          };

    final stateKey = permanent
        ? 'camera-permission-permanent'
        : state.status == ScannerCameraStatus.permissionDenied
        ? 'camera-permission-denied'
        : 'camera-failure-content';

    return Container(
      key: const ValueKey('camera-fallback'),
      color: AppTheme.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
          child: Column(
            key: ValueKey(stateKey),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📷', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.onBackground,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                instructions,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.onSurface, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                key: const ValueKey('camera-retry'),
                onPressed: () => unawaited(onRetry()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử lại'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('camera-rear-fallback'),
                onPressed: () => unawaited(onCaptureRear()),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Chụp bằng camera sau'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('camera-gallery-fallback'),
                onPressed: () => unawaited(onPickGallery()),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Chọn ảnh từ thư viện'),
              ),
              if (permanent && !isWeb) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('camera-open-settings'),
                  onPressed: () => unawaited(onOpenSettings()),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Mở cài đặt'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
