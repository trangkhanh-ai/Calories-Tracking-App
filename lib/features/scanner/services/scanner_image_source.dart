import 'package:image_picker/image_picker.dart';

typedef ScannerPickImage =
    Future<XFile?> Function({
      required ImageSource source,
      required CameraDevice preferredCameraDevice,
      required double maxWidth,
      required int imageQuality,
    });

abstract interface class ScannerImageSource {
  Future<XFile?> captureRearCamera();

  Future<XFile?> pickGallery();
}

class PluginScannerImageSource implements ScannerImageSource {
  PluginScannerImageSource({ScannerPickImage? pickImage})
    : _pickImage = pickImage ?? _pickWithPlugin;

  final ScannerPickImage _pickImage;

  static Future<XFile?> _pickWithPlugin({
    required ImageSource source,
    required CameraDevice preferredCameraDevice,
    required double maxWidth,
    required int imageQuality,
  }) {
    return ImagePicker().pickImage(
      source: source,
      preferredCameraDevice: preferredCameraDevice,
      maxWidth: maxWidth,
      imageQuality: imageQuality,
    );
  }

  @override
  Future<XFile?> captureRearCamera() {
    // preferredCameraDevice is a browser hint and may be ignored by some
    // mobile browsers or Android camera intents.
    return _pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 1024,
      imageQuality: 85,
    );
  }

  @override
  Future<XFile?> pickGallery() {
    return _pickImage(
      source: ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 1024,
      imageQuality: 85,
    );
  }
}
