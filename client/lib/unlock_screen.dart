import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isWorking = false;
  bool _biometricEnabled = false;
  Duration _lockLeft = Duration.zero;
  Timer? _timer;

  bool get _isLocked => _lockLeft > Duration.zero;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final wait = await _securityService.lockoutRemaining();
    final biometric = await _securityService.isBiometricEnabled();
    if (!mounted) return;
    setState(() => _biometricEnabled = biometric);
    _startCountdown(wait);
    // Show the fingerprint prompt automatically when the screen opens
    if (biometric) _attemptBiometricAuth();
  }

  void _startCountdown(Duration wait) {
    _timer?.cancel();
    setState(() => _lockLeft = wait);
    if (wait <= Duration.zero) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = _lockLeft - const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        timer.cancel();
        setState(() {
          _lockLeft = Duration.zero;
          _errorMessage = null;
        });
      } else {
        setState(() => _lockLeft = remaining);
      }
    });
  }

  String _formatWait(Duration d) {
    final totalSeconds = (d.inMilliseconds / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
  }

  Future<void> _attemptBiometricAuth() async {
    final ok = await _securityService.authenticateWithBiometrics();
    if (ok && mounted) _navigateToDashboard();
  }

  Future<void> _verifyPin() async {
    if (_isWorking || _isLocked) return;
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    final result = await _securityService.unlockWithPin(pin);
    if (!mounted) return;
    setState(() => _isWorking = false);

    switch (result.status) {
      case UnlockStatus.success:
        _navigateToDashboard();
      case UnlockStatus.wrongPin:
        _pinController.clear();
        setState(() {
          _errorMessage =
              'Incorrect Master PIN. Attempts left before a lockout: ${result.attemptsLeft}.';
        });
      case UnlockStatus.lockedOut:
        _pinController.clear();
        setState(() => _errorMessage = 'Too many wrong PINs.');
        _startCountdown(result.wait);
    }
  }

  void _navigateToDashboard() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const VaultDashboardScreen()),
      (route) => false,
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
              Icon(
                _isLocked ? Icons.lock_clock : Icons.lock_outline,
                size: 80,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 20),
              const Text(
                'KeyMaster Locked',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                _biometricEnabled
                    ? 'Authenticate with biometrics or enter your Master PIN'
                    : 'Enter your Master PIN',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pinController,
                enabled: !_isLocked && !_isWorking,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                onSubmitted: (_) => _verifyPin(),
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
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
              if (_isLocked) ...[
                const SizedBox(height: 8),
                Text(
                  'Locked. Try again in ${_formatWait(_lockLeft)}',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 14),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _verifyPin,
                child: _isWorking
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isLocked ? 'Locked' : 'Unlock Vault',
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
              ),
              if (_biometricEnabled) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _attemptBiometricAuth,
                  icon: const Icon(Icons.fingerprint, color: Colors.blueAccent),
                  label: const Text('Use Biometrics', style: TextStyle(color: Colors.blueAccent)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}