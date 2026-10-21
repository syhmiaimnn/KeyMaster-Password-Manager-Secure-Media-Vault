class VaultItem {
  final String id;
  final String type; // 'Password' or 'Note'
  final String title;
  final String username;
  final String password;
  final String note;
  final DateTime createdAt;

  VaultItem({
    required this.id,
    required this.type,
    required this.title,
    this.username = '',
    this.password = '',
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Convert to JSON for local storage later if needed
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'username': username,
        'password': password,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };
}