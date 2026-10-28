import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// All cryptography for KeyMaster lives in this one class, so the rest of
/// the app never handles ciphers directly.
class CryptoService {
  static final AesGcm _aes = AesGcm.with256bits();
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  /// Cryptographically secure random bytes (salts and the vault key).
  Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  /// PIN + salt -> 32-byte unlock key, using Argon2id.
  /// It runs in a background isolate so the screen does not freeze.
  /// Debug builds are several times slower than release builds. If the
  /// pause bothers you, test with `flutter run --release` instead of
  /// lowering these numbers.
  Future<Uint8List> deriveUnlockKey(String pin, Uint8List salt) {
    return Isolate.run(() async {
      final argon2 = Argon2id(
        memory: 19456, // 19 MiB (the unit is 1 KiB blocks)
        parallelism: 1,
        iterations: 2,
        hashLength: 32,
      );
      final key = await argon2.deriveKeyFromPassword(
        password: pin,
        nonce: salt,
      );
      return Uint8List.fromList(await key.extractBytes());
    });
  }

  /// AES-256-GCM. Returns base64 of: nonce (12 bytes) + ciphertext + tag (16 bytes).
  /// [aad] is extra data that is checked but not encrypted. It ties the
  /// ciphertext to its purpose, so the wrapped key cannot be swapped in
  /// as if it were the item list.
  Future<String> encrypt(
    List<int> plainText,
    Uint8List key, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(
      plainText,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Reverses [encrypt]. Throws if the key is wrong or the data was changed.
  Future<Uint8List> decrypt(
    String packed,
    Uint8List key, {
    List<int> aad = const [],
  }) async {
    final bytes = base64Decode(packed);
    if (bytes.length < _nonceLength + _macLength) {
      throw const FormatException('Encrypted data is too short');
    }
    final box = SecretBox(
      bytes.sublist(_nonceLength, bytes.length - _macLength),
      nonce: bytes.sublist(0, _nonceLength),
      mac: Mac(bytes.sublist(bytes.length - _macLength)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }

  // ---------------------------------------------------------------
  // New in Phase 2: raw bytes for photo files
  // ---------------------------------------------------------------

  /// Same cipher as [encrypt], but the result is raw bytes:
  /// nonce (12) + ciphertext + tag (16). No base64, so files stay small.
  Future<Uint8List> encryptToBytes(
    List<int> plainText,
    Uint8List key, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(
      plainText,
      secretKey: SecretKey(key),
      aad: aad,
    );
    final out = BytesBuilder(copy: false)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.takeBytes();
  }

  /// Reverses [encryptToBytes]. Throws if the key or [aad] is wrong, or if
  /// even one byte of the file was changed.
  Future<Uint8List> decryptFromBytes(
    Uint8List packed,
    Uint8List key, {
    List<int> aad = const [],
  }) async {
    if (packed.length < _nonceLength + _macLength) {
      throw const FormatException('Encrypted data is too short');
    }
    final box = SecretBox(
      Uint8List.sublistView(packed, _nonceLength, packed.length - _macLength),
      nonce: Uint8List.sublistView(packed, 0, _nonceLength),
      mac: Mac(Uint8List.sublistView(packed, packed.length - _macLength)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }

  /// [encryptToBytes] in a background isolate. Use this for whole photos.
  Future<Uint8List> encryptToBytesInBackground(
    List<int> plainText,
    Uint8List key, {
    List<int> aad = const [],
  }) {
    return Isolate.run(() => encryptToBytes(plainText, key, aad: aad));
  }

  /// [decryptFromBytes] in a background isolate. Use this for whole photos.
  Future<Uint8List> decryptFromBytesInBackground(
    Uint8List packed,
    Uint8List key, {
    List<int> aad = const [],
  }) {
    return Isolate.run(() => decryptFromBytes(packed, key, aad: aad));
  }
}