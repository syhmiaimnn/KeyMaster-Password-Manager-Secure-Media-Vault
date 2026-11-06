import 'dart:convert';
import 'dart:typed_data';

// The two vaults, and the small pieces that make them look alike on disk.
//
// KeyMaster always keeps TWO vault slots, whether or not a decoy PIN is set.
//
//   real  - the vault you use every day. It keeps the storage names that
//           earlier phases already used, so an existing vault needs no move.
//   decoy - a second vault with its own key, its own items and its own photo
//           folder. A second PIN opens it.
//
// When no decoy PIN is set, the second slot holds random bytes in exactly the
// same shape as a real one. Someone who looks inside the phone storage then
// sees the same two entries with or without a decoy, and cannot tell which
// case it is (report test 8). This file holds only the parts that do not need
// Flutter, so they are easy to test.

/// Which of the two vaults is open.
enum VaultSlot {
  real('vault_wrapped_key', 'vault_items_encrypted', 'media_vault'),
  decoy('vault2_wrapped_key', 'vault2_items_encrypted', 'media_vault_2');

  /// Storage name of the vault key wrapped with this slot's PIN.
  final String wrapKey;

  /// Storage name of the encrypted items and folders.
  final String itemsKey;

  /// Name of the folder that holds this slot's encrypted photos.
  final String mediaDir;

  const VaultSlot(this.wrapKey, this.itemsKey, this.mediaDir);

  bool get isDecoy => this == VaultSlot.decoy;
}

/// How a wrapped vault key is written in storage: "v2.<salt>.<wrapped key>".
/// One value means one write, so a crash can never leave a new salt next to an
/// old wrapped key. (Phases 0 to 2 used two values. See security_service.dart.)
class WrapFormat {
  const WrapFormat._();

  static const String prefix = 'v2';

  /// Salt length in bytes.
  static const int saltBytes = 16;

  /// Wrapped key length in bytes: 12 nonce + 32 key + 16 tag.
  static const int wrappedBytes = 60;

  static String encode(Uint8List salt, String wrapped) =>
      '$prefix.${base64Encode(salt)}.$wrapped';

  /// Returns null when [stored] is not in this format.
  static ({Uint8List salt, String wrapped})? decode(String stored) {
    if (!stored.startsWith('$prefix.')) return null;
    final parts = stored.split('.');
    if (parts.length != 3) return null;
    try {
      return (salt: base64Decode(parts[1]), wrapped: parts[2]);
    } on FormatException {
      return null;
    }
  }
}

/// Random bytes that look like a real slot. [random] makes secure random
/// bytes of the length it is given.
class SlotFiller {
  const SlotFiller._();

  /// Item lists differ in size from vault to vault, so the filler does too.
  static const int minItemsBytes = 1200;
  static const int itemsSpread = 1800;

  /// A wrapped key that opens with no PIN at all, in the real format.
  static String wrap(Uint8List Function(int length) random) {
    return WrapFormat.encode(
      random(WrapFormat.saltBytes),
      base64Encode(random(WrapFormat.wrappedBytes)),
    );
  }

  /// An item list that opens with no key at all.
  static String items(Uint8List Function(int length) random) {
    final pick = random(2);
    final extra = ((pick[0] << 8) | pick[1]) % itemsSpread;
    return base64Encode(random(minItemsBytes + extra));
  }
}

/// What the real vault remembers about the second slot. It is saved encrypted
/// under the REAL vault key, so only a real session can read it.
///
/// It always has the same length. When there is no decoy the key is random,
/// so the saved value looks the same either way.
class SlotFlags {
  final bool decoyOn;

  /// The decoy vault key (32 bytes). Random when [decoyOn] is false. Keeping
  /// it here lets the real vault change the decoy PIN without losing the decoy
  /// items.
  final Uint8List decoyKey;

  const SlotFlags(this.decoyOn, this.decoyKey);

  String serialize() {
    return jsonEncode({'d': decoyOn ? 1 : 0, 'k': base64Encode(decoyKey)});
  }

  /// Throws [FormatException] if [text] is not a flags value.
  static SlotFlags parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The slot flags have an unknown format.');
    }
    final on = decoded['d'];
    final key = decoded['k'];
    if (on is! int || key is! String) {
      throw const FormatException('The slot flags have an unknown format.');
    }
    final bytes = base64Decode(key);
    if (bytes.length != 32) {
      throw const FormatException('The slot flags hold a key of the wrong size.');
    }
    return SlotFlags(on == 1, bytes);
  }
}
