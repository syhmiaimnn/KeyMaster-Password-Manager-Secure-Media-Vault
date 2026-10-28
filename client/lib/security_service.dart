import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto_service.dart';
import 'vault_item.dart';

enum UnlockStatus { success, wrongPin, lockedOut }

class UnlockResult {
  final UnlockStatus status;
  final int attemptsLeft; // wrong PINs left before the first lockout
  final Duration wait; // time left when status is lockedOut

  const UnlockResult(
    this.status, {
    this.attemptsLeft = 0,
    this.wait = Duration.zero,
  });
}

class SecurityService {
  // One shared object for the whole app. The unlocked vault key lives in
  // memory inside it, so every screen must use the same instance.
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final CryptoService _crypto = CryptoService();

  // Names of the values saved in secure storage
  static const String _saltKey = 'vault_salt';
  static const String _wrappedVaultKey = 'vault_wrapped_key';
  static const String _itemsKey = 'vault_items_encrypted';
  static const String _biometricCopyKey = 'vault_biometric_copy';
  static const String _failedAttemptsKey = 'failed_attempts';
  static const String _lockUntilKey = 'lock_until_ms';
  // Plain-text names used by the first version of the app
  static const String _legacyPinKey = 'master_pin';
  static const String _legacyItemsKey = 'vault_items_data';

  // AAD ties each ciphertext to its purpose (see crypto_service.dart)
  static final List<int> _wrapAad = utf8.encode('keymaster:v1:wrapped-vault-key');
  static final List<int> _itemsAad = utf8.encode('keymaster:v1:vault-items');

  // Wrong PINs allowed before the first lockout
  static const int _freeAttempts = 5;

  Uint8List? _vaultKey; // exists only in memory, never saved as it is
  bool get isUnlocked => _vaultKey != null;

  // ---------------------------------------------------------------
  // Auto-lock pause (used while the gallery or camera is open)
  // ---------------------------------------------------------------

  /// How long the app may stay covered by the gallery or camera before it
  /// locks itself anyway.
  static const Duration autoLockGrace = Duration(minutes: 5);

  DateTime? _autoLockPausedUntil;

  /// Call just before opening the gallery or the camera.
  void pauseAutoLock() {
    _autoLockPausedUntil = DateTime.now().add(autoLockGrace);
  }

  /// Call as soon as the gallery or camera has closed.
  void resumeAutoLock() {
    _autoLockPausedUntil = null;
  }

  bool get isAutoLockPaused {
    final until = _autoLockPausedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  // ---------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------

  /// True once a vault has been created on this phone.
  Future<bool> hasPin() async {
    final salt = await _storage.read(key: _saltKey);
    final wrapped = await _storage.read(key: _wrappedVaultKey);
    return salt != null && wrapped != null;
  }

  /// First run: create the vault key, wrap it with the PIN, leave it unlocked.
  Future<void> setupVault(String pin, {bool enableBiometrics = false}) async {
    final salt = _crypto.randomBytes(16);
    final vaultKey = _crypto.randomBytes(32);
    final unlockKey = await _crypto.deriveUnlockKey(pin, salt);
    final wrappedKey =
        await _crypto.encrypt(vaultKey, unlockKey, aad: _wrapAad);
    final emptyItems =
        await _crypto.encrypt(utf8.encode('[]'), vaultKey, aad: _itemsAad);

    // Delete the old plain-text data from the first version of the app
    await _storage.delete(key: _legacyPinKey);
    await _storage.delete(key: _legacyItemsKey);

    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _itemsKey, value: emptyItems);
    if (enableBiometrics) {
      // Interim design, replaced in Phase 1
      await _storage.write(
        key: _biometricCopyKey,
        value: base64Encode(vaultKey),
      );
    } else {
      await _storage.delete(key: _biometricCopyKey);
    }
    await _resetAttempts();
    // Written last, so hasPin() is only true when everything else is saved.
    await _storage.write(key: _wrappedVaultKey, value: wrappedKey);

    _vaultKey = vaultKey;
  }

  // ---------------------------------------------------------------
  // Unlock with PIN (with lockout)
  // ---------------------------------------------------------------

  /// How long the PIN screen must stay locked. Duration.zero = not locked.
  Future<Duration> lockoutRemaining() async {
    final text = await _storage.read(key: _lockUntilKey);
    final untilMs = int.tryParse(text ?? '');
    if (untilMs == null) return Duration.zero;
    final left =
        DateTime.fromMillisecondsSinceEpoch(untilMs).difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<UnlockResult> unlockWithPin(String pin) async {
    final wait = await lockoutRemaining();
    if (wait > Duration.zero) {
      return UnlockResult(UnlockStatus.lockedOut, wait: wait);
    }

    final saltText = await _storage.read(key: _saltKey);
    final wrapped = await _storage.read(key: _wrappedVaultKey);
    if (saltText == null || wrapped == null) {
      return const UnlockResult(UnlockStatus.wrongPin);
    }

    final unlockKey =
        await _crypto.deriveUnlockKey(pin, base64Decode(saltText));
    try {
      // A wrong PIN gives a wrong unlock key, so this throws.
      _vaultKey = await _crypto.decrypt(wrapped, unlockKey, aad: _wrapAad);
    } catch (_) {
      return _registerFailure();
    }
    await _resetAttempts();
    return const UnlockResult(UnlockStatus.success);
  }

  Future<UnlockResult> _registerFailure() async {
    final text = await _storage.read(key: _failedAttemptsKey);
    final failed = (int.tryParse(text ?? '') ?? 0) + 1;
    await _storage.write(key: _failedAttemptsKey, value: '$failed');

    final delay = _delayFor(failed);
    if (delay > Duration.zero) {
      final untilMs = DateTime.now().add(delay).millisecondsSinceEpoch;
      await _storage.write(key: _lockUntilKey, value: '$untilMs');
      return UnlockResult(UnlockStatus.lockedOut, wait: delay);
    }
    return UnlockResult(
      UnlockStatus.wrongPin,
      attemptsLeft: _freeAttempts - failed,
    );
  }

  /// The wait grows with every extra wrong PIN.
  Duration _delayFor(int failed) {
    if (failed < _freeAttempts) return Duration.zero;
    if (failed == 5) return const Duration(seconds: 30);
    if (failed == 6) return const Duration(minutes: 1);
    if (failed == 7) return const Duration(minutes: 5);
    if (failed == 8) return const Duration(minutes: 15);
    return const Duration(hours: 1);
  }

  Future<void> _resetAttempts() async {
    await _storage.delete(key: _failedAttemptsKey);
    await _storage.delete(key: _lockUntilKey);
  }

  // ---------------------------------------------------------------
  // Unlock with biometrics
  // ---------------------------------------------------------------

  Future<bool> isBiometricEnabled() async {
    return await _storage.read(key: _biometricCopyKey) != null;
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      if (!await isBiometricEnabled()) return false;
      if (!await _localAuth.canCheckBiometrics) return false;

      final ok = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock KeyMaster',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!ok) return false;

      final copy = await _storage.read(key: _biometricCopyKey);
      if (copy == null) return false;
      _vaultKey = base64Decode(copy);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Lock and items
  // ---------------------------------------------------------------

  /// Forget the vault key. Call this when the app goes to the background.
  void lock() {
    final key = _vaultKey;
    if (key != null) key.fillRange(0, key.length, 0);
    _vaultKey = null;
  }

  Uint8List _requireKey() {
    final key = _vaultKey;
    if (key == null) throw StateError('The vault is locked');
    return key;
  }

  Future<void> saveVaultItems(List<VaultItem> items) async {
    final key = _requireKey();
    final plain = utf8.encode(VaultItem.serializeList(items));
    final packed = await _crypto.encrypt(plain, key, aad: _itemsAad);
    await _storage.write(key: _itemsKey, value: packed);
  }

  Future<List<VaultItem>> loadVaultItems() async {
    final key = _requireKey();
    final packed = await _storage.read(key: _itemsKey);
    if (packed == null || packed.isEmpty) return [];
    final plain = await _crypto.decrypt(packed, key, aad: _itemsAad);
    return VaultItem.deserializeList(utf8.decode(plain));
  }
}