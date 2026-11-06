import 'package:flutter/widgets.dart';

import 'app_settings.dart';
import 'clean_share_service.dart';
import 'intruder_service.dart';
import 'media_vault_service.dart';
import 'security_service.dart';
import 'vault_store.dart';

/// "Erase all data": removes the encrypted photos of both vaults, the intruder
/// photos, the vault, the keys and the settings, so the app is as new.
class WipeService {
  static Future<void> eraseEverything() async {
    // 1. The encrypted photo files of the real vault and of the decoy vault,
    //    and the locked intruder photos
    await MediaVaultService.deleteAllFiles();
    await IntruderService.deleteAllFiles();

    // 2. Any readable copy made for sharing a clean photo
    await CleanShareService.clearTemporaryShares();

    // 3. Keys, items, counters and settings in secure storage
    await SecurityService().wipeAll();

    // 4. Everything still in memory
    VaultStore.instance.clear();
    AppSettings.instance.resetToDefaults();
    imageCache.clear();
    imageCache.clearLiveImages();
  }
}
