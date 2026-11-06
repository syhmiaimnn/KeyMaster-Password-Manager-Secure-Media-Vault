import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_service.dart';
import 'decoy_seed.dart';
import 'keystore_biometric.dart';
import 'recovery_phrase.dart';
import 'vault_data.dart';
import 'vault_slot.dart';

enum UnlockStatus { success, wrongPin, lockedOut }

/// The outcome of asking for a fingerprint at the unlock screen.
enum BiometricResult {
  success,
  cancelled,

  /// A new fingerprint was added to the phone, so the old key is gone and
  /// biometric unlock was switched off. The PIN still works.
  invalidated,
  failed,
}

/// The outcome of checking a recovery phrase against the vault.
enum RecoveryOutcome {
  success,

  /// The words are a valid phrase, but not the one for this vault.
  wrongPhrase,

  /// This vault never got a recovery phrase.
  notSet,
}

class UnlockResult {
  final UnlockStatus status;
  final int attemptsLeft; // wrong PINs left before the first lockout
  final Duration wait; // time left when status is lockedOut

  /// Wrong PINs counted since the last good unlock, including this one. It is
  /// 0 when no PIN was checked (for example while waiting out a lockout). The
  /// unlock screen uses it to decide when to take an intruder photo.
  final int failedCount;

  const UnlockResult(
    this.status, {
    this.attemptsLeft = 0,
    this.wait = Duration.zero,
    this.failedCount = 0,
  });
}

/// A PIN that is acceptable on its own but cannot be used here, because it
/// already opens the other vault. The message is safe to show.
class PinNotAllowedException implements Exception {
  final String message;
  const PinNotAllowedException(this.message);

  @override
  String toString() => message;
}

// What one PIN check found: the result for the screen, and, when the PIN was
// right, the vault key it opened and which vault that was.
typedef _PinCheck = ({UnlockResult result, Uint8List? key, VaultSlot? slot});

class SecurityService {
  // One shared object for the whole app. The unlocked vault key lives in
  // memory inside it, so every screen must use the same instance.
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final CryptoService _crypto = CryptoService();
  late final RecoveryPhrase _phrase = RecoveryPhrase(_crypto);

  // Names of the values saved in secure storage. The names of the two vault
  // slots (wrapped key and items) are in vault_slot.dart.
  static const String _saltKey = 'vault_salt';
  static const String _biometricBlobKey = 'vault_biometric_blob';
  static const String _recoveryWrapKey = 'vault_recovery_wrap';
  static const String _failedAttemptsKey = 'failed_attempts';
  static const String _lockUntilKey = 'lock_until_ms';
  // What the real vault knows about the second slot (Phase 7)
  static const String _flagsKey = 'vault_slot_flags';
  // Names used by earlier versions of the app
  static const String _legacyPinKey = 'master_pin';
  static const String _legacyItemsKey = 'vault_items_data';
  // Phases 0 to 3 saved a plain copy of the vault key here for fingerprint
  // unlock. It is deleted as soon as the PIN is entered after the update.
  static const String _legacyBiometricCopyKey = 'vault_biometric_copy';

  // AAD ties each ciphertext to its purpose (see crypto_service.dart)
  static final List<int> _wrapAad = utf8.encode('keymaster:v1:wrapped-vault-key');
  static final List<int> _itemsAad = utf8.encode('keymaster:v1:vault-items');
  static final List<int> _recoveryAad = utf8.encode('keymaster:v1:recovery-wrap');
  static final List<int> _flagsAad = utf8.encode('keymaster:v1:slot-flags');

  // Wrong PINs allowed before the first lockout
  static const int _freeAttempts = 5;

  /// From this many wrong PINs on, every further wrong PIN triggers the
  /// intruder photo (when it is switched on).
  static const int intruderAfterFailures = _freeAttempts;

  Uint8List? _vaultKey; // exists only in memory, never saved as it is
  VaultSlot _slot = VaultSlot.real; // which vault the key above opens

  bool get isUnlocked => _vaultKey != null;

  /// The vault that is open. Only meaningful while [isUnlocked].
  VaultSlot get slot => _slot;

  /// True while the decoy vault is the one that is open.
  bool get isDecoySession => _vaultKey != null && _slot.isDecoy;

  // ---------------------------------------------------------------
  // How the salt and the wrapped vault key are stored
  // ---------------------------------------------------------------
  //
  // Old format (Phase 0 to 2): two values, 'vault_salt' and
  // 'vault_wrapped_key'.
  // New format (written by changePin): one value 'vault_wrapped_key' that
  // reads "v2.<salt>.<wrapped key>". One value means one write, so a crash
  // in the middle of a PIN change can never leave a new salt next to an old
  // wrapped key (which would lock you out for good).
  // Both formats are read, so existing vaults keep working. Since Phase 7 the
  // old format is converted to the new one at the next real unlock, so both
  // slots look the same.

  Future<({Uint8List salt, String wrapped})?> _loadWrap(VaultSlot slot) async {
    final stored = await _storage.read(key: slot.wrapKey);
    if (stored == null) return null;

    final current = WrapFormat.decode(stored);
    if (current != null) return current;
    // Marked as the new format, but damaged.
    if (stored.startsWith('${WrapFormat.prefix}.')) return null;

    // Old format: the salt is a separate value, and only the real vault ever
    // had one.
    if (slot != VaultSlot.real) return null;
    final saltText = await _storage.read(key: _saltKey);
    if (saltText == null) return null;
    try {
      return (salt: base64Decode(saltText), wrapped: stored);
    } on FormatException {
      return null;
    }
  }

  /// Converts an old two-value wrap to the one-value format. No key changes.
  Future<void> _upgradeLegacyWrap() async {
    final stored = await _storage.read(key: VaultSlot.real.wrapKey);
    if (stored == null || stored.startsWith('${WrapFormat.prefix}.')) return;
    final saltText = await _storage.read(key: _saltKey);
    if (saltText == null) return;
    final Uint8List salt;
    try {
      salt = base64Decode(saltText);
    } on FormatException {
      return;
    }
    // One write holds both parts. Only then is the old salt removed.
    await _storage.write(
      key: VaultSlot.real.wrapKey,
      value: WrapFormat.encode(salt, stored),
    );
    await _storage.delete(key: _saltKey);
  }

  // ---------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------

  /// True once a vault has been created on this phone.
  Future<bool> hasPin() async {
    return await _loadWrap(VaultSlot.real) != null;
  }

  /// First run: create the vault key, wrap it with the PIN, leave it unlocked.
  /// Biometric unlock and the recovery phrase are switched on afterwards, with
  /// [enableBiometrics] and [storeRecoveryWords], because both need the user.
  Future<void> setupVault(String pin) async {
    final salt = _crypto.randomBytes(WrapFormat.saltBytes);
    final vaultKey = _crypto.randomBytes(32);
    final unlockKey = await _crypto.deriveUnlockKey(pin, salt);
    final wrappedKey =
        await _crypto.encrypt(vaultKey, unlockKey, aad: _wrapAad);
    final emptyItems =
        await _crypto.encrypt(utf8.encode('[]'), vaultKey, aad: _itemsAad);

    // Delete the old plain-text data from the first version of the app
    await _storage.delete(key: _legacyPinKey);
    await _storage.delete(key: _legacyItemsKey);

    // A brand new vault has no fingerprint key and no recovery phrase yet.
    await _storage.delete(key: _biometricBlobKey);
    await _storage.delete(key: _legacyBiometricCopyKey);
    await _storage.delete(key: _recoveryWrapKey);
    await KeystoreBiometric.deleteKey();

    await _storage.delete(key: _saltKey);
    await _storage.write(key: VaultSlot.real.itemsKey, value: emptyItems);
    await _resetAttempts();

    _vaultKey = vaultKey;
    _slot = VaultSlot.real;
    // The second slot gets random filler, so this vault looks the same as one
    // that has a decoy. A new vault never inherits an old decoy.
    await _ensureSlotStorage(reset: true);

    // Written last, so hasPin() is only true when everything else is saved.
    await _storage.write(
      key: VaultSlot.real.wrapKey,
      value: WrapFormat.encode(salt, wrappedKey),
    );
  }

  // ---------------------------------------------------------------
  // The second slot
  // ---------------------------------------------------------------
  //
  // Both slots always exist, so the storage looks the same with or without a
  // decoy PIN. A slot nobody uses holds random bytes of the same shape as a
  // real wrapped key and a real item list.

  /// Makes sure the second slot and its flags exist. Safe to call again.
  /// Only a real session can do it, because the flags are saved under the
  /// real vault key. With [reset] the second slot is overwritten with fresh
  /// filler even if it exists.
  Future<void> _ensureSlotStorage({bool reset = false}) async {
    if (_vaultKey == null || _slot != VaultSlot.real) return;

    if (!reset) await _upgradeLegacyWrap();

    final decoy = VaultSlot.decoy;
    if (reset || await _storage.read(key: decoy.wrapKey) == null) {
      await _storage.write(
        key: decoy.wrapKey,
        value: SlotFiller.wrap(_crypto.randomBytes),
      );
    }
    if (reset || await _storage.read(key: decoy.itemsKey) == null) {
      await _storage.write(
        key: decoy.itemsKey,
        value: SlotFiller.items(_crypto.randomBytes),
      );
    }
    if (reset || await _storage.read(key: _flagsKey) == null) {
      await _writeFlags(SlotFlags(false, _crypto.randomBytes(32)));
    }
  }

  /// The real vault key, or a [StateError] when the vault is locked or the
  /// decoy vault is the one that is open.
  Uint8List _requireRealKey() {
    final key = _vaultKey;
    if (key == null) throw StateError('The vault is locked');
    if (_slot != VaultSlot.real) {
      throw StateError('This needs the real vault');
    }
    return key;
  }

  Future<SlotFlags?> _readFlags() async {
    final key = _vaultKey;
    if (key == null || _slot != VaultSlot.real) return null;
    final packed = await _storage.read(key: _flagsKey);
    if (packed == null) return null;
    try {
      final plain = await _crypto.decrypt(packed, key, aad: _flagsAad);
      return SlotFlags.parse(utf8.decode(plain));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeFlags(SlotFlags flags) async {
    final key = _requireRealKey();
    final packed = await _crypto.encrypt(
      utf8.encode(flags.serialize()),
      key,
      aad: _flagsAad,
    );
    await _storage.write(key: _flagsKey, value: packed);
  }

  /// True when a decoy PIN is set. Only a real session can tell.
  Future<bool> isDecoyEnabled() async {
    final flags = await _readFlags();
    return flags?.decoyOn ?? false;
  }

  /// Sets the decoy PIN, or changes it if one is already set. A new decoy
  /// vault is filled with a few harmless entries. Changing the PIN of an
  /// existing decoy keeps whatever is in it. Real session only.
  ///
  /// Throws [PinNotAllowedException] when [pin] is the real PIN.
  Future<void> setDecoyPin(String pin) async {
    _requireRealKey();

    // The two PINs must differ, or one of the vaults could never be opened.
    if (await _opensSlot(VaultSlot.real, pin)) {
      throw const PinNotAllowedException(
        'That is your real PIN. Choose a different one for the decoy vault.',
      );
    }

    // An existing decoy keeps its key (and so its items). Otherwise a new one
    // is made.
    final flags = await _readFlags();
    final Uint8List decoyKey;
    final bool keepDecoy;
    if (flags != null && flags.decoyOn) {
      decoyKey = Uint8List.fromList(flags.decoyKey);
      keepDecoy = true;
    } else {
      decoyKey = _crypto.randomBytes(32);
      keepDecoy = false;
    }

    try {
      if (!keepDecoy) {
        // A new decoy vault: its items are saved first, under its own key.
        final seeded = utf8.encode(DecoySeed.build().serialize());
        final packed = await _crypto.encrypt(seeded, decoyKey, aad: _itemsAad);
        await _storage.write(key: VaultSlot.decoy.itemsKey, value: packed);
      }
      // The real vault remembers the decoy key, so it can change the decoy PIN
      // later without losing the decoy items. This comes before the wrap, so
      // the key is never lost.
      await _writeFlags(SlotFlags(true, decoyKey));
      // Last step: wrapping the key with the PIN is what makes it work.
      await _writePinWrap(VaultSlot.decoy, decoyKey, pin);
    } finally {
      decoyKey.fillRange(0, decoyKey.length, 0);
    }
  }

  /// Switches the decoy vault off. The decoy PIN stops working at once, and
  /// its key and items are overwritten with random bytes. The caller deletes
  /// the decoy photo files. Real session only.
  Future<void> removeDecoy() async {
    _requireRealKey();
    // The wrap goes first, so the decoy PIN stops working immediately.
    await _storage.write(
      key: VaultSlot.decoy.wrapKey,
      value: SlotFiller.wrap(_crypto.randomBytes),
    );
    await _storage.write(
      key: VaultSlot.decoy.itemsKey,
      value: SlotFiller.items(_crypto.randomBytes),
    );
    await _writeFlags(SlotFlags(false, _crypto.randomBytes(32)));
  }

  /// True when [pin] opens [slot]. Takes about one unlock. Counts nothing.
  Future<bool> _opensSlot(VaultSlot slot, String pin) async {
    final wrap = await _loadWrap(slot);
    if (wrap == null) return false;
    final unlockKey = await _crypto.deriveUnlockKey(pin, wrap.salt);
    final key = await _tryUnwrap(wrap.wrapped, unlockKey);
    if (key == null) return false;
    key.fillRange(0, key.length, 0);
    return true;
  }

  /// Refuses a new PIN that already opens the OTHER vault.
  Future<void> _refuseOtherVaultPin(String pin) async {
    final other = _slot.isDecoy ? VaultSlot.real : VaultSlot.decoy;
    if (await _opensSlot(other, pin)) {
      throw const PinNotAllowedException(
        'That PIN cannot be used. Choose a different one.',
      );
    }
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

  /// Wrong PINs since the last good unlock.
  Future<int> failedAttempts() async {
    final text = await _storage.read(key: _failedAttemptsKey);
    return int.tryParse(text ?? '') ?? 0;
  }

  /// Opens a wrapped vault key. Returns null for a wrong PIN: a wrong PIN
  /// gives a wrong unlock key, so decrypting fails.
  Future<Uint8List?> _tryUnwrap(String wrapped, Uint8List unlockKey) async {
    try {
      return await _crypto.decrypt(wrapped, unlockKey, aad: _wrapAad);
    } catch (_) {
      return null;
    }
  }

  /// Checks a PIN. On success it also returns the vault key it unlocked and
  /// which vault that was. Wrong PINs are counted and can trigger a lockout.
  ///
  /// [unlocking] is true at the lock screen: then BOTH vaults are tried, and
  /// the same work is done whichever PIN is typed, so the time taken does not
  /// say which vault a PIN belongs to. Inside an open vault only that vault's
  /// PIN counts, so the other PIN is refused there.
  Future<_PinCheck> _checkPin(String pin, {required bool unlocking}) async {
    final wait = await lockoutRemaining();
    if (wait > Duration.zero) {
      return (
        result: UnlockResult(UnlockStatus.lockedOut, wait: wait),
        key: null,
        slot: null,
      );
    }
    return unlocking ? _checkBothSlots(pin) : _checkOneSlot(pin, _slot);
  }

  Future<_PinCheck> _checkBothSlots(String pin) async {
    final real = await _loadWrap(VaultSlot.real);
    if (real == null) {
      return (
        result: const UnlockResult(UnlockStatus.wrongPin),
        key: null,
        slot: null,
      );
    }
    final decoy = await _loadWrap(VaultSlot.decoy);

    // Two derivations at once, always. With no decoy yet a random salt keeps
    // the work the same.
    final decoySalt = decoy?.salt ?? _crypto.randomBytes(WrapFormat.saltBytes);
    final unlockKeys = await Future.wait([
      _crypto.deriveUnlockKey(pin, real.salt),
      _crypto.deriveUnlockKey(pin, decoySalt),
    ]);

    // Both are tried before anything is decided.
    final realKey = await _tryUnwrap(real.wrapped, unlockKeys[0]);
    final decoyKey =
        decoy == null ? null : await _tryUnwrap(decoy.wrapped, unlockKeys[1]);

    if (realKey != null) {
      if (decoyKey != null) decoyKey.fillRange(0, decoyKey.length, 0);
      await _resetAttempts();
      return (
        result: const UnlockResult(UnlockStatus.success),
        key: realKey,
        slot: VaultSlot.real,
      );
    }
    if (decoyKey != null) {
      await _resetAttempts();
      return (
        result: const UnlockResult(UnlockStatus.success),
        key: decoyKey,
        slot: VaultSlot.decoy,
      );
    }
    return (result: await _registerFailure(), key: null, slot: null);
  }

  Future<_PinCheck> _checkOneSlot(String pin, VaultSlot slot) async {
    final wrap = await _loadWrap(slot);
    if (wrap == null) {
      return (
        result: const UnlockResult(UnlockStatus.wrongPin),
        key: null,
        slot: null,
      );
    }
    final unlockKey = await _crypto.deriveUnlockKey(pin, wrap.salt);
    final key = await _tryUnwrap(wrap.wrapped, unlockKey);
    if (key == null) {
      return (result: await _registerFailure(), key: null, slot: null);
    }
    await _resetAttempts();
    return (
      result: const UnlockResult(UnlockStatus.success),
      key: key,
      slot: slot,
    );
  }

  /// The lock screen's PIN check. Opens the real vault for the real PIN and
  /// the decoy vault for the decoy PIN.
  Future<UnlockResult> unlockWithPin(String pin) async {
    final check = await _checkPin(pin, unlocking: true);
    final key = check.key;
    final slot = check.slot;
    if (key != null && slot != null) {
      _vaultKey = key;
      _slot = slot;
      // Remove the unprotected key copy that older versions kept for the
      // fingerprint. Fingerprint unlock is then switched on again in Settings,
      // this time with a key that stays in the Android Keystore.
      await _storage.delete(key: _legacyBiometricCopyKey);
      await _prepareRealSession();
    }
    return check.result;
  }

  /// After a real unlock: make sure the second slot exists (an update from an
  /// earlier phase has none yet). This must never stop the unlock.
  Future<void> _prepareRealSession() async {
    if (_slot != VaultSlot.real) return;
    try {
      await _ensureSlotStorage();
    } catch (_) {
      // Runs again at the next unlock.
    }
  }

  /// Checks a PIN without changing whether the vault is locked. Use it before
  /// a sensitive action. Only the PIN of the vault that is open passes.
  Future<UnlockResult> verifyPin(String pin) async {
    final check = await _checkPin(pin, unlocking: false);
    final key = check.key;
    if (key != null) key.fillRange(0, key.length, 0);
    return check.result;
  }

  Future<UnlockResult> _registerFailure() async {
    final failed = (await failedAttempts()) + 1;
    await _storage.write(key: _failedAttemptsKey, value: '$failed');

    final delay = _delayFor(failed);
    if (delay > Duration.zero) {
      final untilMs = DateTime.now().add(delay).millisecondsSinceEpoch;
      await _storage.write(key: _lockUntilKey, value: '$untilMs');
      return UnlockResult(
        UnlockStatus.lockedOut,
        wait: delay,
        failedCount: failed,
      );
    }
    return UnlockResult(
      UnlockStatus.wrongPin,
      attemptsLeft: _freeAttempts - failed,
      failedCount: failed,
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
  // Change the Master PIN
  // ---------------------------------------------------------------

  /// Re-wraps the same vault key under a new PIN. Your passwords and photos
  /// are not re-encrypted, because they are protected by the vault key, which
  /// does not change. Returns the result of checking [currentPin].
  ///
  /// Throws [PinNotAllowedException] when [newPin] already opens the other
  /// vault.
  Future<UnlockResult> changePin(String currentPin, String newPin) async {
    final check = await _checkPin(currentPin, unlocking: false);
    final vaultKey = check.key;
    if (vaultKey == null) return check.result;

    try {
      await _refuseOtherVaultPin(newPin);
      await _writePinWrap(_slot, vaultKey, newPin);
    } catch (_) {
      vaultKey.fillRange(0, vaultKey.length, 0);
      rethrow;
    }

    _vaultKey = vaultKey;
    return check.result;
  }

  /// Wraps [vaultKey] with a key made from [pin] and saves it in one write
  /// (see the notes near the top of this file).
  Future<void> _writePinWrap(
    VaultSlot slot,
    Uint8List vaultKey,
    String pin,
  ) async {
    final salt = _crypto.randomBytes(WrapFormat.saltBytes);
    final unlockKey = await _crypto.deriveUnlockKey(pin, salt);
    final wrapped = await _crypto.encrypt(vaultKey, unlockKey, aad: _wrapAad);
    await _storage.write(
      key: slot.wrapKey,
      value: WrapFormat.encode(salt, wrapped),
    );
    if (slot == VaultSlot.real) {
      await _storage.delete(key: _saltKey); // the old salt is not used any more
    }
  }

  // ---------------------------------------------------------------
  // Recovery phrase
  // ---------------------------------------------------------------
  //
  // The vault key is wrapped a second time, with a key made from 12 random
  // words. The PIN and the phrase are two independent doors to the same vault
  // key. Neither is stored. Only the two wrapped copies are. The phrase always
  // belongs to the real vault. The decoy vault has none.

  /// True when this vault has a recovery phrase.
  Future<bool> hasRecoveryPhrase() async {
    return await _storage.read(key: _recoveryWrapKey) != null;
  }

  /// Reads typed text and says whether it is a well-formed phrase. This does
  /// not look at the vault.
  Future<PhraseCheck> checkRecoveryText(String text) => _phrase.check(text);

  /// Makes 12 new words. Nothing is saved until [storeRecoveryWords], so the
  /// old phrase keeps working until the user has confirmed the new one.
  Future<List<String>> generateRecoveryWords() async {
    final entropy = _crypto.randomBytes(RecoveryPhrase.entropyBytes);
    try {
      return await _phrase.wordsFromEntropy(entropy);
    } finally {
      entropy.fillRange(0, entropy.length, 0);
    }
  }

  static String _phraseSecret(List<String> words) {
    return words.map((word) => word.trim().toLowerCase()).join(' ');
  }

  /// Saves the vault key wrapped with [words]. The real vault must be
  /// unlocked. Any earlier phrase stops working.
  Future<void> storeRecoveryWords(List<String> words) async {
    final vaultKey = _requireRealKey();
    final salt = _crypto.randomBytes(16);
    final recoveryKey = await _crypto.deriveUnlockKey(_phraseSecret(words), salt);
    final wrapped =
        await _crypto.encrypt(vaultKey, recoveryKey, aad: _recoveryAad);
    await _storage.write(
      key: _recoveryWrapKey,
      value: 'r1.${base64Encode(salt)}.$wrapped',
    );
  }

  /// "Forgot PIN", step 1. If [words] are the right phrase, the vault key is
  /// kept in memory, so the next step can wrap it with a new PIN. Nothing is
  /// saved yet, so quitting now changes nothing.
  Future<RecoveryOutcome> recoverWithPhrase(List<String> words) async {
    final stored = await _storage.read(key: _recoveryWrapKey);
    if (stored == null) return RecoveryOutcome.notSet;
    final parts = stored.split('.');
    if (parts.length != 3 || parts[0] != 'r1') return RecoveryOutcome.notSet;

    final Uint8List salt;
    try {
      salt = base64Decode(parts[1]);
    } catch (_) {
      return RecoveryOutcome.notSet;
    }

    final recoveryKey = await _crypto.deriveUnlockKey(_phraseSecret(words), salt);
    try {
      // A wrong phrase gives a wrong key, so this throws.
      final key =
          await _crypto.decrypt(parts[2], recoveryKey, aad: _recoveryAad);
      lock(); // forget any key still in memory
      _vaultKey = key;
      _slot = VaultSlot.real; // the phrase only ever opens the real vault
      return RecoveryOutcome.success;
    } catch (_) {
      return RecoveryOutcome.wrongPhrase;
    }
  }

  /// "Forgot PIN", step 2. Wraps the recovered vault key with [newPin] and
  /// clears the wrong-PIN counter. Call it only after [recoverWithPhrase]
  /// succeeded. The vault stays unlocked.
  ///
  /// Throws [PinNotAllowedException] when [newPin] is the decoy PIN.
  Future<void> finishRecovery(String newPin) async {
    final vaultKey = _requireRealKey();
    await _refuseOtherVaultPin(newPin);
    await _writePinWrap(VaultSlot.real, vaultKey, newPin);
    await _resetAttempts();
    await _prepareRealSession();
  }

  // ---------------------------------------------------------------
  // Biometrics (key kept in the Android Keystore)
  // ---------------------------------------------------------------
  //
  // Enabling: the vault key is encrypted with a Keystore key that needs a
  // fingerprint scan for every use. Only the encrypted result is saved.
  // Unlocking: a scan lets the Keystore decrypt it again. A new fingerprint
  // added to the phone destroys the Keystore key, which switches this off.
  // The fingerprint always opens the real vault.

  Future<bool> isBiometricEnabled() async {
    return await _storage.read(key: _biometricBlobKey) != null;
  }

  /// Why biometric unlock is, or is not, possible on this phone.
  Future<BiometricStatus> biometricStatus() => KeystoreBiometric.status();

  /// True when the phone has a strong fingerprint sensor that is set up.
  Future<bool> isBiometricSupported() async {
    return await KeystoreBiometric.status() == BiometricStatus.ready;
  }

  /// Turn biometric unlock on. The user must scan a finger once. The real
  /// vault must be unlocked, because the key to protect comes from memory.
  Future<bool> enableBiometrics() async {
    final key = _vaultKey;
    if (key == null || _slot != VaultSlot.real) return false;
    try {
      final blob = await KeystoreBiometric.enroll(key);
      await _storage.write(key: _biometricBlobKey, value: blob);
      await _storage.delete(key: _legacyBiometricCopyKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disableBiometrics() async {
    await _storage.delete(key: _biometricBlobKey);
    await _storage.delete(key: _legacyBiometricCopyKey);
    await KeystoreBiometric.deleteKey();
  }

  Future<BiometricResult> authenticateWithBiometrics() async {
    final blob = await _storage.read(key: _biometricBlobKey);
    if (blob == null) return BiometricResult.failed;
    try {
      _vaultKey = await KeystoreBiometric.unlock(blob);
      _slot = VaultSlot.real;
      await _prepareRealSession();
      return BiometricResult.success;
    } on BiometricException catch (e) {
      if (e.failure == BiometricFailure.invalidated) {
        await disableBiometrics();
        return BiometricResult.invalidated;
      }
      if (e.failure == BiometricFailure.cancelled) {
        return BiometricResult.cancelled;
      }
      return BiometricResult.failed;
    } catch (_) {
      return BiometricResult.failed;
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

  /// Saves the items and the photo folders of the OPEN vault together, as one
  /// encrypted value (see vault_data.dart for why they are never saved
  /// separately).
  Future<void> saveVaultData(VaultData data) async {
    final key = _requireKey();
    final slot = _slot;
    final plain = utf8.encode(data.serialize());
    final packed = await _crypto.encrypt(plain, key, aad: _itemsAad);
    await _storage.write(key: slot.itemsKey, value: packed);
  }

  /// Reads and decrypts the items and folders of the OPEN vault. A vault saved
  /// before Phase 6 has items only, and opens with no folders.
  Future<VaultData> loadVaultData() async {
    final key = _requireKey();
    final packed = await _storage.read(key: _slot.itemsKey);
    if (packed == null || packed.isEmpty) return VaultData.empty;
    final plain = await _crypto.decrypt(packed, key, aad: _itemsAad);
    return VaultData.deserialize(utf8.decode(plain));
  }

  // ---------------------------------------------------------------
  // Locking small secrets under the real vault key (intruder photo keys)
  // ---------------------------------------------------------------

  /// Encrypts [plain] with the real vault key. Real session only.
  Future<String> encryptForRealVault(
    List<int> plain, {
    required List<int> aad,
  }) {
    return _crypto.encrypt(plain, _requireRealKey(), aad: aad);
  }

  /// Reverses [encryptForRealVault]. Real session only.
  Future<Uint8List> decryptForRealVault(
    String packed, {
    required List<int> aad,
  }) {
    return _crypto.decrypt(packed, _requireRealKey(), aad: aad);
  }

  // ---------------------------------------------------------------
  // Unlock speed (for the report)
  // ---------------------------------------------------------------

  /// Milliseconds taken by each of [runs] unlock key derivations on this
  /// phone. Unlocking checks both vault slots at once, so each run does the
  /// same two Argon2id derivations as a real unlock, side by side. The time is
  /// what the user waits, plus a few milliseconds.
  Future<List<int>> measureUnlockSpeed([int runs = 5]) {
    return _crypto.benchmarkKeyDerivation(runs, parallel: 2);
  }

  // ---------------------------------------------------------------
  // Erase everything
  // ---------------------------------------------------------------

  /// Deletes every value KeyMaster saved in secure storage: both vault slots,
  /// the wrapped keys, the encrypted items, the biometric blob, the counters,
  /// the intruder photo keys and the settings, and the fingerprint key in the
  /// Android Keystore.
  /// The caller deletes the photo files (see wipe_service.dart).
  Future<void> wipeAll() async {
    lock();
    _slot = VaultSlot.real;
    await _storage.deleteAll();
    await KeystoreBiometric.deleteKey();
  }

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
}
