import 'dart:convert';

import 'photo_folder.dart';
import 'vault_item.dart';

/// Everything that is saved, encrypted, under the vault key: the items
/// (passwords, notes, photo records) and the photo folders.
///
/// They are saved together in ONE value on purpose. A photo record holds a key
/// that only its folder can open, so the two must never be saved out of step.
///
/// Before Phase 6 the saved text was just a list of items. [deserialize] still
/// reads that, so an existing vault opens as before.
class VaultData {
  final List<VaultItem> items;
  final List<PhotoFolder> folders;

  const VaultData(this.items, this.folders);

  static const VaultData empty = VaultData(<VaultItem>[], <PhotoFolder>[]);

  String serialize() {
    return jsonEncode({
      'v': 2,
      'items': items.map((item) => item.toJson()).toList(),
      'folders': folders.map((folder) => folder.toJson()).toList(),
    });
  }

  /// Reads the saved text. Throws [FormatException] if it is not vault data.
  static VaultData deserialize(String text) {
    if (text.isEmpty) return empty;
    final Object? decoded = jsonDecode(text);

    // Saved by Phase 5 or earlier: a plain list of items, no folders.
    if (decoded is List) {
      return VaultData(_itemsFrom(decoded), const <PhotoFolder>[]);
    }

    if (decoded is Map<String, dynamic>) {
      final items = decoded['items'];
      final folders = decoded['folders'];
      return VaultData(
        items is List ? _itemsFrom(items) : <VaultItem>[],
        folders is List ? _foldersFrom(folders) : <PhotoFolder>[],
      );
    }

    throw const FormatException('The vault data has an unknown format.');
  }

  static List<VaultItem> _itemsFrom(List<dynamic> list) {
    return list
        .map((json) => VaultItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  static List<PhotoFolder> _foldersFrom(List<dynamic> list) {
    return list
        .map((json) => PhotoFolder.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
