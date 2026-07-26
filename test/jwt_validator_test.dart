import 'dart:convert';

import 'package:flutter_application_1/features/auth/utils/jwt_validator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a JWT-shaped string with the supplied payload. The signature is
/// irrelevant here: the client only inspects the claim, the server verifies it.
String buildToken(Map<String, dynamic> payload, {String signature = 'sig'}) {
  String encode(Map<String, dynamic> part) =>
      base64Url.encode(utf8.encode(json.encode(part))).replaceAll('=', '');

  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode(payload)}.$signature';
}

int epochSeconds(DateTime moment) => moment.millisecondsSinceEpoch ~/ 1000;

void main() {
  const validator = JwtValidator();
  final now = DateTime.utc(2026, 7, 26, 12);

  group('valid tokens', () {
    test('a token expiring in the future is valid', () {
      final token = buildToken({'exp': epochSeconds(now.add(const Duration(days: 7)))});

      expect(validator.isValid(token, now: now), isTrue);
    });

    test('exp is read as a UTC instant', () {
      final expiry = now.add(const Duration(hours: 3));
      final token = buildToken({'exp': epochSeconds(expiry)});

      expect(validator.expiryOf(token), expiry);
    });

    test('a floating-point exp is accepted', () {
      // Some issuers emit exp as a JSON number rather than an integer.
      final token = buildToken({'exp': epochSeconds(now.add(const Duration(days: 1))).toDouble()});

      expect(validator.isValid(token, now: now), isTrue);
    });

    test('clock skew tolerates a token that just expired', () {
      final token = buildToken({'exp': epochSeconds(now.subtract(const Duration(seconds: 10)))});

      // Default skew is 30s, so a 10s-stale token still passes.
      expect(validator.isValid(token, now: now), isTrue);
    });
  });

  group('invalid tokens', () {
    test('an expired token is rejected', () {
      final token = buildToken({'exp': epochSeconds(now.subtract(const Duration(days: 1)))});

      expect(validator.isValid(token, now: now), isFalse);
    });

    test('a token past the skew window is rejected', () {
      final token = buildToken({'exp': epochSeconds(now.subtract(const Duration(minutes: 5)))});

      expect(validator.isValid(token, now: now), isFalse);
    });

    test('a missing exp claim is rejected', () {
      // Previously this was treated as valid, so a malformed token could live
      // forever and cause a 401 loop on every request.
      final token = buildToken({'sub': '42', 'name': 'duy'});

      expect(validator.isValid(token, now: now), isFalse);
      expect(validator.expiryOf(token), isNull);
    });

    test('a non-numeric exp is rejected', () {
      final token = buildToken({'exp': 'not-a-number'});

      expect(validator.isValid(token, now: now), isFalse);
    });

    test('a null exp is rejected', () {
      final token = buildToken({'exp': null});

      expect(validator.isValid(token, now: now), isFalse);
    });

    test('a token without three segments is rejected', () {
      expect(validator.isValid('header.payload', now: now), isFalse);
      expect(validator.isValid('only-one-segment', now: now), isFalse);
      expect(validator.isValid('a.b.c.d', now: now), isFalse);
    });

    test('a payload that is not valid base64url is rejected', () {
      expect(validator.isValid('header.!!!not-base64!!!.sig', now: now), isFalse);
    });

    test('a payload that is not JSON is rejected', () {
      final payload = base64Url.encode(utf8.encode('this is not json')).replaceAll('=', '');

      expect(validator.isValid('header.$payload.sig', now: now), isFalse);
    });

    test('a payload that is a JSON array rather than an object is rejected', () {
      final payload = base64Url.encode(utf8.encode('[1,2,3]')).replaceAll('=', '');

      expect(validator.isValid('header.$payload.sig', now: now), isFalse);
    });

    test('null and empty tokens are rejected', () {
      expect(validator.isValid(null, now: now), isFalse);
      expect(validator.isValid('', now: now), isFalse);
    });
  });
}
