import 'dart:math' as math;

import 'ui/format.dart';
import 'vault_item.dart';

/// How strong a password is, from worst to best.
enum StrengthLevel { veryWeak, weak, fair, strong, veryStrong }

class StrengthResult {
  final StrengthLevel level;

  /// A rough estimate of how many guesses it takes, as bits (2^bits guesses).
  final double bits;
  final List<String> tips;

  const StrengthResult(this.level, this.bits, this.tips);

  String get label {
    switch (level) {
      case StrengthLevel.veryWeak:
        return 'Very weak';
      case StrengthLevel.weak:
        return 'Weak';
      case StrengthLevel.fair:
        return 'Fair';
      case StrengthLevel.strong:
        return 'Strong';
      case StrengthLevel.veryStrong:
        return 'Very strong';
    }
  }

  bool get isWeak =>
      level == StrengthLevel.veryWeak || level == StrengthLevel.weak;
}

/// Estimates password strength without sending the password anywhere.
///
/// This is a teaching-grade estimate: character variety x length, with
/// penalties for common passwords, sequences and repeats. It is deliberately
/// simple so it can be explained in the project report.
class PasswordTools {
  static const Set<String> _common = {
    'password',
    'passw0rd',
    'qwerty',
    'qwertyuiop',
    'admin',
    'welcome',
    'letmein',
    'iloveyou',
    'monkey',
    'dragon',
    'football',
    'baseball',
    'login',
    'master',
    'sunshine',
    'princess',
    'secret',
    'shadow',
    'superman',
    'michael',
    'abc',
    'abcdef',
    'trustno',
    'freedom',
    'whatever',
    'hello',
    'test',
    'user',
    'guest',
    'root',
    'default',
  };

  static const List<String> _commonParts = [
    'password',
    'qwerty',
    'admin',
    'welcome',
    'letmein',
    'iloveyou',
    'monkey',
    'dragon',
    'football',
    'sunshine',
    'princess',
    'master',
    'secret',
    'hello',
  ];

  static const List<String> _keyboardRows = [
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
    '1234567890',
  ];

  static StrengthResult evaluate(String password) {
    if (password.isEmpty) {
      return const StrengthResult(StrengthLevel.veryWeak, 0, []);
    }

    final tips = <String>[];
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    final hasSymbol = RegExp(r'[^a-zA-Z0-9]').hasMatch(password);

    var pool = 0;
    if (hasLower) pool += 26;
    if (hasUpper) pool += 26;
    if (hasDigit) pool += 10;
    if (hasSymbol) pool += 33;

    final lower = password.toLowerCase();
    final length = password.runes.length;
    final distinct = password.runes.toSet().length;

    // Repeated characters count a quarter, sequences are subtracted.
    var effective = distinct + (length - distinct) * 0.25;
    effective -= _sequencePenalty(lower);
    if (effective < 1) effective = 1;

    var bits = effective * (math.log(pool) / math.ln2);

    // Very common passwords, with or without digits or symbols on the end.
    final stem = lower.replaceAll(RegExp(r'[^a-z]+$'), '');
    if (_common.contains(lower) || (stem.isNotEmpty && _common.contains(stem))) {
      bits = math.min(bits, 18);
      tips.add('This is one of the most common passwords.');
    } else {
      for (final part in _commonParts) {
        if (lower.contains(part)) {
          bits -= 14;
          tips.add('Avoid common words such as "$part".');
          break;
        }
      }
    }

    if (length < 8) bits = math.min(bits, 35);
    if (bits < 0) bits = 0;

    if (length < 12) tips.add('Use at least 12 characters.');
    if (!(hasLower && hasUpper)) tips.add('Mix upper and lower case letters.');
    if (!hasDigit) tips.add('Add some digits.');
    if (!hasSymbol) tips.add('Add a symbol such as ! or #.');
    if (distinct < length * 0.6) tips.add('Avoid repeating the same characters.');

    final StrengthLevel level;
    if (bits < 28) {
      level = StrengthLevel.veryWeak;
    } else if (bits < 36) {
      level = StrengthLevel.weak;
    } else if (bits < 60) {
      level = StrengthLevel.fair;
    } else if (bits < 80) {
      level = StrengthLevel.strong;
    } else {
      level = StrengthLevel.veryStrong;
    }
    return StrengthResult(level, bits, tips);
  }

  /// Characters that go up or down one step at a time ("abcd", "4321") and
  /// runs along a keyboard row ("qwer") are easy to guess.
  static double _sequencePenalty(String lower) {
    var penalty = 0.0;
    var run = 1;
    var step = 0;
    for (var i = 1; i < lower.length; i++) {
      final diff = lower.codeUnitAt(i) - lower.codeUnitAt(i - 1);
      final isStep = diff == 1 || diff == -1;
      if (isStep && (step == 0 || step == diff)) {
        step = diff;
        run++;
      } else {
        if (run >= 3) penalty += run - 2;
        if (isStep) {
          step = diff;
          run = 2;
        } else {
          step = 0;
          run = 1;
        }
      }
    }
    if (run >= 3) penalty += run - 2;

    for (final row in _keyboardRows) {
      for (var i = 0; i + 4 <= row.length; i++) {
        if (lower.contains(row.substring(i, i + 4))) penalty += 2;
      }
    }
    return penalty;
  }
}

/// One line of the "device protection" checklist.
class ChecklistEntry {
  final String title;
  final String detail;
  final bool ok;
  const ChecklistEntry(this.title, this.detail, this.ok);
}

/// The result of looking at the whole vault.
class SecurityReport {
  /// A password older than this many days is flagged.
  static const int oldAfterDays = 180;

  final int passwordCount;
  final List<VaultItem> weak;
  final List<VaultItem> reused;
  final List<VaultItem> old;
  final int score; // 0 to 100
  final List<ChecklistEntry> checklist;

  const SecurityReport({
    required this.passwordCount,
    required this.weak,
    required this.reused,
    required this.old,
    required this.score,
    required this.checklist,
  });

  /// Items that have at least one problem (an item is counted once).
  int get issueCount {
    final ids = <String>{
      for (final item in weak) item.id,
      for (final item in reused) item.id,
      for (final item in old) item.id,
    };
    return ids.length;
  }

  int get deviceIssues => checklist.where((entry) => !entry.ok).length;

  String get verdict {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 55) return 'Fair';
    return 'At risk';
  }

  static SecurityReport analyze(
    List<VaultItem> items, {
    required bool biometricOn,
    required int autoLockSeconds,
    required bool screenshotsBlocked,
    required int clipboardSeconds,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final logins = items
        .where((item) => item.type == 'Password' && item.password.isNotEmpty)
        .toList();

    final weak = logins
        .where((item) => PasswordTools.evaluate(item.password).isWeak)
        .toList();

    final groups = <String, List<VaultItem>>{};
    for (final item in logins) {
      groups.putIfAbsent(item.password, () => <VaultItem>[]).add(item);
    }
    final reused = <VaultItem>[
      for (final group in groups.values)
        if (group.length > 1) ...group,
    ];

    final old = logins
        .where((item) => clock.difference(item.updatedAt).inDays > oldAfterDays)
        .toList();

    // Passwords count for 70 points, device settings for 30.
    double vault = 100;
    final n = logins.length;
    if (n > 0) {
      vault -= 50 * weak.length / n;
      vault -= 30 * reused.length / n;
      vault -= 20 * old.length / n;
    }
    if (vault < 0) vault = 0;

    var device = 0;
    if (biometricOn) device += 25;
    if (autoLockSeconds <= 60) {
      device += 30;
    } else if (autoLockSeconds <= 300) {
      device += 15;
    }
    if (screenshotsBlocked) device += 25;
    device += clipboardSeconds <= 30 ? 20 : 10;

    final score = math.max(0, math.min(100, (vault * 0.7 + device * 0.3).round()));

    final checklist = <ChecklistEntry>[
      ChecklistEntry(
        'Biometric unlock',
        biometricOn
            ? 'Fingerprint or face unlock is on.'
            : 'Turn it on for fast unlocking.',
        biometricOn,
      ),
      ChecklistEntry(
        'Auto-lock',
        autoLockSeconds == 0
            ? 'Locks as soon as you leave the app.'
            : 'Locks after ${secondsLabel(autoLockSeconds).toLowerCase()} away.',
        autoLockSeconds <= 60,
      ),
      ChecklistEntry(
        'Screenshot protection',
        screenshotsBlocked
            ? 'Screenshots and the app switcher preview are blocked.'
            : 'Screenshots are allowed.',
        screenshotsBlocked,
      ),
      ChecklistEntry(
        'Clipboard auto-clear',
        'Copied passwords are cleared after '
            '${secondsLabel(clipboardSeconds).toLowerCase()}.',
        clipboardSeconds <= 30,
      ),
    ];

    return SecurityReport(
      passwordCount: logins.length,
      weak: weak,
      reused: reused,
      old: old,
      score: score,
      checklist: checklist,
    );
  }
}

/// Rules for the Master PIN.
class PinPolicy {
  static const int length = 6;

  static const Set<String> _common = {
    '123456',
    '654321',
    '123123',
    '123321',
    '112233',
    '121212',
    '159753',
    '696969',
    '202020',
    '101010',
    '131313',
    '111222',
    '012345',
    '987654',
  };

  /// Returns null when the PIN is acceptable, otherwise a short message.
  static String? validate(String pin) {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) return 'Use exactly 6 digits.';
    if (pin.split('').toSet().length == 1) {
      return 'Avoid repeating one digit.';
    }
    if (_common.contains(pin)) {
      return 'That PIN is too easy to guess. Pick another one.';
    }
    var ascending = true;
    var descending = true;
    for (var i = 1; i < pin.length; i++) {
      final diff = pin.codeUnitAt(i) - pin.codeUnitAt(i - 1);
      if (diff != 1) ascending = false;
      if (diff != -1) descending = false;
    }
    if (ascending || descending) {
      return 'Avoid simple sequences such as 123456.';
    }
    if (pin.substring(0, 2) * 3 == pin) {
      return 'Avoid repeating patterns such as 121212.';
    }
    return null;
  }
}
