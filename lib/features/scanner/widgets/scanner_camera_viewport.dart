import 'package:flutter/widgets.dart';

import '../services/scanner_camera_service.dart';
import 'scan_frame_overlay.dart';
import 'scanner_preview_geometry.dart';

class ScannerCameraViewport extends StatelessWidget {
  const ScannerCameraViewport({
    super.key,
    required this.controller,
    required this.isWeb,
  });

  final ScannerCameraController controller;
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = ScannerPreviewGeometry.calculate(
          constraints.biggest,
          controller.aspectRatio,
          isWeb ? ScannerPreviewFit.contain : ScannerPreviewFit.cover,
        );

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fromRect(
              rect: geometry.previewRect,
              child: KeyedSubtree(
                key: const ValueKey('camera-preview-geometry'),
                child: controller.buildPreview(),
              ),
            ),
            Positioned.fromRect(
              rect: geometry.visibleRect,
              child: const KeyedSubtree(
                key: ValueKey('camera-overlay-geometry'),
                child: ScanFrameOverlay(),
              ),
            ),
          ],
        );
      },
    );
  }
}
