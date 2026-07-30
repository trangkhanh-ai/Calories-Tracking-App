import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _appTitle = 'CalTrack — Theo dõi Calories';
const _appDescription = 'Theo dõi calo và dinh dưỡng mỗi ngày cùng CalTrack.';
const _androidApplicationId = 'com.example.flutter_application_1';
const _iosBundleIdentifier = 'com.example.flutterApplication1';

void main() {
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

    expect(pubspec, contains('- assets/branding/caltrack-mark.png'));
    expect(pubspec, contains('- assets/branding/caltrack-logo.png'));
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
