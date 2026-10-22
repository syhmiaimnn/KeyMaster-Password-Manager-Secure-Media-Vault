import 'dart:async';
import 'package:flutter/services.dart';

/// Copies secrets to the clipboard and wipes them after a short time.
class ClipboardService {
  static const Duration clearAfter = Duration(seconds: 30);
  static Timer? _timer;
  static DateTime? _clearAt;

  static Future<void> copySensitive(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _clearAt = DateTime.now().add(clearAfter);
    _timer?.cancel();
    _timer = Timer(clearAfter, clearNow);
  }

  /// Wipes the clipboard now, but only if this app put something there.
  static Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    if (_clearAt == null) return;
    _clearAt = null;
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  /// Call when the app comes back to the foreground. The timer may not
  /// have run while the app was in the background.
  static Future<void> clearIfExpired() async {
    final clearAt = _clearAt;
    if (clearAt != null && !DateTime.now().isBefore(clearAt)) {
      await clearNow();
    }
  }
}