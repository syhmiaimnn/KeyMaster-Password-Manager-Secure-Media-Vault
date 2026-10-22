import 'dart:convert';

import 'package:client/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final crypto = CryptoService();

  group('CryptoService', () {
    test('decrypt returns exactly what was encrypted', () async {
      final key = crypto.randomBytes(32);
      final packed = await crypto.encrypt(utf8.encode('my secret message'), key);
      final clear = await crypto.decrypt(packed, key);
      expect(utf8.decode(clear), 'my secret message');
    });

    test('the same text gives different output each time (random nonce)', () async {
      final key = crypto.randomBytes(32);
      final a = await crypto.encrypt(utf8.encode('same'), key);
      final b = await crypto.encrypt(utf8.encode('same'), key);
      expect(a, isNot(b));
    });

    test('a wrong key is rejected', () async {
      final packed = await crypto.encrypt(utf8.encode('secret'), crypto.randomBytes(32));
      await expectLater(
        crypto.decrypt(packed, crypto.randomBytes(32)),
        throwsA(anything),
      );
    });

    test('one changed byte is detected', () async {
      final key = crypto.randomBytes(32);
      final packed = await crypto.encrypt(utf8.encode('secret message'), key);
      final bytes = base64Decode(packed);
      bytes[13] ^= 1; // flip one bit inside the ciphertext
      await expectLater(
        crypto.decrypt(base64Encode(bytes), key),
        throwsA(anything),
      );
    });

    test('data cannot be reused for another purpose (AAD)', () async {
      final key = crypto.randomBytes(32);
      final packed = await crypto.encrypt(
        utf8.encode('secret'),
        key,
        aad: utf8.encode('items'),
      );
      await expectLater(
        crypto.decrypt(packed, key, aad: utf8.encode('wrapped-key')),
        throwsA(anything),
      );
    });

    test(
      'same PIN and salt give the same key, another PIN does not',
      () async {
        final salt = crypto.randomBytes(16);
        final a = await crypto.deriveUnlockKey('123456', salt);
        final b = await crypto.deriveUnlockKey('123456', salt);
        final c = await crypto.deriveUnlockKey('654321', salt);
        expect(a.length, 32);
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}