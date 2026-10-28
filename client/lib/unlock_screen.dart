import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'home_shell.dart';
import 'security_service.dart';
import 'ui/format.dart';
import 'ui/pin_entry.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final SecurityService _security = SecurityService();
  final GlobalKey<PinEntryState> _pad = GlobalKey<PinEntryState>();

  String? _message;
  bool _working = false;
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
    super.dispose();
  }

  Future<void> _prepare() async {
    final wait = await _security.lockoutRemaining();
    final biometric = await _security.isBiometricEnabled();
    if (!mounted) return;
    setState(() => _biometricEnabled = biometric);
    _startCountdown(wait);
    // Show the fingerprint prompt automatically when the screen opens
    if (biometric) _tryBiometric();
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
          _message = null;
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
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _tryBiometric() async {
    final ok = await _security.authenticateWithBiometrics();
    if (ok && mounted) _enter();
  }

  Future<void> _onPin(String pin) async {
    if (_working || _isLocked) return;
    setState(() {
      _working = true;
      _message = null;
    });
    final result = await _security.unlockWithPin(pin);
    if (!mounted) return;
    setState(() => _working = false);

    switch (result.status) {
      case UnlockStatus.success:
        _enter();
      case UnlockStatus.wrongPin:
        unawaited(_pad.currentState?.showError());
        final left = result.attemptsLeft;
        setState(() {
          _message = left > 0
              ? 'Incorrect PIN. $left ${left == 1 ? 'try' : 'tries'} left '
                  'before a lockout.'
              : 'Incorrect PIN.';
        });
      case UnlockStatus.lockedOut:
        unawaited(_pad.currentState?.showError());
        setState(() => _message = 'Too many wrong PINs.');
        _startCountdown(result.wait);
    }
  }

  void _enter() {
    AppSettings.instance.recordUnlock();
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute<void>(const HomeShell()),
      (route) => false,
    );
  }

  Widget _status(Palette p) {
    if (_isLocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: p.warning.withAlpha(28),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.warning.withAlpha(90)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, color: p.warning, size: 22),
            const SizedBox(width: 10),
            Text(
              'Try again in ${_formatWait(_lockLeft)}',
              style: TextStyle(
                color: p.warning,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }
    if (_message != null) {
      return Text(
        _message!,
        textAlign: TextAlign.center,
        style: AppText.caption.copyWith(
          color: p.danger,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final compact = MediaQuery.sizeOf(context).height < 680;

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(size: compact ? 56 : 72),
                  SizedBox(height: compact ? 14 : 22),
                  Text(
                    greeting(),
                    style: AppText.overline.copyWith(color: p.muted),
                  ),
                  const SizedBox(height: 6),
                  const Text('Welcome back', style: AppText.display),
                  const SizedBox(height: 8),
                  Text(
                    _biometricEnabled
                        ? 'Use biometrics or enter your Master PIN'
                        : 'Enter your Master PIN',
                    style: AppText.body.copyWith(color: p.muted),
                  ),
                  SizedBox(height: compact ? 22 : 34),
                  PinEntry(
                    key: _pad,
                    enabled: !_working && !_isLocked,
                    onCompleted: _onPin,
                    leading: _biometricEnabled
                        ? InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _tryBiometric,
                            child: Center(
                              child: Icon(
                                Icons.fingerprint_rounded,
                                color: p.accent,
                                size: 34,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: _working
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : _status(p),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
