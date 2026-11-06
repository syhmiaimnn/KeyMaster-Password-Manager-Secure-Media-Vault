import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'crypto_service.dart';
import 'security_service.dart';

/// Shares a photo that has already been cleaned and checked.
///
/// This is the one place that writes a readable copy of a vault photo to the
/// phone's storage, because another app has to be able to open it. The copy:
///   * is already stripped of hidden data (the caller checked it),
///   * gets a neutral random name (no date, no title),
///   * lives in the app's private cache folder, and
///   * is deleted again as soon as possible (see [clearTemporaryShares]).
class CleanShareService {
  static const String _folderName = 'keymaster_share';

  // The share plugin keeps its own copy of a shared file in this cache folder.
  static const String _pluginFolderName = 'share_plus';

  // Counts shares, so a late clean-up never deletes a newer share.
  static int _generation = 0;
  static _ResumeOnce? _waiter;

  final CryptoService _crypto = CryptoService();
  final SecurityService _security = SecurityService();

  /// Writes [bytes] (a JPEG) to a temporary file and opens the share sheet.
  /// Throws if the file cannot be written or the sheet cannot be opened.
  Future<void> shareJpeg(Uint8List bytes) async {
    final generation = ++_generation;
    await clearTemporaryShares(); // leftovers of an earlier share

    final cache = await getTemporaryDirectory();
    final folder = Directory('${cache.path}${Platform.pathSeparator}$_folderName');
    await folder.create(recursive: true);
    final file = File(
      '${folder.path}${Platform.pathSeparator}photo_${_randomName()}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);

    // The share sheet covers the app. Do not lock it while the sheet is open.
    _security.pauseAutoLock();
    try {
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path, mimeType: 'image/jpeg')]),
      );
    } catch (_) {
      _security.resumeAutoLock();
      await clearTemporaryShares();
      rethrow;
    }

    unawaited(_resumeAutoLockWhenBack());

    // The other app may still be reading the file, so it is not deleted now.
    unawaited(
      Future<void>.delayed(const Duration(minutes: 3), () {
        if (generation == _generation) unawaited(clearTemporaryShares());
      }),
    );
  }

  /// Deletes every temporary copy made for sharing. Safe to call at any time.
  /// It is called before each share, when the Photos tab opens, when the vault
  /// locks and when all data is erased.
  static Future<void> clearTemporaryShares() async {
    try {
      final cache = await getTemporaryDirectory();
      for (final name in const <String>[_folderName, _pluginFolderName]) {
        final folder = Directory('${cache.path}${Platform.pathSeparator}$name');
        if (await folder.exists()) await folder.delete(recursive: true);
      }
    } catch (_) {
      // Best effort. The files hold no hidden data and sit in the app's
      // private cache, and the next clean-up tries again.
    }
  }

  // On Android the share call can finish the moment the sheet opens, while
  // the app is still moving to the background. Wait a moment, then give the
  // normal auto-lock back once the app is in front again.
  Future<void> _resumeAutoLockWhenBack() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) {
      _security.resumeAutoLock();
      return;
    }
    _waiter?.cancel();
    _waiter = _ResumeOnce(_security.resumeAutoLock);
  }

  String _randomName() {
    final bytes = _crypto.randomBytes(6);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Calls [onResumed] the next time the app comes back to the front.
class _ResumeOnce with WidgetsBindingObserver {
  final VoidCallback onResumed;
  bool _done = false;

  _ResumeOnce(this.onResumed) {
    WidgetsBinding.instance.addObserver(this);
  }

  void cancel() {
    if (_done) return;
    _done = true;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _done) return;
    cancel();
    onResumed();
  }
}
