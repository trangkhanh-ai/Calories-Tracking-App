import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String shellQuote(String value) => "'${value.replaceAll("'", "'\\\"'\\\"'")}'";

String? resolveBash() {
  final candidates = Platform.isWindows
      ? <String>[
          r'C:\Program Files\Git\bin\bash.exe',
          r'C:\Program Files\Git\usr\bin\bash.exe',
          'bash',
        ]
      : const <String>['bash'];

  for (final candidate in candidates) {
    try {
      if (Process.runSync(candidate, const ['-c', 'true']).exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      // Try the next standard Bash location.
    }
  }

  return null;
}

final bashExecutable = resolveBash();

/// Exercises the BACKEND_BASE_URL guard in scripts/vercel-build.sh directly.
///
/// The script is sourced with its `main` suppressed, so only the validation
/// function runs — no Flutter SDK is downloaded and no build is attempted.
Future<ProcessResult> validate(String? url) {
  final backendUrlSetup = url == null
      ? 'unset BACKEND_BASE_URL'
      : 'export BACKEND_BASE_URL=${shellQuote(url)}';

  // Pass the path as a quoted positional argument so spaces in the Windows
  // workspace path cannot be split by Bash.
  final harness = <String>[
    'set -uo pipefail',
    backendUrlSetup,
    "set -- ${shellQuote('scripts/vercel-build.sh')}",
    r'script_path="$1"',
    r'''eval "$(tr -d '\r' < "$script_path" | sed 's|^main "$@"$||')"''',
    'validate_backend_base_url',
  ].join('\n');

  return Process.run(bashExecutable!, [
    '-c',
    harness,
  ], includeParentEnvironment: true);
}

void main() {
  // Requires bash; skipped where it is unavailable.
  group(
    'BACKEND_BASE_URL validation',
    skip: bashExecutable == null ? 'bash unavailable' : false,
    () {
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
            reason:
                '"${invalid.key}" (${invalid.value}) should have been rejected',
          );
        });
      }

      test('rejects a missing variable', () async {
        final result = await validate(null);

        expect(result.exitCode, isNot(0));
      });

      test('the failure message never echoes the whole URL', () async {
        final result = await validate(
          'https://user:secret@example.onrender.com',
        );

        expect(result.exitCode, isNot(0));
        // Credentials must not be reproduced in a public build log.
        expect(result.stderr.toString(), isNot(contains('secret')));
      });
    },
  );
}
