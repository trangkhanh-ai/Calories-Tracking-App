import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/scanner_provider.dart';
import '../widgets/scan_frame_overlay.dart';
import '../widgets/capture_button.dart';
import '../../../app/theme.dart';

class CameraScannerScreen extends ConsumerStatefulWidget {
  const CameraScannerScreen({super.key});

  @override
  ConsumerState<CameraScannerScreen> createState() =>
      _CameraScannerScreenState();
}

class _CameraScannerScreenState extends ConsumerState<CameraScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCamera = 0;
  bool _flashOn = false;
  bool _isInitialized = false;
  bool _cameraUnavailable = false;
  bool _isCapturing = false;
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
    _currentTip = _tips[0];
    _initCamera();
    _startTipRotation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tipTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _isInitialized = false;
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
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

  Future<void> _initCamera() async {
    if (!kIsWeb) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) _showPermissionDeniedDialog();
        return;
      }
    }

    try {
      _cameras = await availableCameras();
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _cameraUnavailable = true);
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _cameraUnavailable = true);
      return;
    }

    try {
      await _cameraController?.dispose();
      _cameraController = CameraController(
        _cameras[_selectedCamera],
        ResolutionPreset.medium, // Giảm từ high xuống medium để AI quét nhanh gấp 5 lần
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Camera controller error: $e');
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() {
      _selectedCamera = (_selectedCamera + 1) % _cameras.length;
      _isInitialized = false;
    });
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    setState(() => _flashOn = !_flashOn);
    await _cameraController!.setFlashMode(
      _flashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || !_isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final file = await _cameraController!.takePicture();
      await _analyzeImage(file.path);
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Lỗi chụp ảnh: $e');
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked != null) {
      await _analyzeImage(picked.path);
    }
  }

  Future<void> _analyzeImage(String imagePath) async {
    // Show loading overlay
    if (!mounted) return;
    _showLoadingOverlay();

    final result = await ref.read(scanProvider.notifier).analyzeImage(imagePath);

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading overlay

    if (result != null) {
      if (!result.foodDetected) {
        _showNoFoodDialog();
      } else if (result.imageQuality == 'low_light') {
        _showQualityWarning('💡 Ảnh hơi tối — kết quả có thể kém chính xác hơn', result, imagePath);
      } else {
        context.pushNamed('results', extra: result);
      }
    } else {
      final scanState = ref.read(scanProvider);
      _showErrorSnackBar(scanState.errorMessage ?? 'Lỗi không xác định');
    }
  }

  void _showLoadingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AnalyzingOverlay(),
    );
  }

  void _showNoFoodDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🤔 Không tìm thấy thức ăn',
            style: TextStyle(color: AppTheme.onBackground)),
        content: const Text(
          'Hãy đảm bảo khung hình chứa món ăn rõ ràng và ánh sáng đủ.',
          style: TextStyle(color: AppTheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Thử lại', style: TextStyle(color: AppTheme.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickFromGallery();
            },
            child: const Text('Chọn từ thư viện',
                style: TextStyle(color: AppTheme.onSurface)),
          ),
        ],
      ),
    );
  }

  void _showQualityWarning(String message, result, String imagePath) {
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
    // Also navigate to results 
    context.pushNamed('results', extra: result);
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
          onPressed: () {},
        ),
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('📷 Cần quyền Camera',
            style: TextStyle(color: AppTheme.onBackground)),
        content: const Text(
          'App cần quyền truy cập camera để quét thức ăn.',
          style: TextStyle(color: AppTheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Mở cài đặt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Camera preview
            if (_cameraUnavailable)
              _CameraUnavailableFallback(onPickGallery: _pickFromGallery)
            else if (_cameraController != null && _cameraController!.value.isInitialized)
              Positioned.fill(
                child: Builder(builder: (context) {
                  final size = MediaQuery.of(context).size;
                  final deviceRatio = size.width / size.height;
                  final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                  final previewRatio = isLandscape 
                      ? _cameraController!.value.aspectRatio 
                      : (1 / _cameraController!.value.aspectRatio);
                  
                  double previewWidth;
                  double previewHeight;

                  if (previewRatio > deviceRatio) {
                    // Màn hình hẹp hơn so với camera (ví dụ điện thoại dọc)
                    previewHeight = size.height;
                    previewWidth = size.height * previewRatio;
                  } else {
                    // Màn hình rộng hơn so với camera (ví dụ Web ngang)
                    previewWidth = size.width;
                    previewHeight = size.width / previewRatio;
                  }
                      
                  return ClipRect(
                    child: OverflowBox(
                      maxWidth: previewWidth,
                      maxHeight: previewHeight,
                      minWidth: previewWidth,
                      minHeight: previewHeight,
                      child: SizedBox(
                        width: previewWidth,
                        height: previewHeight,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  );
                }),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),

            // Scan frame overlay
            const Positioned.fill(child: ScanFrameOverlay()),

            // Top bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Back button
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
                    // Flash toggle
                    _IconButton(
                      icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                      onTap: _toggleFlash,
                      active: _flashOn,
                    ),
                  ],
                ),
              ),
            ),

            // Tip text (center bottom of frame)
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

            // Bottom action bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Gallery picker
                      _ActionButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Thư viện',
                        onTap: _pickFromGallery,
                      ),

                      // Main capture button
                      CaptureButton(
                        onTap: _captureImage,
                        isProcessing: _isCapturing,
                      ),

                      // Switch camera
                      _ActionButton(
                        icon: Icons.flip_camera_ios_outlined,
                        label: 'Đổi camera',
                        onTap: _switchCamera,
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

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  const _IconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
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
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Đang nhận diện thức ăn...',
              style: TextStyle(
                color: AppTheme.onBackground,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
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
  final VoidCallback onPickGallery;
  const _CameraUnavailableFallback({required this.onPickGallery});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📷', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text(
                'Camera không khả dụng',
                style: TextStyle(
                  color: AppTheme.onBackground,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Trên web, camera cần quyền từ trình duyệt.\nHãy chọn ảnh từ thư viện để thử nghiệm.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.onSurface, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onPickGallery,
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Chọn ảnh từ thư viện'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
