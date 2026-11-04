import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Whether this phone can protect a key with the fingerprint sensor.
enum BiometricStatus {
  /// A strong fingerprint (or face) sensor is set up and ready.
  ready,

  /// The phone has a sensor, but no fingerprint is saved in its settings.
  notEnrolled,

  /// The sensor exists but Android rates it "weak", which is not allowed to
  /// guard a key. Some budget phones are rated this way.
  weakOnly,

  /// No usable sensor, or the native Kotlin step is missing.
  unavailable,
}

/// Why a fingerprint request did not give a key.
enum BiometricFailure {
  cancelled,
  lockout,

  /// A new fingerprint was added to the phone, or the key was deleted. The old
  /// key can never be used again.
  invalidated,
  unavailable,
  failed,
}

class BiometricException implements Exception {
  final BiometricFailure failure;
  final String message;
  const BiometricException(this.failure, this.message);

  @override
  String toString() => 'BiometricException(${failure.name}): $message';
}

/// Talks to the Kotlin code in MainActivity.kt.
///
/// The vault key is encrypted with a key that lives in the Android Keystore.
/// That key can only be used right after a successful fingerprint scan and can
/// never be read out of the phone's secure hardware. What the app saves is
/// only the encrypted result (the "blob"), which is useless without the scan.
class KeystoreBiometric {
  static const MethodChannel _channel = MethodChannel('keymaster/biometric');

  static Future<BiometricStatus> status() async {
    try {
      final text = await _channel.invokeMethod<String>('status');
      return switch (text) {
        'ready' => BiometricStatus.ready,
        'not_enrolled' => BiometricStatus.notEnrolled,
        'weak_only' => BiometricStatus.weakOnly,
        _ => BiometricStatus.unavailable,
      };
    } catch (_) {
      return BiometricStatus.unavailable;
    }
  }

  /// Creates a fresh Keystore key, asks for a fingerprint and returns [secret]
  /// encrypted with that key. Throws [BiometricException] if it does not work.
  static Future<String> enroll(Uint8List secret) async {
    try {
      final blob = await _channel.invokeMethod<String>('enroll', {
        'secret': base64Encode(secret),
        'title': 'Turn on fingerprint unlock',
        'subtitle': 'Confirm your fingerprint to protect your vault key',
        'negative': 'Cancel',
      });
      if (blob == null || blob.isEmpty) {
        throw const BiometricException(BiometricFailure.failed, 'No data');
      }
      return blob;
    } on PlatformException catch (e) {
      throw _fromPlatform(e);
    } on MissingPluginException {
      throw const BiometricException(
        BiometricFailure.unavailable,
        'The Kotlin step is missing',
      );
    }
  }

  /// Asks for a fingerprint and returns the secret that [blob] protects.
  /// Throws [BiometricException] if it does not work.
  static Future<Uint8List> unlock(String blob) async {
    try {
      final text = await _channel.invokeMethod<String>('unlock', {
        'blob': blob,
        'title': 'Unlock KeyMaster',
        'subtitle': 'Touch the fingerprint sensor',
        'negative': 'Use PIN',
      });
      if (text == null || text.isEmpty) {
        throw const BiometricException(BiometricFailure.failed, 'No data');
      }
      return base64Decode(text);
    } on PlatformException catch (e) {
      throw _fromPlatform(e);
    } on MissingPluginException {
      throw const BiometricException(
        BiometricFailure.unavailable,
        'The Kotlin step is missing',
      );
    }
  }

  /// Removes the Keystore key. Never throws.
  static Future<void> deleteKey() async {
    try {
      await _channel.invokeMethod<void>('deleteKey');
    } catch (_) {
      // No native side (tests), or nothing to delete.
    }
  }

  static BiometricException _fromPlatform(PlatformException e) {
    final failure = switch (e.code) {
      'cancelled' => BiometricFailure.cancelled,
      'lockout' => BiometricFailure.lockout,
      'invalidated' => BiometricFailure.invalidated,
      'unavailable' => BiometricFailure.unavailable,
      _ => BiometricFailure.failed,
    };
    return BiometricException(failure, e.message ?? e.code);
  }
}
