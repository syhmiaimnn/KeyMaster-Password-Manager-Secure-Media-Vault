import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'crypto_service.dart';
import 'intruder_payload.dart';
import 'sealed_box.dart';
import 'security_service.dart';

/// What happened when a photo was requested.
enum CaptureResult {
  saved,

  /// The feature was never set up (no key pair), so nothing was taken.
  notReady,
  noFrontCamera,
  permissionDenied,

  /// Another photo was already being taken.
  busy,
  failed,
}

/// One saved intruder photo file (still locked).
class IntruderEntry {
  final File file;
  final DateTime modified;
  const IntruderEntry(this.file, this.modified);

  String get name => file.uri.pathSegments.last;
}

/// The key pair that opens intruder photos. The private key exists in memory
/// only while a real vault is open.
class IntruderKeys {
  final Uint8List publicKey;
  final Uint8List privateKey;
  IntruderKeys(this.publicKey, this.privateKey);

  /// Overwrites the private key. Call it when the screen that used it closes.
  void clear() => privateKey.fillRange(0, privateKey.length, 0);
}

/// Intruder photo (FR13): after five wrong PINs the front camera takes a
/// photo, and the photo is saved locked, so only the real owner can look at it
/// later.
///
/// The photo is taken while the app is locked, so there is no vault key to
/// lock it with. Instead a key PAIR is made when the feature is switched on:
///   - the public key sits in plain storage, so a locked app can use it;
///   - the private key is saved locked under the real vault key.
/// See sealed_box.dart for how the lock works.
///
/// The photo is never written as a readable file by this app. The camera
/// plugin makes one temporary file. It is read into memory, locked, and
/// deleted straight away.
class IntruderService {
  IntruderService._();
  static final IntruderService instance = IntruderService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final CryptoService _crypto = CryptoService();
  final SecurityService _security = SecurityService();

  static const String _publicKeyName = 'intruder_pub';
  static const String _privateKeyName = 'intruder_priv';
  static const String _seenName = 'intruder_seen_ms';
  static final List<int> _privateAad =
      utf8.encode('keymaster:v1:intruder-private-key');

  /// The oldest photos are deleted when there are more than this.
  static const int maxPhotos = 20;
  static const String _folderName = 'intruder_log';

  bool _busy = false;

  // ---------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------

  static Future<Directory> _directory({bool create = true}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_folderName');
    if (create && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Deletes every intruder photo file. Used by "Erase all data".
  static Future<void> deleteAllFiles() async {
    try {
      final dir = await _directory(create: false);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Without the private key (deleted with the settings) they are
      // unreadable anyway.
    }
  }

  /// The saved photos, newest first.
  Future<List<IntruderEntry>> list() async {
    final dir = await _directory(create: false);
    if (!await dir.exists()) return const <IntruderEntry>[];
    final entries = <IntruderEntry>[];
    await for (final item in dir.list()) {
      if (item is File && item.path.endsWith('.enc')) {
        entries.add(IntruderEntry(item, await item.lastModified()));
      }
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return entries;
  }

  Future<void> _prune() async {
    final entries = await list();
    for (final old in entries.skip(maxPhotos)) {
      await _remove(old.file);
    }
  }

  Future<void> _remove(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort. The file is locked anyway.
    }
  }

  Future<void> delete(IntruderEntry entry) => _remove(entry.file);

  Future<void> deleteAll() async {
    for (final entry in await list()) {
      await _remove(entry.file);
    }
  }

  // ---------------------------------------------------------------
  // Keys
  // ---------------------------------------------------------------

  /// True when the key pair exists.
  Future<bool> isSetUp() async {
    return await _storage.read(key: _publicKeyName) != null &&
        await _storage.read(key: _privateKeyName) != null;
  }

  /// Makes the key pair if there is none. Real session only, because the
  /// private key is locked under the real vault key.
  Future<void> setUp() async {
    if (await isSetUp()) return;
    final pair = await SealedBox.newKeyPair();
    try {
      final lockedPrivate = await _security.encryptForRealVault(
        pair.privateKey,
        aad: _privateAad,
      );
      // The private key goes first. The public key is what switches capture
      // on, so it is written last.
      await _storage.write(key: _privateKeyName, value: lockedPrivate);
      await _storage.write(
        key: _publicKeyName,
        value: base64Encode(pair.publicKey),
      );
    } finally {
      pair.privateKey.fillRange(0, pair.privateKey.length, 0);
    }
  }

  /// Reads both keys. Real session only. Call [IntruderKeys.clear] when done.
  Future<IntruderKeys> loadKeys() async {
    final publicText = await _storage.read(key: _publicKeyName);
    final privateText = await _storage.read(key: _privateKeyName);
    if (publicText == null || privateText == null) {
      throw StateError('Intruder photos are not set up.');
    }
    final privateKey = await _security.decryptForRealVault(
      privateText,
      aad: _privateAad,
    );
    return IntruderKeys(base64Decode(publicText), privateKey);
  }

  // ---------------------------------------------------------------
  // Take a photo (works while the app is locked)
  // ---------------------------------------------------------------

  /// Takes one photo with the front camera and saves it locked. [failedCount]
  /// is the number of wrong PINs so far (0 for a test photo).
  ///
  /// It never throws and never shows anything, so a failed capture does not
  /// get in the way of the lock screen.
  Future<CaptureResult> capture({required int failedCount}) async {
    if (_busy) return CaptureResult.busy;
    _busy = true;

    CameraController? controller;
    File? temp;
    try {
      final publicText = await _storage.read(key: _publicKeyName);
      if (publicText == null) return CaptureResult.notReady;
      final publicKey = Uint8List.fromList(base64Decode(publicText));

      final cameras = await availableCameras();
      CameraDescription? front;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          front = camera;
          break;
        }
      }
      if (front == null) return CaptureResult.noFrontCamera;

      controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize().timeout(const Duration(seconds: 10));
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Some front cameras have no flash setting.
      }
      // Give the camera a moment to settle its exposure.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final shot =
          await controller.takePicture().timeout(const Duration(seconds: 10));
      temp = File(shot.path);
      final jpeg = await temp.readAsBytes();

      final payload = IntruderPayload(
        time: DateTime.now(),
        failedCount: failedCount,
        jpeg: jpeg,
      ).pack();
      final sealed = await SealedBox.seal(payload, publicKey);
      await _save(sealed);
      return CaptureResult.saved;
    } on CameraException catch (e) {
      return e.code.startsWith('CameraAccess')
          ? CaptureResult.permissionDenied
          : CaptureResult.failed;
    } catch (_) {
      return CaptureResult.failed;
    } finally {
      try {
        await controller?.dispose();
      } catch (_) {
        // Nothing more to do.
      }
      final leftover = temp;
      if (leftover != null) await _remove(leftover);
      _busy = false;
    }
  }

  Future<void> _save(Uint8List sealed) async {
    final dir = await _directory();
    final name = _crypto
        .randomBytes(12)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final file = File('${dir.path}${Platform.pathSeparator}$name.enc');
    await file.writeAsBytes(sealed, flush: true);
    await _prune();
  }

  // ---------------------------------------------------------------
  // Look at a photo (real session only)
  // ---------------------------------------------------------------

  /// Opens one saved photo. Throws if the file was changed.
  Future<IntruderPayload> open(IntruderEntry entry, IntruderKeys keys) async {
    final sealed = await entry.file.readAsBytes();
    final plain = await SealedBox.open(sealed, keys.privateKey, keys.publicKey);
    return IntruderPayload.unpack(plain);
  }

  // ---------------------------------------------------------------
  // What is new since the owner last looked
  // ---------------------------------------------------------------

  /// How many photos were taken since the log was last opened.
  Future<int> unseenCount() async {
    final seen = int.tryParse(await _storage.read(key: _seenName) ?? '') ?? 0;
    final entries = await list();
    return entries
        .where((entry) => entry.modified.millisecondsSinceEpoch > seen)
        .length;
  }

  Future<void> markSeen() async {
    await _storage.write(
      key: _seenName,
      value: '${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
