import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'clipboard_service.dart';

/// Switches Android's "secure window" flag on or off. When it is on, screenshots
/// and screen recordings show a black screen, and the app switcher shows no
/// preview. The native side is a few lines in MainActivity.kt (see the guide).
/// If those lines are missing, this does nothing and the app still works.
class ScreenGuard {
  static const MethodChannel _channel = MethodChannel('keymaster/privacy');

  static Future<void> setSecure(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': on});
    } catch (_) {
      // No native side (desktop preview, tests, or the Kotlin step is missing).
    }
  }
}

/// The user's choices. Saved in secure storage, so they survive restarts.
/// Nothing here is secret, but secure storage is already in the project.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// Seconds the app may stay in the background before it locks (0 = at once).
  static const List<int> autoLockChoices = [0, 30, 60, 300];

  /// Seconds before a copied password is wiped from the clipboard.
  static const List<int> clipboardChoices = [15, 30, 60];

  static const String _kTheme = 'pref_theme';
  static const String _kAutoLock = 'pref_auto_lock_s';
  static const String _kClipboard = 'pref_clipboard_s';
  static const String _kBlockShots = 'pref_block_screenshots';
  static const String _kOnboarded = 'pref_onboarded';
  static const String _kLastUnlock = 'pref_last_unlock_ms';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ThemeMode _themeMode = ThemeMode.dark;
  int _autoLockSeconds = 0;
  int _clipboardSeconds = 30;
  bool _blockScreenshots = true;
  bool _onboardingDone = false;
  DateTime? _lastUnlock;
  DateTime? _previousUnlock;
  bool _biometricOn = false; // kept in memory; the truth is in SecurityService

  ThemeMode get themeMode => _themeMode;
  int get autoLockSeconds => _autoLockSeconds;
  int get clipboardSeconds => _clipboardSeconds;
  bool get blockScreenshots => _blockScreenshots;
  bool get onboardingDone => _onboardingDone;
  bool get biometricOn => _biometricOn;

  /// When the vault was unlocked before this session (null on the first run).
  DateTime? get previousUnlock => _previousUnlock;

  /// Reads the saved choices. Never throws: if storage is not available (for
  /// example in a test), the defaults stay.
  Future<void> load() async {
    try {
      final theme = await _storage.read(key: _kTheme);
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == theme,
        orElse: () => ThemeMode.dark,
      );

      final autoLock = int.tryParse(await _storage.read(key: _kAutoLock) ?? '');
      if (autoLock != null && autoLockChoices.contains(autoLock)) {
        _autoLockSeconds = autoLock;
      }

      final clip = int.tryParse(await _storage.read(key: _kClipboard) ?? '');
      if (clip != null && clipboardChoices.contains(clip)) {
        _clipboardSeconds = clip;
      }

      final shots = await _storage.read(key: _kBlockShots);
      if (shots != null) _blockScreenshots = shots == 'true';

      _onboardingDone = await _storage.read(key: _kOnboarded) == 'true';

      final last = int.tryParse(await _storage.read(key: _kLastUnlock) ?? '');
      if (last != null) _lastUnlock = DateTime.fromMillisecondsSinceEpoch(last);
    } catch (_) {
      // Keep the defaults.
    }
    ClipboardService.clearAfter = Duration(seconds: _clipboardSeconds);
    await ScreenGuard.setSecure(_blockScreenshots);
    notifyListeners();
  }

  Future<void> _save(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // The choice still works until the app closes.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _save(_kTheme, mode.name);
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    _autoLockSeconds = seconds;
    notifyListeners();
    await _save(_kAutoLock, '$seconds');
  }

  Future<void> setClipboardSeconds(int seconds) async {
    _clipboardSeconds = seconds;
    ClipboardService.clearAfter = Duration(seconds: seconds);
    notifyListeners();
    await _save(_kClipboard, '$seconds');
  }

  Future<void> setBlockScreenshots(bool value) async {
    _blockScreenshots = value;
    notifyListeners();
    await ScreenGuard.setSecure(value);
    await _save(_kBlockShots, '$value');
  }

  /// Remember whether biometric unlock is on, so screens can show it.
  void setBiometricOn(bool value) {
    if (_biometricOn == value) return;
    _biometricOn = value;
    notifyListeners();
  }

  Future<void> setOnboardingDone() async {
    _onboardingDone = true;
    notifyListeners();
    await _save(_kOnboarded, 'true');
  }

  /// Call after each successful unlock.
  void recordUnlock() {
    _previousUnlock = _lastUnlock;
    final now = DateTime.now();
    _lastUnlock = now;
    unawaited(_save(_kLastUnlock, '${now.millisecondsSinceEpoch}'));
    notifyListeners();
  }

  /// Used after "Erase all data". Storage itself is already wiped by then.
  void resetToDefaults() {
    _themeMode = ThemeMode.dark;
    _autoLockSeconds = 0;
    _clipboardSeconds = 30;
    _blockScreenshots = true;
    _onboardingDone = false;
    _biometricOn = false;
    _lastUnlock = null;
    _previousUnlock = null;
    ClipboardService.clearAfter = const Duration(seconds: 30);
    notifyListeners();
  }
}
