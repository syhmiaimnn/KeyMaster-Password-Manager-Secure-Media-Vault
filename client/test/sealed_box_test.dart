import 'dart:convert';
import 'dart:typed_data';

import 'package:client/sealed_box.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('key pair', () {
    test('both keys are 32 bytes and each pair is new', () async {
      final a = await SealedBox.newKeyPair();
      final b = await SealedBox.newKeyPair();

      expect(a.publicKey.length, 32);
      expect(a.privateKey.length, 32);
      expect(a.publicKey, isNot(b.publicKey));
      expect(a.privateKey, isNot(b.privateKey));
      expect(a.publicKey, isNot(a.privateKey));
    });
  });

  group('seal and open', () {
    test('the owner gets the message back', () async {
      final owner = await SealedBox.newKeyPair();
      final message = bytesOf('a photo, as bytes');

      final sealed = await SealedBox.seal(message, owner.publicKey);
      final opened =
          await SealedBox.open(sealed, owner.privateKey, owner.publicKey);

      expect(opened, message);
    });

    test('an empty message works', () async {
      final owner = await SealedBox.newKeyPair();
      final sealed = await SealedBox.seal(const <int>[], owner.publicKey);
      final opened =
          await SealedBox.open(sealed, owner.privateKey, owner.publicKey);
      expect(opened, isEmpty);
    });

    test('a large message works (a photo is tens of kilobytes)', () async {
      final owner = await SealedBox.newKeyPair();
      final message = Uint8List.fromList(
        List<int>.generate(200000, (i) => (i * 31 + 7) % 256),
      );

      final sealed = await SealedBox.seal(message, owner.publicKey);
      final opened =
          await SealedBox.open(sealed, owner.privateKey, owner.publicKey);

      expect(opened, message);
    });

    test('the sealed bytes add exactly the documented overhead', () async {
      final owner = await SealedBox.newKeyPair();
      final message = bytesOf('12345678901234567890');
      final sealed = await SealedBox.seal(message, owner.publicKey);

      expect(SealedBox.overhead, 60);
      expect(sealed.length, message.length + SealedBox.overhead);
    });

    test('the plain message cannot be found in the sealed bytes', () async {
      final owner = await SealedBox.newKeyPair();
      final text = 'this text must not appear';
      final sealed = await SealedBox.seal(bytesOf(text), owner.publicKey);

      expect(latin1.decode(sealed, allowInvalid: true).contains(text), isFalse);
    });

    test('sealing the same message twice gives different bytes', () async {
      final owner = await SealedBox.newKeyPair();
      final message = bytesOf('same');

      final one = await SealedBox.seal(message, owner.publicKey);
      final two = await SealedBox.seal(message, owner.publicKey);

      expect(one, isNot(two));
      // The one-time public key at the front is new each time.
      expect(one.sublist(0, 32), isNot(two.sublist(0, 32)));
    });
  });

  group('who can open it', () {
    test('another key pair cannot open it', () async {
      final owner = await SealedBox.newKeyPair();
      final stranger = await SealedBox.newKeyPair();
      final sealed = await SealedBox.seal(bytesOf('secret'), owner.publicKey);

      await expectLater(
        SealedBox.open(sealed, stranger.privateKey, stranger.publicKey),
        throwsA(anything),
      );
    });

    test('the right private key with the wrong public key cannot open it',
        () async {
      final owner = await SealedBox.newKeyPair();
      final stranger = await SealedBox.newKeyPair();
      final sealed = await SealedBox.seal(bytesOf('secret'), owner.publicKey);

      await expectLater(
        SealedBox.open(sealed, owner.privateKey, stranger.publicKey),
        throwsA(anything),
      );
    });

    test('the public key alone cannot open it', () async {
      final owner = await SealedBox.newKeyPair();
      final sealed = await SealedBox.seal(bytesOf('secret'), owner.publicKey);

      // Someone who only has the public key (it is not secret) tries it as if
      // it were the private key.
      await expectLater(
        SealedBox.open(sealed, owner.publicKey, owner.publicKey),
        throwsA(anything),
      );
    });
  });

  group('changed data', () {
    Future<Uint8List> sealedSample(({Uint8List publicKey, Uint8List privateKey}) owner) {
      return SealedBox.seal(bytesOf('do not change me'), owner.publicKey);
    }

    test('changing any single byte makes opening fail', () async {
      final owner = await SealedBox.newKeyPair();
      final sealed = await sealedSample(owner);

      // Front (one-time public key), nonce, ciphertext and tag are all checked.
      for (final index in [0, 15, 31, 32, 40, 43, 44, 50, sealed.length - 17, sealed.length - 16, sealed.length - 1]) {
        final changed = Uint8List.fromList(sealed);
        changed[index] ^= 0x01;
        await expectLater(
          SealedBox.open(changed, owner.privateKey, owner.publicKey),
          throwsA(anything),
          reason: 'byte $index',
        );
      }
    });

    test('a shortened message fails', () async {
      final owner = await SealedBox.newKeyPair();
      final sealed = await sealedSample(owner);
      final shorter = sealed.sublist(0, sealed.length - 1);

      await expectLater(
        SealedBox.open(shorter, owner.privateKey, owner.publicKey),
        throwsA(anything),
      );
    });

    test('data shorter than the overhead is refused as a format problem',
        () async {
      final owner = await SealedBox.newKeyPair();
      await expectLater(
        SealedBox.open(Uint8List(59), owner.privateKey, owner.publicKey),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('bad keys', () {
    test('sealing to a key of the wrong size is refused', () async {
      await expectLater(
        SealedBox.seal(bytesOf('x'), Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('opening with keys of the wrong size is refused', () async {
      final owner = await SealedBox.newKeyPair();
      final sealed = await SealedBox.seal(bytesOf('x'), owner.publicKey);

      await expectLater(
        SealedBox.open(sealed, Uint8List(16), owner.publicKey),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        SealedBox.open(sealed, owner.privateKey, Uint8List(33)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
