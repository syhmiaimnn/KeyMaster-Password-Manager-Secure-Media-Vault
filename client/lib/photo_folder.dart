import 'dart:convert';
import 'dart:typed_data';

/// A folder of photos with its own key (report section 3.4.2).
///
/// The folder key is a random 32-byte key. It locks the keys of the photos in
/// the folder (see key_tree.dart). The folder record is saved inside the
/// encrypted vault data, so the vault key protects the folder key.
class PhotoFolder {
  static const int maxNameLength = 40;

  /// How many folder colours the app offers.
  static const int colorCount = 6;

  final String id;
  final String name;

  /// This folder's own random 32-byte key, as base64.
  final String key;

  /// When true, the app asks for the Master PIN before it opens the folder.
  /// This is an extra check in the app. The key itself is still protected by
  /// the vault key, which is in memory while the vault is open.
  final bool requiresPin;

  /// Which folder colour to use (0 to [colorCount] - 1).
  final int colorIndex;

  final DateTime createdAt;

  PhotoFolder({
    required this.id,
    required this.name,
    required this.key,
    this.requiresPin = false,
    this.colorIndex = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// The key as bytes, ready to use for wrapping photo keys.
  Uint8List get keyBytes => base64Decode(key);

  PhotoFolder copyWith({String? name, bool? requiresPin, int? colorIndex}) {
    return PhotoFolder(
      id: id,
      name: name ?? this.name,
      key: key,
      requiresPin: requiresPin ?? this.requiresPin,
      colorIndex: colorIndex ?? this.colorIndex,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': key,
        'requiresPin': requiresPin,
        'colorIndex': colorIndex,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PhotoFolder.fromJson(Map<String, dynamic> json) {
    final colorValue = (json['colorIndex'] as num?)?.toInt() ?? 0;
    return PhotoFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      key: json['key'] as String,
      requiresPin: json['requiresPin'] as bool? ?? false,
      colorIndex: colorValue.abs() % colorCount,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Returns a sentence that says what is wrong with [raw] as a folder name,
  /// or null when the name is fine. [others] are the other folders, because two
  /// folders may not share a name.
  static String? validateName(String raw, Iterable<PhotoFolder> others) {
    final name = raw.trim();
    if (name.isEmpty) return 'Give the folder a name.';
    if (name.length > maxNameLength) {
      return 'Use at most $maxNameLength characters.';
    }
    final lower = name.toLowerCase();
    for (final other in others) {
      if (other.name.trim().toLowerCase() == lower) {
        return 'A folder with this name already exists.';
      }
    }
    return null;
  }
}
