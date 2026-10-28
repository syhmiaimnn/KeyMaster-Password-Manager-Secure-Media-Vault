import 'dart:typed_data';

import 'package:client/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final crypto = CryptoService();
  final key = crypto.randomBytes(32);
  final aad = [1, 2, 3];

  test('a photo-sized file survives encrypt then decrypt', () async {
    final photo = crypto.randomBytes(200000);
    final packed = await crypto.encryptToBytes(photo, key, aad: aad);
    final back = await crypto.decryptFromBytes(packed, key, aad: aad);
    expect(back, photo);
  });

  test('encrypted bytes are not the original bytes', () async {
    final photo = Uint8List.fromList(List<int>.filled(1000, 7));
    final packed = await crypto.encryptToBytes(photo, key, aad: aad);
    expect(packed.length, photo.length + 12 + 16);
    expect(packed.sublist(12, 100), isNot(photo.sublist(0, 88)));
  });

  test('the same photo encrypts differently each time', () async {
    final photo = crypto.randomBytes(1000);
    final a = await crypto.encryptToBytes(photo, key, aad: aad);
    final b = await crypto.encryptToBytes(photo, key, aad: aad);
    expect(a, isNot(b));
  });

  test('a wrong key is rejected', () async {
    final packed = await crypto.encryptToBytes([1, 2, 3], key, aad: aad);
    await expectLater(
      crypto.decryptFromBytes(packed, crypto.randomBytes(32), aad: aad),
      throwsA(anything),
    );
  });

  test('a different purpose label (aad) is rejected', () async {
    final packed = await crypto.encryptToBytes([1, 2, 3], key, aad: aad);
    await expectLater(
      crypto.decryptFromBytes(packed, key, aad: [9, 9, 9]),
      throwsA(anything),
    );
  });

  test('one changed byte is detected', () async {
    final packed = await crypto.encryptToBytes(crypto.randomBytes(500), key, aad: aad);
    packed[100] = packed[100] ^ 1;
    await expectLater(
      crypto.decryptFromBytes(packed, key, aad: aad),
      throwsA(anything),
    );
  });

  test('the background versions give the same result', () async {
    final photo = crypto.randomBytes(50000);
    final packed = await crypto.encryptToBytesInBackground(photo, key, aad: aad);
    final back = await crypto.decryptFromBytesInBackground(packed, key, aad: aad);
    expect(back, photo);
  });
}