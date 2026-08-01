import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum ScannerPreviewFit { contain, cover }

@immutable
class ScannerPreviewGeometry {
  const ScannerPreviewGeometry({
    required this.previewRect,
    required this.visibleRect,
    required this.normalizedAspectRatio,
    required this.usedFallbackRatio,
  });

  final Rect previewRect;
  final Rect visibleRect;
  final double normalizedAspectRatio;
  final bool usedFallbackRatio;

  static ScannerPreviewGeometry calculate(
    Size viewport,
    double rawAspectRatio,
    ScannerPreviewFit fit,
  ) {
    final usedFallbackRatio = !(rawAspectRatio.isFinite && rawAspectRatio > 0);
    final validAspectRatio = usedFallbackRatio ? 4 / 3 : rawAspectRatio;
    final isPortrait = viewport.height > viewport.width;
    final normalizedAspectRatio = isPortrait
        ? (validAspectRatio > 1 ? 1 / validAspectRatio : validAspectRatio)
        : (validAspectRatio < 1 ? 1 / validAspectRatio : validAspectRatio);

    if (!viewport.isFinite || viewport.width <= 0 || viewport.height <= 0) {
      return ScannerPreviewGeometry(
        previewRect: Rect.zero,
        visibleRect: Rect.zero,
        normalizedAspectRatio: normalizedAspectRatio,
        usedFallbackRatio: usedFallbackRatio,
      );
    }

    final source = Size(normalizedAspectRatio, 1);
    final widthScale = viewport.width / source.width;
    final heightScale = viewport.height / source.height;
    final scale = fit == ScannerPreviewFit.contain
        ? math.min(widthScale, heightScale)
        : math.max(widthScale, heightScale);
    final fitted = Size(source.width * scale, source.height * scale);
    final offset = Offset(
      (viewport.width - fitted.width) / 2,
      (viewport.height - fitted.height) / 2,
    );
    final previewRect = offset & fitted;

    return ScannerPreviewGeometry(
      previewRect: previewRect,
      visibleRect: fit == ScannerPreviewFit.contain
          ? previewRect
          : Offset.zero & viewport,
      normalizedAspectRatio: normalizedAspectRatio,
      usedFallbackRatio: usedFallbackRatio,
    );
  }
}
