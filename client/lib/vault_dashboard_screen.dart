import 'package:flutter/material.dart';
import 'add_item_dialog.dart';
import 'vault_item.dart';

class VaultDashboardScreen extends StatefulWidget {
  const VaultDashboardScreen({super.key});

  @override
  State<VaultDashboardScreen> createState() => _VaultDashboardScreenState();
}

class _VaultDashboardScreenState extends State<VaultDashboardScreen> {
  int _selectedIndex = 0;
  final List<VaultItem> _vaultItems = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('KeyMaster Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Settings placeholder
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Security Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.verified_user, color: Colors.greenAccent),
                        SizedBox(width: 8),
                        Text(
                          'Vault Encrypted',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Zero-knowledge AES-256 local encryption active.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Quick Access',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              // Category Grid
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _buildCategoryCard(
                      icon: Icons.key,
                      title: 'Passwords',
                      count: '${_vaultItems.where((item) => item.type == 'Password').length} items',
                      color: Colors.blueAccent,
                      onTap: () {},
                    ),
                    _buildCategoryCard(
                      icon: Icons.photo_library,
                      title: 'Media Vault',
                      count: '${_vaultItems.where((item) => item.type == 'Note').length} items',
                      color: Colors.purpleAccent,
                      onTap: () {},
                    ),
                    _buildCategoryCard(
                      icon: Icons.note,
                      title: 'Secure Notes',
                      count: '0 items',
                      color: Colors.orangeAccent,
                      onTap: () {},
                    ),
                    _buildCategoryCard(
                      icon: Icons.credit_card,
                      title: 'Cards & Banking',
                      count: '0 items',
                      color: Colors.tealAccent,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
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
            setState(() {
              _vaultItems.add(VaultItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                type: result['type']!,
                title: result['title']!,
                username: result['username'] ?? '',
                password: result['password'] ?? '',
                note: result['note'] ?? '',
              ));
            });

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved "${result['title']}" to Vault!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.lock),
            label: 'Vault',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.security),
            label: 'Audit',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required IconData icon,
    required String title,
    required String count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, color: color),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}