import 'package:flutter/material.dart';
import 'password_generator.dart';

class AddItemDialog extends StatefulWidget {
  const AddItemDialog({super.key});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  String _itemType = 'Password';
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _noteController = TextEditingController();
  bool _obscurePassword = true;
  double _passwordLength = 16;
  bool _useSymbols = true;

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _generatePassword() {
    final password = PasswordGenerator.generate(
      length: _passwordLength.round(),
      useSymbols: _useSymbols,
    );

    setState(() {
      _passwordController.text = password;
      _obscurePassword = false; // show it so the user can see what was made
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add New Item',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'Password',
                  label: Text('Password'),
                  icon: Icon(Icons.key),
                ),
                ButtonSegment(
                  value: 'Note',
                  label: Text('Secure Note'),
                  icon: Icon(Icons.note),
                ),
              ],
              selected: {_itemType},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _itemType = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Title / Service (e.g. Google, Bank)',
                labelStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            if (_itemType == 'Password') ...[
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Username / Email',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Generate Password Button
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.blueAccent),
                        tooltip: 'Generate Strong Password',
                        onPressed: _generatePassword,
                      ),
                      // Toggle visibility
                      IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Length: ${_passwordLength.round()}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  Expanded(
                    child: Slider(
                      value: _passwordLength,
                      min: 8,
                      max: 32,
                      divisions: 24,
                      label: _passwordLength.round().toString(),
                      onChanged: (value) => setState(() => _passwordLength = value),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _useSymbols,
                onChanged: (value) => setState(() => _useSymbols = value),
                title: const Text(
                  'Include symbols (!@#%...)',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ] else ...[
              TextField(
                controller: _noteController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Secret Note Content',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context, {
                  'type': _itemType,
                  'title': _titleController.text,
                  'username': _usernameController.text,
                  'password': _passwordController.text,
                  'note': _noteController.text,
                });
              },
              child: const Text('Save to Vault', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}