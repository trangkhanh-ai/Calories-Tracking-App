import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/scanner/widgets/scanner_preview_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const _portrait = Size(375, 667);
const _tallPortrait = Size(390, 844);
const _landscape = Size(667, 375);
const _tolerance = 0.0001;

void main() {
  group('ScannerPreviewGeometry contain', () {
    test('keeps 4:3 and 3:4 equivalent in portrait', () {
      final wide = ScannerPreviewGeometry.calculate(
        _portrait,
        4 / 3,
        ScannerPreviewFit.contain,
      );
      final tall = ScannerPreviewGeometry.calculate(
        _portrait,
        3 / 4,
        ScannerPreviewFit.contain,
      );

      expect(wide.previewRect, tall.previewRect);
      expect(wide.visibleRect, tall.visibleRect);
      expect(wide.normalizedAspectRatio, closeTo(3 / 4, _tolerance));
      expect(tall.normalizedAspectRatio, closeTo(3 / 4, _tolerance));
      expect(wide.usedFallbackRatio, isFalse);
      expect(tall.usedFallbackRatio, isFalse);
      _expectContainedAndCentered(wide, _portrait);
    });

    test('keeps 16:9 and 9:16 equivalent in tall portrait', () {
      final wide = ScannerPreviewGeometry.calculate(
        _tallPortrait,
        16 / 9,
        ScannerPreviewFit.contain,
      );
      final tall = ScannerPreviewGeometry.calculate(
        _tallPortrait,
        9 / 16,
        ScannerPreviewFit.contain,
      );

      expect(wide.previewRect, tall.previewRect);
      expect(wide.visibleRect, tall.visibleRect);
      expect(wide.normalizedAspectRatio, closeTo(9 / 16, _tolerance));
      expect(tall.normalizedAspectRatio, closeTo(9 / 16, _tolerance));
      expect(wide.usedFallbackRatio, isFalse);
      expect(tall.usedFallbackRatio, isFalse);
      _expectContainedAndCentered(wide, _tallPortrait);
    });

    test('normalizes 4:3 and 3:4 equivalently in landscape', () {
      final wide = ScannerPreviewGeometry.calculate(
        _landscape,
        4 / 3,
        ScannerPreviewFit.contain,
      );
      final tall = ScannerPreviewGeometry.calculate(
        _landscape,
        3 / 4,
        ScannerPreviewFit.contain,
      );

      expect(wide.previewRect, tall.previewRect);
      expect(wide.visibleRect, tall.visibleRect);
      expect(wide.normalizedAspectRatio, closeTo(4 / 3, _tolerance));
      expect(tall.normalizedAspectRatio, closeTo(4 / 3, _tolerance));
      expect(wide.usedFallbackRatio, isFalse);
      expect(tall.usedFallbackRatio, isFalse);
      _expectContainedAndCentered(wide, _landscape);
    });

    test('treats square viewports as landscape', () {
      const square = Size(400, 400);
      final geometry = ScannerPreviewGeometry.calculate(
        square,
        3 / 4,
        ScannerPreviewFit.contain,
      );

      expect(geometry.normalizedAspectRatio, closeTo(4 / 3, _tolerance));
      expect(geometry.previewRect.width, closeTo(400, _tolerance));
      expect(geometry.previewRect.height, closeTo(300, _tolerance));
      expect(geometry.usedFallbackRatio, isFalse);
      _expectContainedAndCentered(geometry, square);
    });

    test('never exceeds the viewport and preserves the normalized ratio', () {
      final geometry = ScannerPreviewGeometry.calculate(
        _tallPortrait,
        4 / 3,
        ScannerPreviewFit.contain,
      );

      expect(geometry.normalizedAspectRatio, closeTo(3 / 4, _tolerance));
      expect(geometry.usedFallbackRatio, isFalse);
      _expectContainedAndCentered(geometry, _tallPortrait);
    });
  });

  test('cover preserves ratio, centers, and exposes the viewport', () {
    final geometry = ScannerPreviewGeometry.calculate(
      _tallPortrait,
      4 / 3,
      ScannerPreviewFit.cover,
    );

    expect(geometry.normalizedAspectRatio, closeTo(3 / 4, _tolerance));
    expect(geometry.usedFallbackRatio, isFalse);
    expect(geometry.previewRect.width, closeTo(633, _tolerance));
    expect(geometry.previewRect.height, closeTo(844, _tolerance));
    expect(
      geometry.previewRect.width > _tallPortrait.width ||
          geometry.previewRect.height > _tallPortrait.height,
      isTrue,
    );
    _expectCentered(geometry.previewRect, _tallPortrait);
    _expectRatio(geometry.previewRect, geometry.normalizedAspectRatio);
    expect(geometry.visibleRect, Offset.zero & _tallPortrait);
  });

  test('zero, negative, NaN, and infinity use the safe fallback ratio', () {
    for (final rawRatio in <double>[0, -1, double.nan, double.infinity]) {
      final geometry = ScannerPreviewGeometry.calculate(
        _portrait,
        rawRatio,
        ScannerPreviewFit.contain,
      );

      expect(geometry.usedFallbackRatio, isTrue, reason: '$rawRatio');
      expect(
        geometry.normalizedAspectRatio,
        closeTo(3 / 4, _tolerance),
        reason: '$rawRatio',
      );
      expect(geometry.previewRect.isFinite, isTrue, reason: '$rawRatio');
      expect(geometry.visibleRect.isFinite, isTrue, reason: '$rawRatio');
      _expectContainedAndCentered(geometry, _portrait);
    }
  });

  test('invalid ratio still normalizes before a zero-viewport return', () {
    final geometry = ScannerPreviewGeometry.calculate(
      Size.zero,
      double.nan,
      ScannerPreviewFit.contain,
    );

    expect(geometry.previewRect, Rect.zero);
    expect(geometry.visibleRect, Rect.zero);
    expect(geometry.normalizedAspectRatio, closeTo(4 / 3, _tolerance));
    expect(geometry.usedFallbackRatio, isTrue);
  });

  test('non-positive viewport dimensions return zero rectangles', () {
    const cases = <(Size, double)>[
      (Size.zero, 4 / 3),
      (Size(0, 667), 3 / 4),
      (Size(375, 0), 4 / 3),
      (Size(-1, 667), 3 / 4),
      (Size(375, -1), 4 / 3),
    ];

    for (final (viewport, expectedRatio) in cases) {
      final geometry = ScannerPreviewGeometry.calculate(
        viewport,
        4 / 3,
        ScannerPreviewFit.contain,
      );

      expect(geometry.previewRect, Rect.zero, reason: '$viewport');
      expect(geometry.visibleRect, Rect.zero, reason: '$viewport');
      expect(
        geometry.normalizedAspectRatio,
        closeTo(expectedRatio, _tolerance),
        reason: '$viewport',
      );
      expect(geometry.usedFallbackRatio, isFalse, reason: '$viewport');
    }
  });

  test('non-finite viewport dimensions return safe zero geometry', () {
    const cases = <(Size, double)>[
      (Size(double.nan, 667), 4 / 3),
      (Size(double.infinity, 667), 4 / 3),
      (Size(375, double.nan), 4 / 3),
      (Size(375, double.infinity), 3 / 4),
    ];

    for (final (viewport, expectedRatio) in cases) {
      final geometry = ScannerPreviewGeometry.calculate(
        viewport,
        4 / 3,
        ScannerPreviewFit.contain,
      );

      expect(geometry.previewRect, Rect.zero, reason: '$viewport');
      expect(geometry.visibleRect, Rect.zero, reason: '$viewport');
      expect(geometry.normalizedAspectRatio.isFinite, isTrue);
      expect(
        geometry.normalizedAspectRatio,
        closeTo(expectedRatio, _tolerance),
        reason: '$viewport',
      );
      expect(geometry.usedFallbackRatio, isFalse, reason: '$viewport');
    }
  });
}

void _expectContainedAndCentered(
  ScannerPreviewGeometry geometry,
  Size viewport,
) {
  expect(geometry.previewRect.left, greaterThanOrEqualTo(-_tolerance));
  expect(geometry.previewRect.top, greaterThanOrEqualTo(-_tolerance));
  expect(
    geometry.previewRect.right,
    lessThanOrEqualTo(viewport.width + _tolerance),
  );
  expect(
    geometry.previewRect.bottom,
    lessThanOrEqualTo(viewport.height + _tolerance),
  );
  expect(
    geometry.previewRect.width,
    lessThanOrEqualTo(viewport.width + _tolerance),
  );
  expect(
    geometry.previewRect.height,
    lessThanOrEqualTo(viewport.height + _tolerance),
  );
  expect(
    (geometry.previewRect.width - viewport.width).abs() <= _tolerance ||
        (geometry.previewRect.height - viewport.height).abs() <= _tolerance,
    isTrue,
    reason: 'contain must use the largest scale that fits the viewport',
  );
  _expectCentered(geometry.previewRect, viewport);
  _expectRatio(geometry.previewRect, geometry.normalizedAspectRatio);
  expect(geometry.visibleRect, geometry.previewRect);
}

void _expectCentered(Rect rect, Size viewport) {
  final viewportCenter = viewport.center(Offset.zero);
  expect(rect.center.dx, closeTo(viewportCenter.dx, _tolerance));
  expect(rect.center.dy, closeTo(viewportCenter.dy, _tolerance));
}

void _expectRatio(Rect rect, double expectedRatio) {
  expect(rect.width / rect.height, closeTo(expectedRatio, _tolerance));
}
