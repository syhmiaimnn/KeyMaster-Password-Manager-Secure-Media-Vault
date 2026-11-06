import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import 'crypto_service.dart';
import 'key_tree.dart';
import 'metadata_analysis.dart';
import 'metadata_scanner.dart';
import 'photo_folder.dart';
import 'vault_item.dart';
import 'vault_store.dart';

/// A problem we can explain to the user in one sentence.
class MediaVaultException implements Exception {
  final String message;
  const MediaVaultException(this.message);

  @override
  String toString() => message;
}

/// The result of importing one photo.
class ImportedPhoto {
  final VaultItem item;

  /// What the original carried in its hidden data.
  final MetadataAnalysis before;

  /// What the saved copy carries. This is read back from the cleaned file
  /// before it is encrypted, so it is a check, not a promise.
  final MetadataAnalysis after;

  const ImportedPhoto(this.item, this.before, this.after);
}

/// A clean copy of a vault photo, ready to share.
class CleanCopy {
  final Uint8List bytes;

  /// The result of re-reading [bytes] just before sharing.
  final MetadataAnalysis check;

  const CleanCopy(this.bytes, this.check);
}

class _Cleaned {
  final Uint8List bytes;
  final MetadataAnalysis after;
  const _Cleaned(this.bytes, this.after);
}

class MediaVaultService {
  /// [importFolderId] is the folder that new photos are saved in. Reading,
  /// sharing, moving and deleting photos work in every folder, so leave it out
  /// for those. When it is left out, new photos go in the first folder.
  MediaVaultService({this.importFolderId});

  final String? importFolderId;

  final CryptoService _crypto = CryptoService();
  final KeyTree _tree = KeyTree();

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
  // Looking for hidden data
  // ---------------------------------------------------------------

  /// Lists the hidden data in a photo: the EXIF fields, plus blocks such as
  /// XMP and IPTC. It changes nothing. The same check is used on the original
  /// (to show the preview) and on the cleaned copy (to verify it).
  Future<MetadataAnalysis> analyze(Uint8List bytes) async {
    var scan = FileScan.unknown;
    try {
      // The scan reads the whole file, so it runs in a background isolate.
      scan = await Isolate.run(() => MetadataScanner.scan(bytes));
    } catch (_) {
      // The EXIF fields below are still checked.
    }
    final tags = await _readTags(bytes);
    return MetadataAnalysis.build(tags, scan);
  }

  /// Every EXIF field as name -> printable text. Binary fields (the embedded
  /// thumbnail, the maker note) are listed by name only.
  Future<Map<String, String>> _readTags(Uint8List bytes) async {
    final out = <String, String>{};
    try {
      final raw = await readExifFromBytes(bytes);
      for (final entry in raw.entries) {
        final name = entry.key;
        if (name == 'JPEGThumbnail' ||
            name == 'TIFFThumbnail' ||
            name.contains('MakerNote')) {
          out[name] = '';
          continue;
        }
        try {
          out[name] = entry.value.toString();
        } catch (_) {
          out[name] = '';
        }
      }
    } catch (_) {
      // Not a photo with readable tags.
    }
    return out;
  }

  // ---------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------

  /// Cleans, encrypts and saves one photo. Returns the new record. The caller
  /// must add it to the vault list and save the list.
  ///
  /// Pass [before] when the original was already analysed (the preview screen
  /// does this), so it is not read twice.
  Future<ImportedPhoto> importPhoto(
    Uint8List original, {
    MetadataAnalysis? before,
  }) async {
    // 0. Which folder? Its key will lock this photo's key. Check this first,
    //    so no time is spent on a photo that has nowhere to go.
    final folder = _importFolder();

    // 1. What hidden data does the original carry?
    final report = before ?? await analyze(original);

    // 2. Re-encode as JPEG and read the result back. If anything that could
    //    identify the owner, the place or the time is still in it, the photo
    //    is refused.
    final cleaned = await _sanitize(original);
    final clean = cleaned.bytes;

    // 3. The small preview is made from the clean photo and checked the same way.
    final thumb = await _reencode(clean, _thumbSize, 70);
    final thumbCheck = await analyze(thumb);
    if (!thumbCheck.isClean) {
      throw const MediaVaultException(
        'The preview image could not be cleaned, so the photo was not saved.',
      );
    }

    // 4. A new random key and name for this photo only. The key is locked
    //    with the folder key before it is saved in the record.
    final id = _newId();
    final fileKey = _crypto.randomBytes(32);
    final lockedKey = await _tree.wrapFileKey(fileKey, folder, id);
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
      fileKey: lockedKey,
      folderId: folder.id,
      sanitizedTags: report.storedNames(),
    );
    return ImportedPhoto(item, report, cleaned.after);
  }

  /// Re-encodes [original] as a JPEG without hidden data and checks the
  /// result. Throws [MediaVaultException] when something is still left.
  Future<_Cleaned> _sanitize(Uint8List original) async {
    var clean = await _reencode(original, _photoSize, 90);
    var after = await analyze(clean);

    if (!after.isClean) {
      // Second try, through PNG. A PNG cannot carry EXIF, and a flat picture
      // has no extra layers (some new phones add an HDR layer to JPEGs).
      try {
        final flat = await _reencode(
          original,
          _photoSize,
          100,
          format: CompressFormat.png,
        );
        final second = await _reencode(flat, _photoSize, 90);
        final secondAfter = await analyze(second);
        if (secondAfter.isClean) {
          clean = second;
          after = secondAfter;
        }
      } catch (_) {
        // Keep the first result. It is refused below.
      }
    }

    if (!after.isClean) {
      final left = after.residualText;
      throw MediaVaultException(
        left.isEmpty
            ? 'Hidden data could not be fully removed from this photo, so it was not saved.'
            : 'Hidden data could not be fully removed from this photo '
                '($left), so it was not saved.',
      );
    }
    return _Cleaned(clean, after);
  }

  Future<Uint8List> _reencode(
    Uint8List bytes,
    int size,
    int quality, {
    CompressFormat format = CompressFormat.jpeg,
  }) async {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: size,
      minHeight: size,
      quality: quality,
      format: format,
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

  /// The folder that new photos go into.
  PhotoFolder _importFolder() {
    final store = VaultStore.instance;
    final wanted = importFolderId;
    if (wanted != null) {
      final folder = store.folderById(wanted);
      if (folder == null) {
        throw const MediaVaultException(
          'This folder no longer exists, so the photo was not saved.',
        );
      }
      return folder;
    }
    final folder = store.defaultFolder;
    if (folder == null) {
      throw const MediaVaultException(
        'There is no folder to save this photo in. Create a folder first.',
      );
    }
    return folder;
  }

  /// The photo's own key, unlocked with the key of its folder.
  Future<Uint8List> _keyOf(VaultItem item) {
    final folder = VaultStore.instance.folderById(item.folderId);
    return _tree.unwrapFileKey(item, folder);
  }

  /// The full photo, decrypted in memory only. Nothing is written to disk.
  Future<Uint8List> readPhoto(VaultItem item) async {
    final key = await _keyOf(item);
    final file = await _file(item.mediaPath);
    final packed = await file.readAsBytes();
    return _crypto.decryptFromBytesInBackground(
      packed,
      key,
      aad: _aad(item.id, 'full'),
    );
  }

  /// The small preview. It is tiny, so it is decrypted on the main isolate.
  Future<Uint8List> readThumbnail(VaultItem item) async {
    final key = await _keyOf(item);
    final file = await _file(_thumbName(item.id));
    final packed = await file.readAsBytes();
    return _crypto.decryptFromBytes(
      packed,
      key,
      aad: _aad(item.id, 'thumb'),
    );
  }

  // ---------------------------------------------------------------
  // Clean copy for sharing
  // ---------------------------------------------------------------

  /// Decrypts a photo and checks it once more before it leaves the vault.
  /// Photos saved by this version are already clean, so this normally only
  /// confirms it. If something is found, the photo is cleaned again first.
  /// Throws [MediaVaultException] if the copy still carries hidden data.
  Future<CleanCopy> exportCleanCopy(VaultItem item) async {
    var bytes = await readPhoto(item);
    var check = await analyze(bytes);
    if (!check.isClean) {
      final cleaned = await _sanitize(bytes);
      bytes = cleaned.bytes;
      check = cleaned.after;
    }
    return CleanCopy(bytes, check);
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
