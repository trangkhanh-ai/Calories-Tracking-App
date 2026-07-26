import 'dart:convert';

/// Local, signature-free inspection of a stored JWT.
///
/// This decides only whether a cached token is worth sending. The server still
/// verifies the signature on every request — this check exists so an obviously
/// dead token never triggers a pointless round trip and a 401 redirect loop.
class JwtValidator {
  const JwtValidator({this.clockSkew = const Duration(seconds: 30)});

  /// Tolerance for a device clock running slightly ahead of the server.
  final Duration clockSkew;

  /// True when the token is structurally sound and not past its `exp`.
  ///
  /// Returns false for a missing, non-numeric, or unparseable `exp`. Treating
  /// "no expiry claim" as valid would let a malformed token live forever.
  bool isValid(String? token, {DateTime? now}) {
    final expiry = expiryOf(token);
    if (expiry == null) {
      return false;
    }

    final reference = (now ?? DateTime.now().toUtc()).toUtc();
    return expiry.isAfter(reference.subtract(clockSkew));
  }

  /// Parses the `exp` claim, or null when the token is unusable.
  DateTime? expiryOf(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }

    final segments = token.split('.');
    if (segments.length != 3) {
      return null;
    }

    final Map<String, dynamic> payload;
    try {
      // base64Url.normalize restores the padding JWTs strip.
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(segments[1])));
      final parsed = json.decode(decoded);
      if (parsed is! Map<String, dynamic>) {
        return null;
      }
      payload = parsed;
    } on FormatException {
      return null;
    } on ArgumentError {
      // base64Url.decode throws ArgumentError on invalid characters.
      return null;
    }

    final exp = payload['exp'];

    // Accept int and double (some issuers emit a JSON number), reject strings
    // and everything else rather than guessing.
    final seconds = switch (exp) {
      final int value => value,
      final double value when value.isFinite => value.toInt(),
      _ => null,
    };

    if (seconds == null) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
