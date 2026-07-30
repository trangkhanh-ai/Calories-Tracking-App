import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _appTitle = 'CalTrack — Theo dõi Calories';
const _appDescription = 'Theo dõi calo và dinh dưỡng mỗi ngày cùng CalTrack.';
const _androidApplicationId = 'com.example.flutter_application_1';
const _iosBundleIdentifier = 'com.example.flutterApplication1';
const _iosAppIconDirectory = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

const requiredImages = <String, ui.Size>{
  'web/favicon.png': ui.Size(32, 32),
  'web/icons/favicon-16.png': ui.Size(16, 16),
  'web/icons/favicon-32.png': ui.Size(32, 32),
  'web/icons/Icon-192.png': ui.Size(192, 192),
  'web/icons/Icon-512.png': ui.Size(512, 512),
  'web/icons/Icon-maskable-192.png': ui.Size(192, 192),
  'web/icons/Icon-maskable-512.png': ui.Size(512, 512),
  'web/icons/apple-touch-icon-180.png': ui.Size(180, 180),
  'assets/branding/caltrack-mark.png': ui.Size(256, 256),
  'assets/branding/caltrack-logo.png': ui.Size(512, 512),
  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': ui.Size(48, 48),
  'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': ui.Size(72, 72),
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': ui.Size(96, 96),
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': ui.Size(144, 144),
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': ui.Size(192, 192),
  'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png': ui.Size(
    432,
    432,
  ),
  '$_iosAppIconDirectory/Icon-App-1024x1024@1x.png': ui.Size(1024, 1024),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('branding PNG assets', () {
    test('all required images decode with the expected dimensions', () async {
      for (final entry in requiredImages.entries) {
        await _expectValidPng(entry.key, entry.value);
      }
    });

    test('every iOS AppIcon catalog image matches size times scale', () async {
      final catalogImages = _readIosAppIconCatalog();

      expect(catalogImages, isNotEmpty);
      for (final image in catalogImages) {
        await _expectValidPng(image.path, image.expectedSize);
      }
    });

    test('maskable artwork stays inside the central 66 percent', () async {
      for (final path in <String>[
        'web/icons/Icon-maskable-192.png',
        'web/icons/Icon-maskable-512.png',
      ]) {
        final image = await _expectValidPng(path, requiredImages[path]!);
        _expectMaskableSafePadding(image, path);
      }
    });

    test('the iOS 1024 marketing icon is fully opaque', () async {
      const path = '$_iosAppIconDirectory/Icon-App-1024x1024@1x.png';
      final image = await _expectValidPng(path, requiredImages[path]!);

      expect(
        _alphaValues(image.rgba).every((alpha) => alpha == 255),
        isTrue,
        reason: '$path must not contain transparent pixels',
      );
    });
  });

  group('web metadata', () {
    late String indexHtml;
    late String manifestJson;
    late Map<String, dynamic> manifest;

    setUpAll(() {
      indexHtml = _readText('web/index.html');
      manifestJson = _readText('web/manifest.json');
      manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    });

    test('uses the exact CalTrack document metadata', () {
      expect(indexHtml, contains('<title>$_appTitle</title>'));
      expect(
        indexHtml,
        contains('name="description" content="$_appDescription"'),
      );
      expect(indexHtml, contains('name="theme-color" content="#2DCA8C"'));
      expect(
        indexHtml,
        contains('apple-mobile-web-app-title" content="CalTrack"'),
      );
    });

    test('uses the exact CalTrack manifest metadata', () {
      expect(manifest['name'], _appTitle);
      expect(manifest['short_name'], 'CalTrack');
      expect(manifest['description'], _appDescription);
      expect(manifest['theme_color'], '#2DCA8C');
      expect(manifest['background_color'], '#F7F9FC');
      expect(manifest['orientation'], 'portrait-primary');
    });

    test('does not expose Flutter template defaults', () {
      for (final contents in [indexHtml, manifestJson]) {
        expect(contents, isNot(contains('flutter_application_1')));
        expect(contents, isNot(contains('A new Flutter project.')));
      }
    });

    test('declares complete web icon references that resolve', () {
      final links = _parseLinkTags(indexHtml);
      final referencedPaths = links
          .where((link) {
            final rel = link['rel']?.split(RegExp(r'\s+')) ?? const <String>[];
            return rel.contains('icon') ||
                rel.contains('apple-touch-icon') ||
                rel.contains('manifest');
          })
          .map((link) => link['href'])
          .whereType<String>()
          .toSet();

      for (final path in referencedPaths) {
        expect(
          File('web/${Uri.parse(path).path}').existsSync(),
          isTrue,
          reason: 'web/index.html references missing file: $path',
        );
      }

      expect(
        referencedPaths,
        containsAll(<String>[
          'icons/favicon-16.png',
          'icons/favicon-32.png',
          'icons/apple-touch-icon-180.png',
          'manifest.json',
        ]),
      );

      _expectMapEntry(links, <String, String>{
        'rel': 'icon',
        'type': 'image/png',
        'sizes': '16x16',
        'href': 'icons/favicon-16.png',
      });
      _expectMapEntry(links, <String, String>{
        'rel': 'icon',
        'type': 'image/png',
        'sizes': '32x32',
        'href': 'icons/favicon-32.png',
      });
      _expectMapEntry(links, <String, String>{
        'rel': 'apple-touch-icon',
        'sizes': '180x180',
        'href': 'icons/apple-touch-icon-180.png',
      });
    });

    test('declares complete manifest icon references that resolve', () {
      final icons = (manifest['icons'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final icon in icons) {
        final path = icon['src'] as String;
        expect(
          File('web/${Uri.parse(path).path}').existsSync(),
          isTrue,
          reason: 'web/manifest.json references missing file: $path',
        );
      }

      _expectMapEntry(icons, <String, dynamic>{
        'src': 'icons/Icon-192.png',
        'sizes': '192x192',
        'type': 'image/png',
        'purpose': 'any',
      });
      _expectMapEntry(icons, <String, dynamic>{
        'src': 'icons/Icon-512.png',
        'sizes': '512x512',
        'type': 'image/png',
        'purpose': 'any',
      });
      _expectMapEntry(icons, <String, dynamic>{
        'src': 'icons/Icon-maskable-192.png',
        'sizes': '192x192',
        'type': 'image/png',
        'purpose': 'maskable',
      });
      _expectMapEntry(icons, <String, dynamic>{
        'src': 'icons/Icon-maskable-512.png',
        'sizes': '512x512',
        'type': 'image/png',
        'purpose': 'maskable',
      });
    });
  });

  test('pubspec declares both in-app branding assets', () {
    final pubspec = _readText('pubspec.yaml');
    final assets = _readFlutterAssetEntries(pubspec);

    expect(
      assets,
      containsAll(<String>[
        'assets/branding/caltrack-mark.png',
        'assets/branding/caltrack-logo.png',
      ]),
    );
  });

  test('pubspec asset parser ignores comments and unrelated occurrences', () {
    const misleadingPubspec = '''
description: assets/branding/caltrack-logo.png
# flutter:
#   assets:
#     - assets/branding/caltrack-mark.png
flutter:
  configuration:
    assets:
      - assets/branding/caltrack-logo.png
  uses-material-design: true
''';

    expect(_readFlutterAssetEntries(misleadingPubspec), isEmpty);
  });

  group('Android metadata', () {
    test('uses CalTrack as the visible application label', () {
      final manifest = _readText('android/app/src/main/AndroidManifest.xml');

      expect(manifest, contains('android:label="CalTrack"'));
    });

    test('preserves the Android application ID', () {
      final gradle = _readText('android/app/build.gradle.kts');

      expect(gradle, contains('applicationId = "$_androidApplicationId"'));
    });
  });

  group('iOS metadata', () {
    test('uses CalTrack for the visible bundle names', () {
      final plist = _readText('ios/Runner/Info.plist');

      expect(_plistString(plist, 'CFBundleDisplayName'), 'CalTrack');
      expect(_plistString(plist, 'CFBundleName'), 'CalTrack');
    });

    test('preserves the iOS bundle identifier', () {
      final plist = _readText('ios/Runner/Info.plist');
      final project = _readText('ios/Runner.xcodeproj/project.pbxproj');
      final bundleIdentifiers = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
      ).allMatches(project).map((match) => match.group(1)!).toSet();

      expect(
        _plistString(plist, 'CFBundleIdentifier'),
        r'$(PRODUCT_BUNDLE_IDENTIFIER)',
      );
      expect(bundleIdentifiers, contains(_iosBundleIdentifier));
      expect(
        bundleIdentifiers.difference(<String>{
          _iosBundleIdentifier,
          '$_iosBundleIdentifier.RunnerTests',
        }),
        isEmpty,
      );
    });
  });
}

String _readText(String path) => File(path).readAsStringSync(encoding: utf8);

List<Map<String, String>> _parseLinkTags(String html) {
  final linkTags = RegExp(
    r'<link\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html);
  final attributePattern = RegExp(
    r'''([-\w:]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );

  return linkTags.map((tag) {
    return <String, String>{
      for (final attribute in attributePattern.allMatches(tag.group(0)!))
        attribute.group(1)!.toLowerCase():
            attribute.group(2) ?? attribute.group(3)!,
    };
  }).toList();
}

String? _plistString(String plist, String key) {
  return RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
  ).firstMatch(plist)?.group(1);
}

void _expectMapEntry<T>(List<Map<String, T>> values, Map<String, T> expected) {
  expect(
    values.any(
      (value) =>
          expected.entries.every((entry) => value[entry.key] == entry.value),
    ),
    isTrue,
    reason: 'Missing metadata entry: $expected',
  );
}

Future<_DecodedPng> _expectValidPng(String path, ui.Size expectedSize) async {
  expect(
    File(path).existsSync(),
    isTrue,
    reason: 'Required PNG is missing: $path',
  );

  final image = await _decodePng(path);
  expect(
    ui.Size(image.width.toDouble(), image.height.toDouble()),
    expectedSize,
    reason: '$path has unexpected pixel dimensions',
  );
  expect(
    _alphaValues(image.rgba).any((alpha) => alpha > 0),
    isTrue,
    reason: '$path is fully transparent',
  );
  return image;
}

Future<_DecodedPng> _decodePng(String path) async {
  final bytes = await File(path).readAsBytes();
  _expectPngSignature(bytes, path);
  final codec = await ui.instantiateImageCodec(bytes);

  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;

    try {
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        fail('Could not extract RGBA pixels from $path');
      }

      return _DecodedPng(
        width: image.width,
        height: image.height,
        rgba: Uint8List.fromList(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
        ),
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

List<_CatalogImageExpectation> _readIosAppIconCatalog() {
  final catalog =
      jsonDecode(_readText('$_iosAppIconDirectory/Contents.json'))
          as Map<String, dynamic>;
  final images = (catalog['images'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  return <_CatalogImageExpectation>[
    for (var index = 0; index < images.length; index++)
      _catalogImageExpectation(images[index], index),
  ];
}

_CatalogImageExpectation _catalogImageExpectation(
  Map<String, dynamic> image,
  int index,
) {
  final filename = image['filename'];
  if (filename is! String || filename.trim().isEmpty) {
    fail('AppIcon catalog image $index must have a non-empty filename');
  }

  return _CatalogImageExpectation(
    path: '$_iosAppIconDirectory/$filename',
    expectedSize: _catalogPixelSize(image, index),
  );
}

ui.Size _catalogPixelSize(Map<String, dynamic> image, int index) {
  final rawSize = image['size'];
  final rawScale = image['scale'];
  if (rawSize is! String || rawScale is! String) {
    fail('AppIcon catalog image $index must define string size and scale');
  }

  final sizeMatch = RegExp(
    r'^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)$',
  ).firstMatch(rawSize);
  final scaleMatch = RegExp(r'^(\d+(?:\.\d+)?)x$').firstMatch(rawScale);
  if (sizeMatch == null || scaleMatch == null) {
    fail('AppIcon catalog image $index has malformed size or scale');
  }

  final width =
      double.parse(sizeMatch.group(1)!) * double.parse(scaleMatch.group(1)!);
  final height =
      double.parse(sizeMatch.group(2)!) * double.parse(scaleMatch.group(1)!);

  expect(
    width,
    width.roundToDouble(),
    reason: 'AppIcon catalog image $index has non-integral pixel width',
  );
  expect(
    height,
    height.roundToDouble(),
    reason: 'AppIcon catalog image $index has non-integral pixel height',
  );
  return ui.Size(width, height);
}

void _expectPngSignature(Uint8List bytes, String path) {
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  expect(
    bytes.length,
    greaterThanOrEqualTo(signature.length),
    reason: '$path is too short to be a PNG',
  );
  expect(
    bytes.sublist(0, signature.length),
    orderedEquals(signature),
    reason: '$path does not have the strict PNG signature',
  );
}

List<String> _readFlutterAssetEntries(String pubspec) {
  final lines = const LineSplitter().convert(pubspec);
  int? flutterLine;

  for (var index = 0; index < lines.length; index++) {
    final content = _uncommentedYamlLine(lines[index]);
    if (content == null) {
      continue;
    }

    if (_indentation(content) == 0 && content.trim() == 'flutter:') {
      flutterLine = index;
      break;
    }
  }

  if (flutterLine == null) {
    fail('pubspec.yaml must define a top-level flutter section');
  }

  final flutterSection = <({int line, int indent, String content})>[];
  for (var index = flutterLine + 1; index < lines.length; index++) {
    final content = _uncommentedYamlLine(lines[index]);
    if (content == null) {
      continue;
    }

    final indent = _indentation(content);
    if (indent == 0) {
      break;
    }
    flutterSection.add((line: index, indent: indent, content: content));
  }

  if (flutterSection.isEmpty) {
    return const <String>[];
  }

  final directChildIndent = flutterSection
      .map((line) => line.indent)
      .reduce((left, right) => left < right ? left : right);
  int? assetsLine;
  for (final line in flutterSection) {
    if (line.indent == directChildIndent && line.content.trim() == 'assets:') {
      assetsLine = line.line;
      break;
    }
  }

  if (assetsLine == null) {
    return const <String>[];
  }

  final assets = <String>[];
  for (var index = assetsLine + 1; index < lines.length; index++) {
    final content = _uncommentedYamlLine(lines[index]);
    if (content == null) {
      continue;
    }

    final indent = _indentation(content);
    if (indent <= directChildIndent) {
      break;
    }

    final trimmed = content.trim();
    if (trimmed.startsWith('- ')) {
      assets.add(_unquoteYamlScalar(trimmed.substring(2).trim()));
    }
  }
  return assets;
}

String? _uncommentedYamlLine(String line) {
  final withoutComment = line.split('#').first.trimRight();
  return withoutComment.trim().isEmpty ? null : withoutComment;
}

int _indentation(String line) => line.length - line.trimLeft().length;

String _unquoteYamlScalar(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

Iterable<int> _alphaValues(Uint8List rgba) sync* {
  for (var offset = 3; offset < rgba.length; offset += 4) {
    yield rgba[offset];
  }
}

void _expectMaskableSafePadding(_DecodedPng image, String path) {
  int? minX;
  int? minY;
  int? maxX;
  int? maxY;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      final isBackground =
          image.rgba[offset] == 0xF7 &&
          image.rgba[offset + 1] == 0xF9 &&
          image.rgba[offset + 2] == 0xFC &&
          image.rgba[offset + 3] == 0xFF;
      if (isBackground) {
        continue;
      }

      minX = minX == null || x < minX ? x : minX;
      minY = minY == null || y < minY ? y : minY;
      maxX = maxX == null || x > maxX ? x : maxX;
      maxY = maxY == null || y > maxY ? y : maxY;
    }
  }

  expect(minX, isNotNull, reason: '$path contains no artwork');
  expect(minY, isNotNull, reason: '$path contains no artwork');
  expect(maxX, isNotNull, reason: '$path contains no artwork');
  expect(maxY, isNotNull, reason: '$path contains no artwork');

  const safeStart = 0.17;
  const safeEnd = 0.83;
  expect(minX! / image.width, greaterThanOrEqualTo(safeStart), reason: path);
  expect(minY! / image.height, greaterThanOrEqualTo(safeStart), reason: path);
  expect((maxX! + 1) / image.width, lessThanOrEqualTo(safeEnd), reason: path);
  expect((maxY! + 1) / image.height, lessThanOrEqualTo(safeEnd), reason: path);
}

final class _DecodedPng {
  const _DecodedPng({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

final class _CatalogImageExpectation {
  const _CatalogImageExpectation({
    required this.path,
    required this.expectedSize,
  });

  final String path;
  final ui.Size expectedSize;
}
