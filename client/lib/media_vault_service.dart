import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import 'crypto_service.dart';
import 'vault_item.dart';

/// A problem we can explain to the user in one sentence.
class MediaVaultException implements Exception {
  final String message;
  const MediaVaultException(this.message);

  @override
  String toString() => message;
}

/// What the original photo carried in its hidden data (EXIF).
class MetadataReport {
  final int tagCount;
  final bool hadLocation; // GPS tags
  final bool hadCameraInfo; // camera make or model

  const MetadataReport({
    required this.tagCount,
    required this.hadLocation,
    required this.hadCameraInfo,
  });

  factory MetadataReport.fromTagNames(Iterable<String> names) {
    final list = names.toList();
    return MetadataReport(
      tagCount: list.length,
      hadLocation: list.any((name) => name.startsWith('GPS')),
      hadCameraInfo:
          list.any((name) => name.contains('Make') || name.contains('Model')),
    );
  }

  static const MetadataReport none = MetadataReport(
    tagCount: 0,
    hadLocation: false,
    hadCameraInfo: false,
  );
}

/// The result of importing one photo.
class ImportedPhoto {
  final VaultItem item;
  final MetadataReport report;
  const ImportedPhoto(this.item, this.report);
}

class MediaVaultService {
  final CryptoService _crypto = CryptoService();

  // Photos are scaled down to roughly this many pixels (never enlarged).
  static const int _photoSize = 2048;
  static const int _thumbSize = 320;

  // ---------------------------------------------------------------
  // Where the files live
  // ---------------------------------------------------------------

  Future<File> _file(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final folder = Directory('${base.path}${Platform.pathSeparator}media_vault');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File('${folder.path}${Platform.pathSeparator}$name');
  }

  static String _thumbName(String id) => '$id.thumb.enc';

  /// The label that is checked together with the data. It ties each file to
  /// one photo and one part, so files cannot be swapped.
  List<int> _aad(String id, String part) =>
      utf8.encode('keymaster:v1:photo:$id:$part');

  // ---------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------

  /// Cleans, encrypts and saves one photo. Returns the new record. The caller
  /// must add it to the vault list and save the list.
  Future<ImportedPhoto> importPhoto(Uint8List original) async {
    // 1. What hidden data does the original carry?
    var report = MetadataReport.none;
    try {
      final tags = await readExifFromBytes(original);
      report = MetadataReport.fromTagNames(tags.keys);
    } catch (_) {
      // Not a photo with readable tags. The re-encoding below still runs.
    }

    // 2. Re-encode as JPEG. This drops the hidden data. The photo is turned
    //    upright first, so it does not end up sideways.
    final clean = await _reencode(original, _photoSize, 90);
    final thumb = await _reencode(clean, _thumbSize, 70);

    // 3. Check the result. If a location survived, refuse to save the photo.
    if (await _hasLocation(clean)) {
      throw const MediaVaultException(
        'The location could not be removed from this photo, so it was not saved.',
      );
    }

    // 4. A new random key and name for this photo only.
    final id = _newId();
    final fileKey = _crypto.randomBytes(32);
    final encPhoto = await _crypto.encryptToBytesInBackground(
      clean,
      fileKey,
      aad: _aad(id, 'full'),
    );
    final encThumb = await _crypto.encryptToBytesInBackground(
      thumb,
      fileKey,
      aad: _aad(id, 'thumb'),
    );

    // 5. Save both files.
    final photoFile = await _file('$id.enc');
    final thumbFile = await _file(_thumbName(id));
    try {
      await photoFile.writeAsBytes(encPhoto, flush: true);
      await thumbFile.writeAsBytes(encThumb, flush: true);
    } catch (_) {
      await _remove(photoFile);
      await _remove(thumbFile);
      rethrow;
    }

    final item = VaultItem(
      id: id,
      type: 'Media',
      title: _defaultTitle(),
      mediaPath: '$id.enc',
      mimeType: 'image/jpeg',
      sizeBytes: clean.length,
      fileKey: base64Encode(fileKey),
    );
    return ImportedPhoto(item, report);
  }

  Future<Uint8List> _reencode(Uint8List bytes, int size, int quality) async {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: size,
      minHeight: size,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    if (out.isEmpty) {
      throw const MediaVaultException(
        'This photo could not be processed, so it was not saved.',
      );
    }
    return out;
  }

  Future<bool> _hasLocation(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      return tags.keys.any((name) => name.startsWith('GPS'));
    } catch (_) {
      return false;
    }
  }

  String _newId() {
    final bytes = _crypto.randomBytes(12);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _defaultTitle() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Photo ${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
  }

  // ---------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------

  Uint8List _keyOf(VaultItem item) => base64Decode(item.fileKey);

  /// The full photo, decrypted in memory only. Nothing is written to disk.
  Future<Uint8List> readPhoto(VaultItem item) async {
    final file = await _file(item.mediaPath);
    final packed = await file.readAsBytes();
    return _crypto.decryptFromBytesInBackground(
      packed,
      _keyOf(item),
      aad: _aad(item.id, 'full'),
    );
  }

  /// The small preview. It is tiny, so it is decrypted on the main isolate.
  Future<Uint8List> readThumbnail(VaultItem item) async {
    final file = await _file(_thumbName(item.id));
    final packed = await file.readAsBytes();
    return _crypto.decryptFromBytes(
      packed,
      _keyOf(item),
      aad: _aad(item.id, 'thumb'),
    );
  }

  // ---------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------

  /// Deletes both encrypted files. The caller removes the record, and with it
  /// the key.
  Future<void> deletePhotoFiles(VaultItem item) async {
    await _remove(await _file(item.mediaPath));
    await _remove(await _file(_thumbName(item.id)));
  }

  Future<void> _remove(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort. Without the record there is no key, so a leftover file
      // is unreadable anyway.
    }
  }
}