import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'clipboard_service.dart';
import 'security_service.dart';
import 'ui/widgets.dart';
import 'unlock_screen.dart';
import 'vault_store.dart';

/// Locks the vault when the app has been in the background too long, and
/// sends the user back to the unlock screen.
///
/// This replaces the lock code that used to live in main.dart.
class AppLock with WidgetsBindingObserver {
  AppLock._();
  static final AppLock instance = AppLock._();

  /// Lets us change screens from outside a widget (when the app locks).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  DateTime? _leftAt; // when the app went to the background
  Duration _limit = Duration.zero; // how long it may stay there
  bool _attached = false;

  /// Start watching the app lifecycle. Call once from main().
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final security = SecurityService();

    if (state == AppLifecycleState.paused) {
      if (!security.isUnlocked) return;

      if (security.isAutoLockPaused) {
        // The gallery or camera is open on top of the app. Stay unlocked for
        // now, but only for the grace period.
        _leftAt = DateTime.now();
        _limit = SecurityService.autoLockGrace;
        return;
      }

      final seconds = AppSettings.instance.autoLockSeconds;
      if (seconds <= 0) {
        lockNow(); // Home button, app switcher or screen off
      } else {
        _leftAt = DateTime.now();
        _limit = Duration(seconds: seconds);
      }
    }

    if (state == AppLifecycleState.resumed) {
      // Back in the app: wipe the clipboard if its time has passed
      ClipboardService.clearIfExpired();

      final left = _leftAt;
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) > _limit) {
        lockNow();
      }
    }
  }

  /// Forget the keys, clear what is in memory and show the unlock screen.
  void lockNow() {
    final security = SecurityService();
    if (!security.isUnlocked) return; // nothing to lock

    security.lock(); // forget the vault key
    VaultStore.instance.clear(); // forget the decrypted list

    // Forget decrypted thumbnails and photos that Flutter kept for drawing
    imageCache.clear();
    imageCache.clearLiveImages();

    navigatorKey.currentState?.pushAndRemoveUntil(
      fadeRoute<void>(const UnlockScreen()),
      (route) => false,
    );
  }
}
