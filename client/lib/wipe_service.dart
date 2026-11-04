import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';
import 'security_service.dart';
import 'vault_store.dart';

/// "Erase all data": removes the encrypted photos, the vault, the keys and
/// the settings, so the app is as new.
class WipeService {
  static Future<void> eraseEverything() async {
    // 1. The encrypted photo files
    try {
      final base = await getApplicationDocumentsDirectory();
      final folder = Directory('${base.path}${Platform.pathSeparator}media_vault');
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {
      // Without the vault key (deleted next) the files are unreadable anyway.
    }

    // 2. Keys, items, counters and settings in secure storage
    await SecurityService().wipeAll();

    // 3. Everything still in memory
    VaultStore.instance.clear();
    AppSettings.instance.resetToDefaults();
    imageCache.clear();
    imageCache.clearLiveImages();
  }
}
