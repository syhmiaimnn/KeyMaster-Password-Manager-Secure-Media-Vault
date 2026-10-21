import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _pinKey = 'master_pin';

  // Save Master PIN securely
  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  // Retrieve stored PIN
  Future<String?> getPin() async {
    return await _storage.read(key: _pinKey);
  }

  // Check if PIN has been set before
  Future<bool> hasPin() async {
    String? pin = await getPin();
    return pin != null && pin.isNotEmpty;
  }

  // Verify entered PIN against stored PIN
  Future<bool> verifyPin(String pin) async {
    String? storedPin = await getPin();
    return storedPin == pin;
  }
}