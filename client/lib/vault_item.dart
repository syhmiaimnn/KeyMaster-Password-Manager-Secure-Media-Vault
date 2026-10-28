import 'dart:convert';

class VaultItem {
  final String id;
  final String type; // 'Password', 'Note', or 'Media'
  final String title;
  final String username;
  final String password;
  final String note;
  final String mediaPath; // file name of the encrypted photo in the app's private folder
  final String mimeType; // 'image/jpeg' for photos, empty for passwords and notes
  final int sizeBytes; // size of the stored photo, 0 for passwords and notes
  final String fileKey; // this photo's own random 32-byte key, as base64
  final DateTime createdAt;

  VaultItem({
    required this.id,
    required this.type,
    required this.title,
    this.username = '',
    this.password = '',
    this.note = '',
    this.mediaPath = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.fileKey = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isPhoto => type == 'Media' && mimeType.startsWith('image/');

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'username': username,
        'password': password,
        'note': note,
        'mediaPath': mediaPath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'fileKey': fileKey,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) => VaultItem(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        note: json['note'] as String? ?? '',
        mediaPath: json['mediaPath'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? '',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        fileKey: json['fileKey'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  static String serializeList(List<VaultItem> items) {
    return jsonEncode(items.map((item) => item.toJson()).toList());
  }

  static List<VaultItem> deserializeList(String jsonString) {
    if (jsonString.isEmpty) return [];
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((json) => VaultItem.fromJson(json)).toList();
  }
}