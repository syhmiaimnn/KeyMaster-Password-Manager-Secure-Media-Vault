import 'dart:convert';

class VaultItem {
  final String id;
  final String type; // 'Password', 'Note', or 'Media'
  final String title;
  final String username;
  final String password;
  final String note;
  final String website; // optional, for passwords
  final bool favorite;
  final String mediaPath; // file name of the encrypted photo in the app's private folder
  final String mimeType; // 'image/jpeg' for photos, empty for passwords and notes
  final int sizeBytes; // size of the stored photo, 0 for passwords and notes
  /// This photo's own random 32-byte key. Since Phase 6 it is saved locked
  /// with the key of the photo's folder ("k2." followed by base64). Photos
  /// saved earlier keep the plain base64 key until the vault is first opened
  /// after the update, when it is moved into the first folder.
  final String fileKey;

  /// The id of the folder this photo is in. Empty for other items, and for
  /// photos saved before Phase 6 until they are moved into the first folder.
  final String folderId;

  /// Names of the hidden fields that were removed from this photo (for example
  /// "GPS GPSLatitude" or "#XMP"). Names only, never the values. The photo's
  /// Privacy report is built from this list. Photos saved before Phase 5 have
  /// none.
  final List<String> sanitizedTags;
  final DateTime createdAt;

  /// When the password (or note text) was last changed. It starts equal to
  /// [createdAt]. The Security Center uses it to find old passwords.
  final DateTime updatedAt;

  VaultItem({
    required this.id,
    required this.type,
    required this.title,
    this.username = '',
    this.password = '',
    this.note = '',
    this.website = '',
    this.favorite = false,
    this.mediaPath = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.fileKey = '',
    this.folderId = '',
    this.sanitizedTags = const <String>[],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  bool get isPhoto => type == 'Media' && mimeType.startsWith('image/');
  bool get isPassword => type == 'Password';
  bool get isNote => type == 'Note';

  VaultItem copyWith({
    String? title,
    String? username,
    String? password,
    String? note,
    String? website,
    bool? favorite,
    String? fileKey,
    String? folderId,
    DateTime? updatedAt,
  }) {
    return VaultItem(
      id: id,
      type: type,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      note: note ?? this.note,
      website: website ?? this.website,
      favorite: favorite ?? this.favorite,
      mediaPath: mediaPath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      fileKey: fileKey ?? this.fileKey,
      folderId: folderId ?? this.folderId,
      sanitizedTags: sanitizedTags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'username': username,
        'password': password,
        'note': note,
        'website': website,
        'favorite': favorite,
        'mediaPath': mediaPath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'fileKey': fileKey,
        'folderId': folderId,
        'sanitizedTags': sanitizedTags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    final created = DateTime.parse(json['createdAt'] as String);
    final updatedText = json['updatedAt'] as String?;
    final tagsJson = json['sanitizedTags'];
    return VaultItem(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      note: json['note'] as String? ?? '',
      website: json['website'] as String? ?? '',
      favorite: json['favorite'] as bool? ?? false,
      mediaPath: json['mediaPath'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      fileKey: json['fileKey'] as String? ?? '',
      // Records saved before Phase 6 have no folder.
      folderId: json['folderId'] as String? ?? '',
      // Records saved before Phase 5 have no list.
      sanitizedTags: tagsJson is List
          ? tagsJson.whereType<String>().toList()
          : const <String>[],
      createdAt: created,
      // Records saved before Phase 3 have no updatedAt: use the creation date.
      updatedAt: updatedText == null ? created : DateTime.parse(updatedText),
    );
  }

  static String serializeList(List<VaultItem> items) {
    return jsonEncode(items.map((item) => item.toJson()).toList());
  }

  static List<VaultItem> deserializeList(String jsonString) {
    if (jsonString.isEmpty) return [];
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((json) => VaultItem.fromJson(json)).toList();
  }
}
