import 'package:flutter/material.dart';
import 'security_service.dart';
import 'vault_dashboard_screen.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  String? _errorMessage;

void _handlePinSubmit() async {
    String pin = _pinController.text.trim();
    String confirmPin = _confirmPinController.text.trim();

    if (pin.length < 6) {
      setState(() {
        _errorMessage = 'PIN must be at least 6 digits long.';
      });
      return;
    }

    if (pin != confirmPin) {
      setState(() {
        _errorMessage = 'PINs do not match. Please try again.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    // Save PIN securely to storage
    final securityService = SecurityService();
    await securityService.savePin(pin);

    if (!mounted) return;

    // Navigate straight to Vault Dashboard
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const VaultDashboardScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Master PIN'),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create Your Master PIN',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'This Master PIN encrypts your local vault key. Keep it safe—it cannot be recovered if lost.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                decoration: InputDecoration(
                  labelText: 'Enter 6-Digit PIN',
                  labelStyle: const TextStyle(color: Colors.grey, letterSpacing: 0, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                decoration: InputDecoration(
                  labelText: 'Confirm 6-Digit PIN',
                  labelStyle: const TextStyle(color: Colors.grey, letterSpacing: 0, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
              ],
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _handlePinSubmit,
                child: const Text('Save Master PIN', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}