import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'add_item_dialog.dart';
import 'security_service.dart';
import 'vault_item.dart';

class VaultDashboardScreen extends StatefulWidget {
  const VaultDashboardScreen({super.key});

  @override
  State<VaultDashboardScreen> createState() => _VaultDashboardScreenState();
}

class _VaultDashboardScreenState extends State<VaultDashboardScreen> {
  final SecurityService _securityService = SecurityService();
  List<VaultItem> _vaultItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItemsFromStorage();
  }

  Future<void> _loadItemsFromStorage() async {
    final items = await _securityService.loadVaultItems();
    setState(() {
      _vaultItems = items;
      _isLoading = false;
    });
  }

  Future<void> _addItem(VaultItem item) async {
    setState(() {
      _vaultItems.add(item);
    });
    await _securityService.saveVaultItems(_vaultItems);
  }

  Future<void> _deleteItem(String id) async {
    setState(() {
      _vaultItems.removeWhere((item) => item.id == id);
    });
    await _securityService.saveVaultItems(_vaultItems);
  }

void _showItemDetails(VaultItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        bool showPassword = false;
        // 👉 MUST BE StatefulBuilder HERE:
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                // ... rest of your modal code
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          Navigator.pop(context);
                          await _deleteItem(item.id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Deleted "${item.title}"')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 12),
                  if (item.type == 'Password') ...[
                    if (item.username.isNotEmpty) ...[
                      const Text('Username / Email', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(item.username, style: const TextStyle(color: Colors.white, fontSize: 16)),
                          IconButton(
                            icon: const Icon(Icons.copy, color: Colors.blueAccent, size: 20),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: item.username));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Username copied to clipboard!')),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (item.password.isNotEmpty) ...[
                      const Text('Password', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            showPassword ? item.password : '••••••••••••',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  showPassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setModalState(() {
                                    showPassword = !showPassword;
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, color: Colors.blueAccent, size: 20),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: item.password));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Password copied to clipboard!')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    const Text('Secure Note', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(item.note, style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int passwordCount = _vaultItems.where((i) => i.type == 'Password').length;
    int noteCount = _vaultItems.where((i) => i.type == 'Note').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KeyMaster Vault'),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildCategoryCard(
                          title: 'Passwords',
                          count: '$passwordCount items',
                          icon: Icons.key,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCategoryCard(
                          title: 'Notes',
                          count: '$noteCount items',
                          icon: Icons.note,
                          color: Colors.purpleAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'All Entries',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _vaultItems.isEmpty
                        ? const Center(
                            child: Text('No items added yet.', style: TextStyle(color: Colors.grey)),
                          )
                        : ListView.builder(
                            itemCount: _vaultItems.length,
                            itemBuilder: (context, index) {
                              final item = _vaultItems[index];
                              return Card(
                                color: const Color(0xFF1E1E1E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: item.type == 'Password' ? Colors.blueAccent : Colors.purpleAccent,
                                    child: Icon(
                                      item.type == 'Password' ? Icons.key : Icons.note,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(item.title, style: const TextStyle(color: Colors.white)),
                                  subtitle: Text(
                                    item.type == 'Password' ? item.username : item.note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                                  onTap: () => _showItemDetails(item),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        onPressed: () async {
          final result = await showModalBottomSheet<Map<String, String>>(
            context: context,
            isScrollControlled: true,
            backgroundColor: const Color(0xFF1E1E1E),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => const AddItemDialog(),
          );

          if (result != null && result['title'] != null && result['title']!.isNotEmpty) {
            final newItem = VaultItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: result['type']!,
              title: result['title']!,
              username: result['username'] ?? '',
              password: result['password'] ?? '',
              note: result['note'] ?? '',
            );

            await _addItem(newItem);

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved "${newItem.title}" securely!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(count, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}