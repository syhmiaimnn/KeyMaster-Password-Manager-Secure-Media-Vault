import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A sealed box: anyone who holds the PUBLIC key can lock a message, but only
/// the holder of the PRIVATE key can open it.
///
/// Why KeyMaster needs this: an intruder photo is taken while the app is
/// locked. At that moment the vault key does not exist in memory, so the photo
/// cannot be locked with it. But the photo must not sit on the phone as a
/// readable file either. So the app keeps a public key in plain storage. It
/// can lock a photo with it at any time. The matching private key is kept
/// locked under the vault key, so the photo can only be opened after a real
/// unlock.
///
/// How one message is locked:
///   1. A new one-time key pair (the "ephemeral" pair) is made.
///   2. X25519 combines the ephemeral private key with the recipient's public
///      key into a shared secret. (The recipient gets the same secret from
///      the ephemeral PUBLIC key and its own private key.)
///   3. HKDF-SHA256 turns that secret into a 256-bit AES key. Both public
///      keys go into the HKDF salt, so the key belongs to this pair only.
///   4. AES-256-GCM locks the message. The ephemeral public key is the AAD, so
///      swapping it for another one makes opening fail.
///   5. The ephemeral private key is thrown away. Even the app can no longer
///      open the message it just locked.
///
/// Layout: ephemeral public key (32) + nonce (12) + ciphertext + tag (16).
class SealedBox {
  const SealedBox._();

  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final List<int> _info = utf8.encode('keymaster:v1:sealed-box');

  static const int keyLength = 32;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  /// The bytes a sealed message adds to the message itself.
  static const int overhead = keyLength + _nonceLength + _macLength;

  /// A new recipient key pair. Both keys are 32 bytes.
  static Future<({Uint8List publicKey, Uint8List privateKey})>
      newKeyPair() async {
    final pair = await _x25519.newKeyPair();
    final publicKey = await pair.extractPublicKey();
    final privateKey = await pair.extractPrivateKeyBytes();
    return (
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: Uint8List.fromList(privateKey),
    );
  }

  static Future<SecretKey> _messageKey(
    SecretKey shared,
    List<int> ephemeralPublic,
    List<int> recipientPublic,
  ) {
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: [...ephemeralPublic, ...recipientPublic],
      info: _info,
    );
  }

  /// Locks [message] so that only the owner of [recipientPublicKey] can open it.
  static Future<Uint8List> seal(
    List<int> message,
    Uint8List recipientPublicKey,
  ) async {
    if (recipientPublicKey.length != keyLength) {
      throw ArgumentError('A public key must be $keyLength bytes.');
    }

    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        recipientPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final key = await _messageKey(shared, ephemeralPublic, recipientPublicKey);

    final box = await _aes.encrypt(message, secretKey: key, aad: ephemeralPublic);
    final out = BytesBuilder(copy: false)
      ..add(ephemeralPublic)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.takeBytes();
  }

  /// Opens a message made by [seal]. Throws if the keys do not match, or if
  /// even one byte was changed.
  static Future<Uint8List> open(
    Uint8List sealed,
    Uint8List privateKey,
    Uint8List publicKey,
  ) async {
    if (sealed.length < overhead) {
      throw const FormatException('Sealed data is too short');
    }
    if (privateKey.length != keyLength || publicKey.length != keyLength) {
      throw ArgumentError('A key must be $keyLength bytes.');
    }

    final ephemeralPublic = Uint8List.sublistView(sealed, 0, keyLength);
    final nonce = Uint8List.sublistView(sealed, keyLength, keyLength + _nonceLength);
    final cipherText = Uint8List.sublistView(
      sealed,
      keyLength + _nonceLength,
      sealed.length - _macLength,
    );
    final mac = Uint8List.sublistView(sealed, sealed.length - _macLength);

    final owner = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final shared = await _x25519.sharedSecretKey(
      keyPair: owner,
      remotePublicKey: SimplePublicKey(
        ephemeralPublic,
        type: KeyPairType.x25519,
      ),
    );
    final key = await _messageKey(shared, ephemeralPublic, publicKey);

    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
      aad: ephemeralPublic,
    );
    return Uint8List.fromList(clear);
  }
}
