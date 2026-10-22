import 'dart:math';

/// Makes random passwords with the operating system's secure random source.
class PasswordGenerator {
  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _digits = '0123456789';
  static const String _symbols = '!@#%^&*()-_=+[]{};:,.?';

  /// [random] is only for tests, so they can use a fixed seed.
  static String generate({
    int length = 16,
    bool useSymbols = true,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final groups = <String>[_lower, _upper, _digits, if (useSymbols) _symbols];
    final all = groups.join();
    final safeLength = length < groups.length ? groups.length : length;

    // One character from every group, so each type is always present
    final chars = <String>[
      for (final group in groups) group[rng.nextInt(group.length)],
    ];

    // Fill the rest from all groups together
    while (chars.length < safeLength) {
      chars.add(all[rng.nextInt(all.length)]);
    }

    // Shuffle (Fisher-Yates) so the guaranteed characters are not always first
    for (var i = chars.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final temp = chars[i];
      chars[i] = chars[j];
      chars[j] = temp;
    }
    return chars.join();
  }
}