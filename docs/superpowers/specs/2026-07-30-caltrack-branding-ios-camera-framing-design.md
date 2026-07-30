# CalTrack Branding and iOS Camera Framing Design

## Status

Approved for implementation on 2026-07-30.

This design covers one focused pull request based on upstream `main` at
`ba0fa7db7d90a2f6475b7cc01391159f158237c4`.

## Goal

Replace remaining user-visible Flutter template branding with an original
CalTrack identity and prevent the mobile-web camera preview from cropping the
available field of view, especially on Safari iOS, without changing camera
capture behavior or backend behavior.

## Scope

The pull request may change only:

- CalTrack branding source and generated platform assets.
- Web, Android, and iOS user-visible application metadata.
- A reusable in-app brand widget and its placement on auth screens.
- Camera preview geometry and scan-overlay layout.
- Deterministic branding and camera-layout tests.
- Camera manual-validation documentation.

The pull request must not change:

- The Dart package name, Android application ID, Kotlin package, iOS bundle
  identifier, or signing configuration.
- Camera selection, hardware zoom, capture resolution, captured bytes,
  orientation correction, lifecycle serialization, permissions, retry,
  switching, rear-camera fallback, or gallery fallback.
- Gemini uploads, prompts, backend APIs, authentication, diary logic, database
  migrations, the USDA dataset, credentials, Render, Neon, CORS, or production
  deployment configuration.
- P1 work.

## Verified Baseline

- Local `main` and `origin/main` both resolve to `ba0fa7d`.
- The working tree was clean before the branch was created.
- The camera merge commit is present.
- `flutter pub get --enforce-lockfile` succeeds.
- The existing Flutter suite passes with 133 tests.

## Verified Root Causes

### Branding

The Flutter template identity remains in platform metadata and generated
launcher assets even though parts of the Dart UI already display CalTrack.

- `web/index.html` still contains `flutter_application_1` and
  `A new Flutter project.`.
- `web/manifest.json` still contains the template name, description, and
  Flutter-blue theme colors.
- Web, Android, and iOS launcher assets are the stock Flutter mark.
- Android and iOS visible application names still use template values.
- Login and registration screens contain no CalTrack logo.
- `pubspec.yaml` does not declare an application branding asset.

The internal package and application identifiers also contain template names,
but they are not user-visible and changing them would expand risk and break
existing import and upgrade identity contracts. They remain unchanged.

### Camera Preview

The apparent zoom is preview-layout cropping, not hardware or capture zoom.

`_CameraSurface` currently derives a full-screen cover size from
`MediaQuery`, then places the preview in an `OverflowBox`. On tall mobile
viewports this enlarges the camera image past the horizontal bounds so the
left and right sides are intentionally clipped. A 4:3 camera source on a
390 by 844 portrait viewport can display at roughly 633 by 844, leaving only
about 62 percent of the source width visible.

The current orientation handling also blindly reciprocates the reported ratio
for portrait layout. A camera that already reports a portrait-oriented ratio
can therefore be normalized twice. The scan overlay is independently centered
over the whole viewport, so it would not align with a letterboxed contained
preview.

Capture continues to call `takePicture()` directly and returns the full
`XFile`; the captured image is not cropped by the current preview widget.

## Selected Brand Design

The approved mark is option A: a rounded plate represented by a strong
mint-colored letter C, combined with a dark-slate check mark and a restrained
peach calorie-progress dot.

### Visual Rules

- Primary mint: `#2DCA8C`.
- Dark mint: `#1F9D6B`.
- Dark slate: `#1E293B`.
- White: `#FFFFFF`.
- Optional peach detail: `#FF9B71`.
- No gradients in launcher or favicon artwork.
- No text inside the mark.
- The silhouette must remain recognizable at 16 by 16 pixels.
- Important artwork must remain within the maskable safe region.
- The same source geometry must drive web, in-app, Android, and iOS assets.

Option B, a plate and leaf, was rejected because the health-leaf motif is less
distinctive. Option C, a calorie progress ring, was rejected because it has a
weaker food association.

## Branding Architecture

### Source and Generated Assets

The editable source of truth will be:

`docs/assets/branding/caltrack-mark.svg`

Generated PNG assets will be committed so production builds require no asset
generation tools.

Required outputs:

- Web favicon and 16, 32, 192, 512, maskable 192, maskable 512, and Apple
  touch 180 icons.
- In-app logo and standalone mark under `assets/branding/`.
- Android launcher icons in all existing density folders.
- Android adaptive foreground and background resources when supported by the
  current project structure.
- Every image required by the existing iOS AppIcon catalog.

Raster generation must preserve aspect ratio, safe padding, transparency rules,
and the expected platform dimensions. The 1024-pixel iOS icon must remain
opaque.

### Metadata

Web metadata will use:

- Title: `CalTrack — Theo dõi Calories`.
- Name: `CalTrack — Theo dõi Calories`.
- Short name: `CalTrack`.
- A concise Vietnamese calorie and nutrition tracking description.
- Theme color: `#2DCA8C`.
- Background color matching the application background.
- Portrait-primary orientation.
- Explicit favicon sizes/types and the new Apple touch icon.

Android and iOS visible labels will become `CalTrack`. Identifiers and signing
settings will not change.

### In-App Branding

A focused reusable `AppBrandLogo` widget will:

- Render committed PNG assets without an SVG runtime dependency.
- Provide a Vietnamese semantic label naming CalTrack.
- Accept compact sizing suitable for auth screens.
- Scale without clipping or pixelation.
- Avoid layout overflow on an iPhone 7-sized viewport.

The widget will appear above the login and registration headings. Existing
fields, actions, navigation, and overall auth-card visual language remain
unchanged.

## Selected Camera Policy

The approved policy is option A, a platform-capability hybrid:

- Web and mobile web use `contain` to preserve the complete available camera
  field of view.
- Native platforms retain the current `cover` presentation.
- No Safari user-agent sniffing is permitted.

Contain everywhere was rejected because it would unnecessarily change native
Android framing before a native cropping problem is demonstrated.

## Camera Geometry Architecture

### Pure Geometry Unit

A small pure unit, tentatively named `ScannerPreviewGeometry`, will accept:

- The `LayoutBuilder` viewport size.
- The controller-reported raw aspect ratio, defined as width divided by height.
- The requested fit policy, `contain` or `cover`.

It will return the centered preview rectangle and the visible overlay
rectangle.

The unit will:

- Reject zero, negative, NaN, and infinite ratios.
- Use a safe 4:3 camera fallback before orientation normalization.
- Normalize once according to viewport orientation.
- Resolve raw 4:3 and raw 3:4 to equivalent portrait geometry.
- Resolve raw 4:3 and raw 3:4 to equivalent landscape geometry.
- Preserve the normalized ratio.
- Guarantee that contained width and height do not exceed the viewport.
- Keep contained and covered layouts centered.

Flutter's standard fit primitives should be preferred over duplicated sizing
branches. The helper must not depend on camera plugins, browser APIs, widget
state, or `MediaQuery`.

### Preview Composition

`_CameraSurface` will use `LayoutBuilder` constraints instead of the full
`MediaQuery` size.

For web contain mode:

1. Compute a centered rectangle fully inside the available constraints.
2. Place the camera preview inside that exact rectangle.
3. Avoid `OverflowBox` on this path.
4. Clip only for platform-renderer safety, not intentional field-of-view crop.
5. Place `ScanFrameOverlay` inside the same visible rectangle.

For native cover mode:

1. Compute the explicit cover rectangle.
2. Preserve the current full-bleed visual behavior.
3. Clip the oversized preview at the viewport boundary.
4. Keep the overlay aligned to the visible viewport portion.

Camera controls and navigation remain positioned relative to the screen, not
the camera content rectangle, so letterboxing cannot hide controls.

### Overlay

`ScanFrameOverlay` will size its square from the smaller of available width
and height rather than width alone. This prevents landscape overflow and keeps
the scan frame within the visible preview rectangle. Its animation and colors
remain unchanged.

### Camera Controller Contract

The current injectable controller boundary remains preferred. It will change
only if the implementation proves that the displayed aspect ratio cannot be
expressed reliably with the existing width-over-height property. Under no
circumstances will widgets receive the underlying plugin controller.

## Data and Behavior Flow

The camera session continues to initialize, select, switch, suspend, resume,
capture, and dispose exactly as before. The only new data flow is:

1. The screen reads controller aspect ratio and platform capability.
2. The pure geometry unit normalizes the ratio and calculates layout.
3. The preview and overlay consume that calculated rectangle.
4. Capture still bypasses preview geometry and returns plugin image bytes.
5. Gemini upload still consumes the captured or selected `XFile` unchanged.

## Error Handling

- Invalid ratios fall back deterministically without throwing.
- Loading, switching, permission, retry, unavailable, rear-camera fallback,
  and gallery fallback states retain their existing copy and actions.
- Geometry calculation creates no new asynchronous state and cannot create a
  camera session during rebuilds.
- Letterboxing uses the existing neutral black scanner background.

## Test Strategy

Implementation follows red-green-refactor. Production behavior is not added
until the corresponding failing test has been observed.

### Branding Tests

Tests will verify:

- Every required icon exists and decodes.
- PNG dimensions match their required sizes.
- Icons are non-empty and not fully transparent.
- Maskable artwork respects central safe padding.
- The iOS 1024 icon is opaque.
- Web metadata and manifest use CalTrack values.
- User-facing web metadata contains no Flutter template name or description.
- Every favicon and manifest reference resolves to an existing file.
- `pubspec.yaml` declares the in-app branding assets.
- Login and registration render `AppBrandLogo` without overflow at compact
  viewport sizes.

### Geometry Unit Tests

Tests will cover:

- Portrait 375 by 667 with raw 4:3 and 3:4.
- Portrait 390 by 844 with raw 16:9 and 9:16.
- Landscape 667 by 375 with raw 4:3 and 3:4.
- Zero, negative, NaN, and infinite ratios.
- Centering, ratio preservation, equivalent normalization, contained bounds,
  and cover behavior.

### Widget and Regression Tests

Tests will verify:

- Web uses the contain path and does not use the old overflowing shell.
- Native uses the explicit cover path.
- Overlay bounds equal the visible web preview bounds.
- Loading, retry, unavailable, switching, capture, lifecycle, and fallback
  behavior remain unchanged.
- Layout rebuilds do not create duplicate camera sessions.
- Existing camera service and image-source tests are retained.

## Automated Validation

Final validation includes:

- `flutter pub get --enforce-lockfile`.
- No unintended `pubspec.lock` change.
- `flutter analyze`.
- Targeted branding and camera tests.
- Full `flutter test --reporter compact`.
- Flutter web release build using a non-secret example backend origin.
- Flutter Android release build using a non-secret example backend origin.
- Tracked-secret scanner and scanner regression tests.
- Web manifest JSON validation.
- Vercel ignore and build-script validation.
- `git diff --check`.

Generated build outputs, APK files, local audit files, credentials, and
environment files must not enter the diff.

## Manual Validation

Automated tests cannot prove Safari camera behavior. The pull request will
include a concise checklist for:

- Direct Safari on a physical iPhone 7.
- Android Chrome and Samsung Internet mobile web.
- Installed PWA where available.
- Android APK.

The checklist covers field of view, unexpected crop, distortion, intentional
letterboxing, overlay alignment, five camera switches, capture and Gemini,
return and second capture, background/resume, retry, rear-camera fallback,
gallery fallback, launcher icon, and app label.

Results remain `BLOCKED` or `Manual pending` until factual device evidence is
provided. The pull request must not claim the Safari issue is fixed from widget
tests alone.

## Git and Delivery

Work occurs on `fix/branding-and-ios-camera-framing` with logical commits:

1. `feat(branding): add CalTrack application identity`
2. `fix(scanner): preserve full camera field of view on mobile web`
3. `test(scanner): cover preview aspect-ratio layout`

The branch may be pushed normally and used to open a pull request against
upstream `main`. It must not be force-pushed, pushed directly to `main`, merged,
or manually deployed.

The pull request will report verified root causes, asset previews, the web
contain versus native cover policy, exact changed files, automated results,
manual-validation status, known browser limitations, and explicit confirmation
that capture, Gemini, backend, database, and security behavior did not change.

After a future upstream merge, the repository owner must synchronize
`Ductri2006/Calories-Tracking-App` and allow the existing Vercel Git integration
to deploy that synchronized commit. This work will not create a deployment
trigger commit without explicit owner authorization.

## Acceptance Criteria

- All user-visible platform branding in scope uses CalTrack.
- The selected mark is original, legible at favicon size, and safe for maskable
  crops.
- Auth screens display the reusable brand widget without compact-viewport
  overflow.
- Web preview uses a centered contained camera rectangle with no intentional
  edge crop from the Flutter layout.
- Native preview retains explicit cover behavior.
- The scan overlay remains inside the visible camera region.
- Camera capture and Gemini behavior are unchanged.
- Automated validation passes.
- The pull request remains unmerged until required physical-device checks pass.
