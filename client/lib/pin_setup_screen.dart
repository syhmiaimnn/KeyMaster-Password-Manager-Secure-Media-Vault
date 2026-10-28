import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'home_shell.dart';
import 'password_tools.dart';
import 'security_service.dart';
import 'ui/pin_entry.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_store.dart';

enum _Stage { create, confirm }

/// First run: the user picks a 6-digit Master PIN on a keypad and repeats it.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final GlobalKey<PinEntryState> _pad = GlobalKey<PinEntryState>();

  _Stage _stage = _Stage.create;
  String _firstPin = '';
  String? _problem;
  bool _biometricSupported = false;
  bool _useBiometric = true;
  bool _working = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final supported = await SecurityService().isBiometricSupported();
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _useBiometric = supported;
    });
  }

  Future<void> _onPin(String pin) async {
    if (_working) return;

    if (_stage == _Stage.create) {
      final problem = PinPolicy.validate(pin);
      if (problem != null) {
        setState(() => _problem = problem);
        unawaited(_pad.currentState?.showError());
        return;
      }
      setState(() {
        _firstPin = pin;
        _stage = _Stage.confirm;
        _problem = null;
      });
      _pad.currentState?.clear();
      return;
    }

    if (pin != _firstPin) {
      setState(() {
        _problem = 'The two PINs did not match. Please start again.';
        _stage = _Stage.create;
        _firstPin = '';
      });
      unawaited(_pad.currentState?.showError());
      return;
    }
    await _createVault(pin);
  }

  Future<void> _createVault(String pin) async {
    setState(() {
      _working = true;
      _problem = null;
    });
    try {
      // Creates the vault key, wraps it with the PIN and leaves it unlocked.
      await SecurityService().setupVault(
        pin,
        enableBiometrics: _useBiometric && _biometricSupported,
      );
      await VaultStore.instance.load(force: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _stage = _Stage.create;
        _firstPin = '';
        _problem = 'Could not create the vault. Please try again.';
      });
      _pad.currentState?.clear();
      return;
    }
    if (!mounted) return;
    AppSettings.instance.recordUnlock();
    setState(() {
      _working = false;
      _done = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute<void>(const HomeShell()),
      (route) => false,
    );
  }

  void _goBack() {
    setState(() {
      _stage = _Stage.create;
      _firstPin = '';
      _problem = null;
    });
    _pad.currentState?.clear();
  }

  Widget _header(Palette p) {
    final confirm = _stage == _Stage.confirm;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Column(
        key: ValueKey<_Stage>(_stage),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: p.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              confirm ? 'STEP 2 OF 2' : 'STEP 1 OF 2',
              style: AppText.overline.copyWith(color: p.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            confirm ? 'Confirm your PIN' : 'Create your Master PIN',
            textAlign: TextAlign.center,
            style: AppText.display.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 10),
          Text(
            confirm
                ? 'Enter the same six digits once more.'
                : 'Six digits that open everything. It cannot be recovered '
                    'if you forget it, so choose one you will remember.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: p.muted),
          ),
        ],
      ),
    );
  }

  Widget _doneView(Palette p) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutBack,
        builder: (context, t, child) {
          final opacity = t > 1 ? 1.0 : (t < 0 ? 0.0 : t);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [p.success, p.accent]),
                boxShadow: [
                  BoxShadow(color: p.success.withAlpha(110), blurRadius: 40),
                ],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
            ),
            const SizedBox(height: 24),
            const Text('Your vault is ready', style: AppText.display),
            const SizedBox(height: 10),
            Text(
              'Encrypted and stored only on this phone.',
              style: AppText.body.copyWith(color: p.muted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: _done
              ? _doneView(p)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _stage == _Stage.confirm && !_working
                              ? IconButton(
                                  onPressed: _goBack,
                                  icon: Icon(Icons.arrow_back_rounded, color: p.text),
                                )
                              : null,
                        ),
                      ),
                      _header(p),
                      const SizedBox(height: 28),
                      PinEntry(
                        key: _pad,
                        enabled: !_working,
                        onCompleted: _onPin,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 40,
                        child: Center(
                          child: _working
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Securing your vault with Argon2id...',
                                      style: AppText.caption.copyWith(color: p.muted),
                                    ),
                                  ],
                                )
                              : _problem != null
                                  ? Text(
                                      _problem!,
                                      textAlign: TextAlign.center,
                                      style: AppText.caption.copyWith(
                                        color: p.danger,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                        ),
                      ),
                      if (_biometricSupported && _stage == _Stage.create) ...[
                        const SizedBox(height: 8),
                        AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              IconBadge(
                                icon: Icons.fingerprint_rounded,
                                color: p.accent,
                                size: 40,
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Text(
                                  'Unlock with biometrics',
                                  style: AppText.subtitle,
                                ),
                              ),
                              Switch(
                                value: _useBiometric,
                                onChanged: (value) =>
                                    setState(() => _useBiometric = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
