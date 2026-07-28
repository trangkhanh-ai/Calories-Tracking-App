import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/features/scanner/services/scanner_image_source.dart';

class _RecordingImagePicker {
  ImageSource? source;
  CameraDevice? preferredCameraDevice;
  double? maxWidth;
  int? imageQuality;

  Future<XFile?> pickImage({
    required ImageSource source,
    required CameraDevice preferredCameraDevice,
    required double maxWidth,
    required int imageQuality,
  }) async {
    this.source = source;
    this.preferredCameraDevice = preferredCameraDevice;
    this.maxWidth = maxWidth;
    this.imageQuality = imageQuality;
    return XFile('blob:test-image');
  }
}

void main() {
  late _RecordingImagePicker picker;
  late ScannerImageSource source;

  setUp(() {
    picker = _RecordingImagePicker();
    source = PluginScannerImageSource(pickImage: picker.pickImage);
  });

  test('rear camera fallback requests the browser rear-camera hint', () async {
    final image = await source.captureRearCamera();

    expect(image?.path, 'blob:test-image');
    expect(picker.source, ImageSource.camera);
    expect(picker.preferredCameraDevice, CameraDevice.rear);
    expect(picker.maxWidth, 1024);
    expect(picker.imageQuality, 85);
  });

  test('gallery fallback remains a separate image source', () async {
    await source.pickGallery();

    expect(picker.source, ImageSource.gallery);
    expect(picker.maxWidth, 1024);
    expect(picker.imageQuality, 85);
  });
}
