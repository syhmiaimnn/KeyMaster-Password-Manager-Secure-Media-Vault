import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'vault_item.dart';

class SecurityService {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  static const _pinKey = 'master_pin';
  static const _vaultItemsKey = 'vault_items_data';

  // --- PIN Operations ---
  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  Future<String?> getPin() async {
    return await _storage.read(key: _pinKey);
  }

  Future<bool> verifyPin(String enteredPin) async {
    String? storedPin = await getPin();
    return storedPin == enteredPin;
  }

  Future<bool> hasPin() async {
    String? pin = await getPin();
    return pin != null && pin.isNotEmpty;
  }

  // --- Vault Items Persistence ---
  Future<void> saveVaultItems(List<VaultItem> items) async {
    String rawData = VaultItem.serializeList(items);
    await _storage.write(key: _vaultItemsKey, value: rawData);
  }

  Future<List<VaultItem>> loadVaultItems() async {
    String? rawData = await _storage.read(key: _vaultItemsKey);
    if (rawData == null || rawData.isEmpty) return [];
    return VaultItem.deserializeList(rawData);
  }

  // --- Biometric Authentication ---
  Future<bool> authenticateWithBiometrics() async {
    try {
      bool canCheck = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canCheck) return false;

    return await _localAuth.authenticate(
  localizedReason: 'Authenticate to unlock KeyMaster',
  biometricOnly: true,
  persistAcrossBackgrounding: true,
);
    } catch (_) {
      return false;
    }
  }
}