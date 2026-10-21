import 'dart:convert';

class VaultItem {
  final String id;
  final String type; // 'Password', 'Note', or 'Media'
  final String title;
  final String username;
  final String password;
  final String note;
  final String mediaPath; // Path to securely stored photo/document
  final DateTime createdAt;

  VaultItem({
    required this.id,
    required this.type,
    required this.title,
    this.username = '',
    this.password = '',
    this.note = '',
    this.mediaPath = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'username': username,
        'password': password,
        'note': note,
        'mediaPath': mediaPath,
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