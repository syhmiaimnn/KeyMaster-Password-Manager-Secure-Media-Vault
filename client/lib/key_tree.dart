import 'dart:convert';
import 'dart:typed_data';

import 'crypto_service.dart';
import 'photo_folder.dart';
import 'vault_item.dart';

/// The key tree from report section 3.4.2.
///
///   vault key           random; the PIN, the recovery phrase and the
///     |                 fingerprint each hold their own locked copy
///     +-- folder key    random, one per folder; saved inside the encrypted
///           |           vault data, so the vault key protects it
///           +-- photo key   random, one per photo; locked with its folder key
///                 |
///                 +-- the encrypted photo file and its thumbnail
///
/// Every node has its own key. A leaked photo key opens one photo. A leaked
/// folder key opens the photos of one folder. Only the vault key opens all.
///
/// This class is the only place that locks and unlocks photo keys.
class KeyTree {
  KeyTree([CryptoService? crypto]) : _crypto = crypto ?? CryptoService();

  final CryptoService _crypto;

  /// A locked photo key starts with this. A photo saved before Phase 6 has its
  /// key stored as plain base64 instead (inside the encrypted vault data).
  static const String wrappedPrefix = 'k2.';

  static bool isWrapped(String stored) => stored.startsWith(wrappedPrefix);

  /// The extra data that is checked with every locked photo key. It ties the
  /// locked key to one folder and one photo, so it cannot be copied onto
  /// another photo's record and still work.
  List<int> _aad(String folderId, String photoId) {
    return utf8.encode('keymaster:v1:photo-key:$folderId:$photoId');
  }

  /// A new random 32-byte key.
  Uint8List newKey() => _crypto.randomBytes(32);

  /// Makes a new folder with its own random id and key.
  PhotoFolder newFolder(
    String name, {
    bool requiresPin = false,
    int colorIndex = 0,
  }) {
    final idBytes = _crypto.randomBytes(8);
    final id = idBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return PhotoFolder(
      id: id,
      name: name.trim(),
      key: base64Encode(newKey()),
      requiresPin: requiresPin,
      colorIndex: colorIndex,
    );
  }

  /// Locks [fileKey] with the key of [folder]. The result is what is saved in
  /// the photo's record.
  Future<String> wrapFileKey(
    Uint8List fileKey,
    PhotoFolder folder,
    String photoId,
  ) async {
    final packed = await _crypto.encrypt(
      fileKey,
      folder.keyBytes,
      aad: _aad(folder.id, photoId),
    );
    return '$wrappedPrefix$packed';
  }

  /// The photo's own key. [folder] is the folder the record says the photo is
  /// in. Throws if the folder key is missing or wrong, or if the saved key was
  /// changed in any way.
  Future<Uint8List> unwrapFileKey(VaultItem photo, PhotoFolder? folder) async {
    final stored = photo.fileKey;

    // Saved before Phase 6: the key is plain base64.
    if (!isWrapped(stored)) return base64Decode(stored);

    if (folder == null || folder.id != photo.folderId) {
      throw StateError('The folder key for this photo is missing.');
    }
    final key = await _crypto.decrypt(
      stored.substring(wrappedPrefix.length),
      folder.keyBytes,
      aad: _aad(folder.id, photo.id),
    );
    if (key.length != 32) {
      throw const FormatException('The photo key has the wrong length.');
    }
    return key;
  }

  /// Puts a photo saved before Phase 6 into [folder]: its key is locked with
  /// the folder key. The photo files are not touched.
  Future<VaultItem> adopt(VaultItem photo, PhotoFolder folder) async {
    final key = base64Decode(photo.fileKey);
    final wrapped = await wrapFileKey(key, folder, photo.id);
    return photo.copyWith(fileKey: wrapped, folderId: folder.id);
  }

  /// Moves a photo to another folder. Only its key is locked again, with the
  /// key of [to]. The encrypted files stay exactly as they are.
  Future<VaultItem> moveToFolder(
    VaultItem photo,
    PhotoFolder? from,
    PhotoFolder to,
  ) async {
    final key = await unwrapFileKey(photo, from);
    final wrapped = await wrapFileKey(key, to, photo.id);
    key.fillRange(0, key.length, 0);
    return photo.copyWith(fileKey: wrapped, folderId: to.id);
  }
}
