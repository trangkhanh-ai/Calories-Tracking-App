import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exercises the BACKEND_BASE_URL guard in scripts/vercel-build.sh directly.
///
/// The script is sourced with its `main` suppressed, so only the validation
/// function runs — no Flutter SDK is downloaded and no build is attempted.
Future<ProcessResult> validate(String? url) {
  final script = File('scripts/vercel-build.sh').absolute.path.replaceAll(r'\', '/');

  // Strip the trailing `main "$@"` so sourcing the file only defines functions.
  final harness = '''
set -uo pipefail
eval "\$(sed 's|^main "\\\$@"\$||' "$script")"
validate_backend_base_url
''';

  return Process.run(
    'bash',
    ['-c', harness],
    environment: url == null ? null : {'BACKEND_BASE_URL': url},
    includeParentEnvironment: true,
  );
}

void main() {
  // Requires bash; skipped where it is unavailable.
  final bashAvailable = Process.runSync('bash', ['-c', 'echo ok']).exitCode == 0;

  group('BACKEND_BASE_URL validation', skip: bashAvailable ? false : 'bash unavailable', () {
    test('a bare HTTPS origin is accepted', () async {
      final result = await validate('https://example.onrender.com');

      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('an HTTPS origin with an explicit port is accepted', () async {
      final result = await validate('https://example.onrender.com:8443');

      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    for (final invalid in <String, String>{
      'http://example.onrender.com': 'plain HTTP',
      'https://example.onrender.com/': 'trailing slash',
      'https://example.onrender.com/api': '/api suffix',
      'https://example.onrender.com/path': 'non-root path',
      'https://user:pass@example.onrender.com': 'embedded credentials',
      'https://example.onrender.com?x=1': 'query string',
      'https://example.onrender.com#frag': 'fragment',
      'https://localhost:5000': 'localhost',
      'https://127.0.0.1': 'IPv4 loopback',
      'ftp://example.onrender.com': 'non-HTTPS scheme',
      '': 'empty value',
    }.entries) {
      test('rejects ${invalid.value}', () async {
        final result = await validate(invalid.key);

        expect(
          result.exitCode,
          isNot(0),
          reason: '"${invalid.key}" (${invalid.value}) should have been rejected',
        );
      });
    }

    test('rejects a missing variable', () async {
      final result = await validate(null);

      expect(result.exitCode, isNot(0));
    });

    test('the failure message never echoes the whole URL', () async {
      final result = await validate('https://user:secret@example.onrender.com');

      expect(result.exitCode, isNot(0));
      // Credentials must not be reproduced in a public build log.
      expect(result.stderr.toString(), isNot(contains('secret')));
    });
  });
}
