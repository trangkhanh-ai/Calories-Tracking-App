# CalTrack Branding and iOS Camera Framing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task with review checkpoints. Each worker owns the files listed in its task and must not revert other agents' edits.

**Goal:** Replace user-visible Flutter template branding with CalTrack and make the mobile-web camera preview preserve its full field of view while keeping native camera behavior unchanged.

**Architecture:** Keep all package and store identifiers unchanged. Generate committed platform assets from one editable SVG source, expose a small PNG-backed AppBrandLogo widget to auth screens, and isolate camera layout in a pure aspect-ratio geometry unit plus a viewport widget. Web uses contain; native uses cover.

**Tech Stack:** Flutter 3.44.1, Dart 3.12, Flutter widget tests, Python 3.11 + Pillow for one-time asset generation, Android XML resources, iOS asset catalogs, Vercel static metadata.

---

## Task 1: Add Failing Branding Asset and Metadata Tests

**Owner:** Branding worker

**Files:**
- Create: test/branding_assets_test.dart
- Read: web/index.html, web/manifest.json, pubspec.yaml, platform resource trees

- [ ] **Step 1: Add PNG inspection helpers and required asset cases**

Create a test that uses dart:io and dart:ui to read files from the repository root. The helper must decode PNG bytes with instantiateImageCodec, return width, height, and raw RGBA bytes, and assert that at least one pixel has alpha greater than zero. Define required files and dimensions explicitly:

~~~dart
const requiredImages = <String, Size>{
  'web/favicon.png': Size(32, 32),
  'web/icons/favicon-16.png': Size(16, 16),
  'web/icons/favicon-32.png': Size(32, 32),
  'web/icons/Icon-192.png': Size(192, 192),
  'web/icons/Icon-512.png': Size(512, 512),
  'web/icons/Icon-maskable-192.png': Size(192, 192),
  'web/icons/Icon-maskable-512.png': Size(512, 512),
  'web/icons/apple-touch-icon-180.png': Size(180, 180),
  'assets/branding/caltrack-mark.png': Size(256, 256),
  'assets/branding/caltrack-logo.png': Size(512, 512),
  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': Size(48, 48),
  'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': Size(72, 72),
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': Size(96, 96),
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': Size(144, 144),
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': Size(192, 192),
  'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png':
      Size(432, 432),
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
      Size(1024, 1024),
};
~~~

Add the remaining iOS files by parsing Contents.json and deriving pixel
dimensions from size * scale. Do not hard-code a list that can diverge from
the catalog.

- [ ] **Step 2: Add metadata assertions**

Read the HTML and JSON as UTF-8 and assert:

~~~dart
expect(index, contains('<title>CalTrack — Theo dõi Calories</title>'));
expect(index, contains('name="theme-color" content="#2DCA8C"'));
expect(index, contains('apple-mobile-web-app-title" content="CalTrack"'));
expect(manifest['name'], 'CalTrack — Theo dõi Calories');
expect(manifest['short_name'], 'CalTrack');
expect(manifest['theme_color'], '#2DCA8C');
expect(manifest['orientation'], 'portrait-primary');
expect(index, isNot(contains('flutter_application_1')));
expect(index, isNot(contains('A new Flutter project.')));
expect(manifestJson, isNot(contains('flutter_application_1')));
expect(manifestJson, isNot(contains('A new Flutter project.')));
~~~

Assert every favicon, Apple touch icon, and manifest icon reference points to
an existing file. Assert pubspec.yaml contains the two branding asset paths.

- [ ] **Step 3: Add maskable safe-padding and opacity assertions**

For each maskable icon, sample RGBA pixels and compute the bounding box of
pixels that differ from the declared #F7F9FC background. Require that the
non-background artwork is fully inside the central 66 percent safe region. For
the iOS 1024 icon, require every alpha byte to equal 255. Keep the test
deterministic and avoid image snapshots.

- [ ] **Step 4: Run the focused test and verify RED**

Run:

~~~powershell
flutter test test/branding_assets_test.dart --reporter compact
~~~

Expected: failure because the required files and CalTrack metadata do not yet
exist.

- [ ] **Step 5: Commit the failing test**

~~~powershell
git add test/branding_assets_test.dart
git commit -m "test(branding): define CalTrack asset contracts"
~~~

## Task 2: Generate CalTrack Assets and Update Platform Branding

**Owner:** Branding worker

**Files:**
- Create: docs/assets/branding/caltrack-mark.svg
- Create: scripts/generate_caltrack_brand_assets.py
- Create: assets/branding/caltrack-mark.png
- Create: assets/branding/caltrack-logo.png
- Create: web/icons/favicon-16.png, web/icons/favicon-32.png, web/icons/apple-touch-icon-180.png
- Modify: web/favicon.png and web/icons/*
- Modify: android/app/src/main/res/mipmap-*/ic_launcher.png
- Create: android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png
- Create: android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
- Create: android/app/src/main/res/values/colors.xml
- Modify: all PNG files declared by ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json
- Modify: web/index.html, web/manifest.json, android/app/src/main/AndroidManifest.xml, ios/Runner/Info.plist, pubspec.yaml

- [ ] **Step 1: Write the editable SVG source**

Create a 1024 by 1024 SVG with no external references. Use the approved mark:

~~~xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <title>CalTrack mark</title>
  <path d="M 752 267 A 330 330 0 1 0 752 757"
        fill="none" stroke="#2DCA8C" stroke-width="148"
        stroke-linecap="round"/>
  <path d="M 410 520 L 494 604 L 690 402"
        fill="none" stroke="#1E293B" stroke-width="92"
        stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="788" cy="760" r="64" fill="#FF9B71"/>
</svg>
~~~

Keep the artwork inside the SVG safe margin. Do not include text, gradients,
emoji, third-party marks, or external fonts.

- [ ] **Step 2: Implement deterministic generation from the SVG**

Write scripts/generate_caltrack_brand_assets.py using Pillow and a local
Chrome headless renderer. The script must:

1. Locate Chrome from CHROME_PATH or standard Windows, macOS, and Linux paths.
2. Write a temporary HTML wrapper with zero margins and the SVG as a full-size
   image.
3. Render a transparent 1024-pixel mark and an opaque #F7F9FC 1024-pixel
   app-icon master using --headless --screenshot --force-device-scale-factor=1.
4. Resize masters with Pillow LANCZOS to exact output dimensions.
5. Scale the mark to 60 percent of the canvas for maskable icons and adaptive
   foreground assets.
6. Write only the listed committed output paths.

The script must not run from Flutter/Vercel builds. Add a short usage section
at the top of the script documenting:

~~~powershell
python scripts/generate_caltrack_brand_assets.py
~~~

- [ ] **Step 3: Generate and inspect all raster assets**

Run the generator, then inspect every output with Pillow metadata and the
focused branding test. Expected output includes exact dimensions, non-empty
pixels, maskable safe padding, and an opaque iOS master.

- [ ] **Step 4: Add Android adaptive icon resources**

Create colors.xml with ic_launcher_background set to #F7F9FC and
mipmap-anydpi-v26/ic_launcher.xml:

~~~xml
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
~~~

Keep the existing package/application ID and add only android:label="CalTrack"
to the application manifest.

- [ ] **Step 5: Update iOS AppIcon and visible metadata**

Replace every PNG referenced by the existing AppIcon catalog while preserving
all filenames and Contents.json entries. Change only CFBundleDisplayName and
CFBundleName to CalTrack; preserve bundle ID, usage descriptions, orientations,
and signing settings.

- [ ] **Step 6: Update web metadata and asset declaration**

Set the exact HTML title to CalTrack — Theo dõi Calories, use a meaningful
Vietnamese description, add the theme-color meta tag, set the Apple title to
CalTrack, link 16 and 32 pixel favicons plus the 180 pixel Apple touch icon,
and preserve the Flutter bootstrap script unchanged. Set manifest name,
short name, description, background color #F7F9FC, theme color #2DCA8C,
portrait orientation, regular/maskable icon purposes. Add:

~~~yaml
flutter:
  assets:
    - assets/branding/caltrack-mark.png
    - assets/branding/caltrack-logo.png
~~~

- [ ] **Step 7: Run the branding test and verify GREEN**

Run:

~~~powershell
flutter test test/branding_assets_test.dart --reporter compact
~~~

Expected: PASS.

- [ ] **Step 8: Commit platform branding**

~~~powershell
git add docs/assets/branding scripts/generate_caltrack_brand_assets.py assets/branding web android/app/src/main/res android/app/src/main/AndroidManifest.xml ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Info.plist web/index.html web/manifest.json pubspec.yaml
git diff --cached --check
git commit -m "feat(branding): add CalTrack application identity"
~~~

## Task 3: Add the Reusable In-App Brand Widget

**Owner:** Auth branding worker

**Files:**
- Create: lib/shared/widgets/app_brand_logo.dart
- Create: test/app_brand_logo_test.dart
- Modify: lib/features/auth/screens/login_screen.dart
- Modify: lib/features/auth/screens/register_screen.dart

- [ ] **Step 1: Write the failing widget tests**

Create tests that pump LoginScreen and RegisterScreen inside the existing
provider/router test setup, find the semantic label CalTrack logo, and assert
both headings and their existing fields remain present. Set the test view to
375x667 at device pixel ratio 1 and call addTearDown to restore the default
view. Assert tester.takeException() is null after settling.

Run:

~~~powershell
flutter test test/app_brand_logo_test.dart --reporter compact
~~~

Expected: failure because AppBrandLogo is not defined or rendered.

- [ ] **Step 2: Implement AppBrandLogo**

Create a compact widget with this contract:

~~~dart
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CalTrack logo',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/caltrack-mark.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: 8),
          Text(
            'CalTrack',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.onBackground,
            ),
          ),
        ],
      ),
    );
  }
}
~~~

Import AppTheme; do not add an SVG runtime package.

- [ ] **Step 3: Place the widget without redesigning auth**

In both auth cards, insert const AppBrandLogo(size: 64) immediately before the
existing heading, reduce only the following heading gap from 32 to 24, and
leave all fields, buttons, routes, and existing copy unchanged.

- [ ] **Step 4: Run focused tests and the existing smoke test**

~~~powershell
flutter test test/app_brand_logo_test.dart test/widget_test.dart --reporter compact
~~~

Expected: PASS with no overflow exceptions.

- [ ] **Step 5: Commit auth branding**

~~~powershell
git add lib/shared/widgets/app_brand_logo.dart lib/features/auth/screens/login_screen.dart lib/features/auth/screens/register_screen.dart test/app_brand_logo_test.dart
git diff --cached --check
git commit -m "feat(branding): add CalTrack auth logo"
~~~

## Task 4: Add Failing Camera Geometry Unit Tests

**Owner:** Camera worker

**Files:**
- Create: test/scanner_preview_geometry_test.dart

- [ ] **Step 1: Define the pure public API in the test**

The test must use a public enum and value type so no widget internals are
needed:

~~~dart
enum ScannerPreviewFit { contain, cover }

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
  );
}
~~~

- [ ] **Step 2: Add RED cases for portrait, landscape, and invalid ratios**

Cover these exact inputs and assertions:

~~~dart
final portrait = Size(375, 667);
final tall = Size(390, 844);
final landscape = Size(667, 375);

test('contain keeps 4:3 and 3:4 equivalent in portrait', () {
  final wide = ScannerPreviewGeometry.calculate(
    portrait,
    4 / 3,
    ScannerPreviewFit.contain,
  );
  final tallSource = ScannerPreviewGeometry.calculate(
    portrait,
    3 / 4,
    ScannerPreviewFit.contain,
  );
  expect(wide.previewRect, tallSource.previewRect);
  expect(wide.normalizedAspectRatio, closeTo(3 / 4, 0.0001));
});

test('contain keeps 16:9 and 9:16 equivalent in portrait', () {
  final wide = ScannerPreviewGeometry.calculate(
    tall,
    16 / 9,
    ScannerPreviewFit.contain,
  );
  final tallSource = ScannerPreviewGeometry.calculate(
    tall,
    9 / 16,
    ScannerPreviewFit.contain,
  );
  expect(wide.previewRect, tallSource.previewRect);
  expect(wide.normalizedAspectRatio, closeTo(9 / 16, 0.0001));
});

test('landscape normalization is equivalent for 4:3 and 3:4', () {
  final wide = ScannerPreviewGeometry.calculate(
    landscape,
    4 / 3,
    ScannerPreviewFit.contain,
  );
  final tallSource = ScannerPreviewGeometry.calculate(
    landscape,
    3 / 4,
    ScannerPreviewFit.contain,
  );
  expect(wide.previewRect, tallSource.previewRect);
  expect(wide.normalizedAspectRatio, closeTo(4 / 3, 0.0001));
});

test('contain never exceeds viewport and stays centered', () {
  final geometry = ScannerPreviewGeometry.calculate(
    tall,
    4 / 3,
    ScannerPreviewFit.contain,
  );
  expect(geometry.previewRect.width, lessThanOrEqualTo(tall.width));
  expect(geometry.previewRect.height, lessThanOrEqualTo(tall.height));
  expect(geometry.previewRect.center, tall.center(Offset.zero));
  expect(
    geometry.previewRect.width / geometry.previewRect.height,
    closeTo(geometry.normalizedAspectRatio, 0.0001),
  );
});

test('cover preserves ratio and may exceed one viewport dimension', () {
  final geometry = ScannerPreviewGeometry.calculate(
    tall,
    4 / 3,
    ScannerPreviewFit.cover,
  );
  expect(
    geometry.previewRect.width > tall.width ||
        geometry.previewRect.height > tall.height,
    isTrue,
  );
  expect(geometry.visibleRect, Offset.zero & tall);
  expect(
    geometry.previewRect.width / geometry.previewRect.height,
    closeTo(geometry.normalizedAspectRatio, 0.0001),
  );
});

test('zero, negative, NaN and infinity use safe fallback', () {
  for (final invalid in <double>[0, -1, double.nan, double.infinity]) {
    final geometry = ScannerPreviewGeometry.calculate(
      portrait,
      invalid,
      ScannerPreviewFit.contain,
    );
    expect(geometry.usedFallbackRatio, isTrue);
    expect(geometry.normalizedAspectRatio, closeTo(3 / 4, 0.0001));
    expect(geometry.previewRect.isFinite, isTrue);
  }
});
~~~

Use concrete assertions for width/height bounds, center coordinates, ratio
error tolerance closeTo(expected, 0.0001), and usedFallbackRatio.

- [ ] **Step 3: Run the geometry tests and verify RED**

~~~powershell
flutter test test/scanner_preview_geometry_test.dart --reporter compact
~~~

Expected: failure because the geometry unit does not exist.

- [ ] **Step 4: Commit the failing geometry tests**

~~~powershell
git add test/scanner_preview_geometry_test.dart
git commit -m "test(scanner): define preview geometry contracts"
~~~

## Task 5: Implement Pure Camera Geometry

**Owner:** Camera worker

**Files:**
- Create: lib/features/scanner/widgets/scanner_preview_geometry.dart

- [ ] **Step 1: Normalize the raw ratio exactly once**

Implement a private normalization helper:

~~~dart
double _normalizeAspectRatio(Size viewport, double raw) {
  final valid = raw.isFinite && raw > 0 ? raw : 4 / 3;
  final portrait = viewport.height > viewport.width;
  if (portrait) return valid > 1 ? 1 / valid : valid;
  return valid < 1 ? 1 / valid : valid;
}
~~~

For square constraints, treat the layout as landscape. Set usedFallbackRatio
when the original value is invalid.

- [ ] **Step 2: Calculate fit sizes without stretching**

Use a source size Size(normalizedRatio, 1) and scale it by min for contain or
max for cover:

~~~dart
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
final visibleRect = fit == ScannerPreviewFit.contain
    ? previewRect
    : Offset.zero & viewport;
~~~

Handle non-positive viewport dimensions by returning zero rectangles and the
safe normalized ratio without throwing. Keep the method free of camera plugin
imports.

- [ ] **Step 3: Run the geometry tests and verify GREEN**

~~~powershell
flutter test test/scanner_preview_geometry_test.dart --reporter compact
~~~

Expected: PASS.

## Task 6: Integrate Geometry and Align the Scan Overlay

**Owner:** Camera worker

**Files:**
- Create: lib/features/scanner/widgets/scanner_camera_viewport.dart
- Modify: lib/features/scanner/screens/camera_scanner_screen.dart
- Modify: lib/features/scanner/widgets/scan_frame_overlay.dart
- Modify: test/camera_scanner_screen_test.dart

- [ ] **Step 1: Add RED widget assertions for web and native policies**

Extend the existing fake controller with a mutable aspectRatio and the fake
platform's existing web flag. Add tests that pump a 390 by 844 viewport and
assert:

- Web contains a keyed camera-preview-geometry whose rectangle is fully inside
  the viewport.
- Web has no OverflowBox in the ready preview subtree.
- Native uses the cover policy and keeps the ready shell functional.
- The overlay is keyed and has the same size/center as the visible web camera
  rectangle.
- A rebuild of the widget tree leaves exactly one non-disposed controller.

Run the targeted test and observe RED before changing production widgets.

- [ ] **Step 2: Implement ScannerCameraViewport**

Create a widget with:

~~~dart
class ScannerCameraViewport extends StatelessWidget {
  const ScannerCameraViewport({
    super.key,
    required this.controller,
    required this.isWeb,
  });

  final ScannerCameraController controller;
  final bool isWeb;
}
~~~

Inside LayoutBuilder, call ScannerPreviewGeometry.calculate with
constraints.biggest, controller.aspectRatio, and
isWeb ? ScannerPreviewFit.contain : ScannerPreviewFit.cover. Build a
Stack(clipBehavior: Clip.hardEdge) with keyed Positioned.fromRect children:

~~~dart
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
~~~

Use the controller's buildPreview() as the child and do not expose the plugin
controller. The contain rectangle must be tight and centered; the cover
rectangle may extend beyond the viewport and is clipped by the stack.

- [ ] **Step 3: Replace only the ready preview branch**

In _CameraSurface, retain existing loading and failure branches and replace
the MediaQuery plus OverflowBox calculation with
ScannerCameraViewport(controller: controller, isWeb: isWeb). Keep the existing
camera-preview-shell key. Do not change session initialization, capture,
retry, switch, or fallback callbacks.

Keep the full-screen overlay for loading/switching states only; the ready
viewport owns its aligned overlay so it is not painted twice.

- [ ] **Step 4: Clamp the scan frame to the visible rectangle**

Change ScanFrameOverlay to compute:

~~~dart
final size = math.min(constraints.maxWidth, constraints.maxHeight) * 0.72;
~~~

Keep the existing animation, dimming painter, corner painter, and primary color.
The widget must remain centered inside the rectangle supplied by the viewport.

- [ ] **Step 5: Run camera tests and verify GREEN**

~~~powershell
flutter test test/scanner_preview_geometry_test.dart test/camera_scanner_screen_test.dart test/scanner_camera_service_test.dart test/scanner_image_source_test.dart --reporter compact
~~~

Expected: PASS with the original lifecycle, switching, capture, and fallback
tests retained.

- [ ] **Step 6: Commit camera behavior**

~~~powershell
git add lib/features/scanner/widgets/scanner_preview_geometry.dart lib/features/scanner/widgets/scanner_camera_viewport.dart lib/features/scanner/screens/camera_scanner_screen.dart lib/features/scanner/widgets/scan_frame_overlay.dart test/scanner_preview_geometry_test.dart test/camera_scanner_screen_test.dart
git diff --cached --check
git commit -m "fix(scanner): preserve full camera field of view on mobile web"
~~~

## Task 7: Update Manual Camera Documentation

**Owner:** Root agent after camera worker review

**Files:**
- Modify: docs/CAMERA_MANUAL_TEST_PLAN.md

- [ ] **Step 1: Add framing-specific manual cases**

Add explicit checks for Safari iPhone 7 and Android mobile web:

- Compare visible field of view before and after the change.
- Confirm no unexpected left/right crop in portrait.
- Confirm letterboxing is intentional and does not cover controls.
- Confirm the scan frame sits inside the visible camera rectangle.
- Check portrait and landscape where supported.
- Record whether analyzed capture framing remains acceptable.

- [ ] **Step 2: Keep evidence status factual**

Retain Manual pending until a physical tester records device, OS, browser/app
version, result, and notes. Do not add PASS claims based on local widget tests.

- [ ] **Step 3: Commit documentation**

~~~powershell
git add docs/CAMERA_MANUAL_TEST_PLAN.md
git diff --cached --check
git commit -m "docs(scanner): add mobile preview framing checks"
~~~

## Task 8: Integrated Validation and Diff Review

**Owner:** Root agent

**Files:**
- All changed files from Tasks 1 through 7

- [ ] **Step 1: Restore the locked dependency state**

~~~powershell
flutter pub get --enforce-lockfile
git diff --exit-code -- pubspec.lock
~~~

Expected: no lockfile drift.

- [ ] **Step 2: Run static analysis and all Flutter tests**

~~~powershell
flutter analyze
flutter test --reporter compact
~~~

Expected: no analyzer issues and all tests pass.

- [ ] **Step 3: Build release artifacts with a non-secret backend origin**

~~~powershell
flutter build web --release --base-href / --dart-define=BACKEND_BASE_URL=https://example.onrender.com
flutter build apk --release --dart-define=BACKEND_BASE_URL=https://example.onrender.com
~~~

Expected: both builds succeed. Do not add build/ or APK outputs to Git.

- [ ] **Step 4: Validate metadata, scripts, and secrets**

~~~powershell
python -m json.tool web/manifest.json > $null
bash -n scripts/vercel-build.sh
python scripts/validate_vercelignore.py
python scripts/tests/test_scan_tracked_secrets.py
python scripts/scan_tracked_secrets.py
git diff --check
~~~

Expected: all commands exit zero and the secret scanner reports no findings.

- [ ] **Step 5: Inspect the complete diff for scope violations**

~~~powershell
git status --short
git diff main...HEAD --stat
git diff main...HEAD --name-only
~~~

Reject any build output, environment file, secret, backend/database change,
USDA change, package-ID rename, unrelated formatting, or generated local audit
file. Confirm changed paths are limited to branding assets/metadata, auth-logo
presentation, camera geometry, tests, and manual documentation.

- [ ] **Step 6: Review commits and request code review**

~~~powershell
git log --oneline --decorate main..HEAD
git diff main...HEAD --check
~~~

Request an independent review focused on camera regression, platform icon
validity, accessibility, and scope. Resolve findings before publishing.

## Task 9: Push and Open the Pull Request Without Merge or Deployment

**Owner:** Root agent

- [ ] **Step 1: Push the branch normally**

~~~powershell
git push -u origin fix/branding-and-ios-camera-framing
~~~

Do not force-push and do not push to main.

- [ ] **Step 2: Open the pull request**

Use base main and title:

fix(ui): add CalTrack branding and correct mobile-web camera framing

The body must include verified root causes, asset previews, web-contain versus
native-cover explanation, exact changed files, automated results, manual test
status, known browser limitations, and explicit statements that capture,
Gemini, backend, database, credentials, and security behavior did not change.

- [ ] **Step 3: Stop before merge/deploy**

Do not merge the pull request, manually deploy Vercel/Render, create a
deployment-trigger commit, force-push, or start P1. Report physical-device
manual checks as BLOCKED or Manual pending until factual owner evidence is
provided.

## Verification Checkpoints

After each worker returns, the root agent will inspect its summary, run focused
tests, check git diff --check, and verify that no other worker's files were
reverted. Before the final report, the root agent will run all Task 8 commands
and review the full diff against main.
