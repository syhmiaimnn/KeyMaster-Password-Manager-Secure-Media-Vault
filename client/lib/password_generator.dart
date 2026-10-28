import 'dart:math';

/// Makes random passwords with the operating system's secure random source.
class PasswordGenerator {
  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _digits = '0123456789';
  static const String _symbols = '!@#%^&*()-_=+[]{};:,.?';

  /// Characters that are easy to mix up when reading a password aloud.
  static const String _lookAlikes = 'Il1O0o';

  /// [random] is only for tests, so they can use a fixed seed.
  static String generate({
    int length = 16,
    bool useSymbols = true,
    bool useUppercase = true,
    bool useLowercase = true,
    bool useDigits = true,
    bool avoidLookAlikes = false,
    Random? random,
  }) {
    final rng = random ?? Random.secure();

    String clean(String group) {
      if (!avoidLookAlikes) return group;
      return group.split('').where((c) => !_lookAlikes.contains(c)).join();
    }

    final groups = <String>[
      if (useLowercase) clean(_lower),
      if (useUppercase) clean(_upper),
      if (useDigits) clean(_digits),
      if (useSymbols) clean(_symbols),
    ];
    // Never build a password from an empty alphabet.
    if (groups.isEmpty) groups.add(clean(_lower));

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
