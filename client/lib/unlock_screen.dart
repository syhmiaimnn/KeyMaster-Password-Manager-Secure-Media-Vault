import 'package:flutter/material.dart';
import 'security_service.dart';
import 'vault_dashboard_screen.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final SecurityService _securityService = SecurityService();
  final TextEditingController _pinController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Automatically trigger biometrics prompt when screen loads
    _attemptBiometricAuth();
  }

  Future<void> _attemptBiometricAuth() async {
    bool isAuthenticated = await _securityService.authenticateWithBiometrics();
    if (isAuthenticated && mounted) {
      _navigateToDashboard();
    }
  }

  void _verifyPin() async {
    String enteredPin = _pinController.text.trim();
    bool isValid = await _securityService.verifyPin(enteredPin);

    if (!mounted) return;

    if (isValid) {
      _navigateToDashboard();
    } else {
      setState(() {
        _errorMessage = 'Incorrect Master PIN. Try again.';
      });
    }
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const VaultDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 20),
              const Text(
                'KeyMaster Locked',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Authenticate with biometrics or enter your Master PIN',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Master PIN',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  counterText: '',
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _verifyPin,
                child: const Text('Unlock Vault', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _attemptBiometricAuth,
                icon: const Icon(Icons.fingerprint, color: Colors.blueAccent),
                label: const Text('Use Biometrics', style: TextStyle(color: Colors.blueAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}