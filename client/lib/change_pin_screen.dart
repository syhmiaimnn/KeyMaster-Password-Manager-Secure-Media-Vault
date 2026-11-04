import 'dart:async';

import 'package:flutter/material.dart';

import 'password_tools.dart';
import 'security_service.dart';
import 'ui/pin_entry.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

enum _Step { current, fresh, confirm }

/// Change the Master PIN: current PIN, new PIN, new PIN again.
/// Your passwords and photos are not re-encrypted, only the key that
/// protects them is wrapped again with the new PIN.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final SecurityService _security = SecurityService();
  final GlobalKey<PinEntryState> _pad = GlobalKey<PinEntryState>();

  _Step _step = _Step.current;
  String _currentPin = '';
  String _newPin = '';
  String? _problem;
  bool _working = false;
  bool _blocked = false;

  String get _title {
    switch (_step) {
      case _Step.current:
        return 'Enter your current PIN';
      case _Step.fresh:
        return 'Choose a new PIN';
      case _Step.confirm:
        return 'Confirm the new PIN';
    }
  }

  String get _subtitle {
    switch (_step) {
      case _Step.current:
        return 'We need to be sure it is you.';
      case _Step.fresh:
        return 'Six digits. Avoid dates and simple patterns.';
      case _Step.confirm:
        return 'Enter the new PIN once more.';
    }
  }

  Future<void> _onPin(String pin) async {
    if (_working || _blocked) return;

    switch (_step) {
      case _Step.current:
        await _checkCurrent(pin);
      case _Step.fresh:
        final problem = PinPolicy.validate(pin);
        if (problem != null) {
          setState(() => _problem = problem);
          unawaited(_pad.currentState?.showError());
        } else if (pin == _currentPin) {
          setState(() => _problem = 'Choose a PIN that is different from the old one.');
          unawaited(_pad.currentState?.showError());
        } else {
          setState(() {
            _newPin = pin;
            _step = _Step.confirm;
            _problem = null;
          });
          _pad.currentState?.clear();
        }
      case _Step.confirm:
        if (pin != _newPin) {
          setState(() {
            _problem = 'The two PINs did not match. Choose again.';
            _step = _Step.fresh;
            _newPin = '';
          });
          unawaited(_pad.currentState?.showError());
        } else {
          await _apply(pin);
        }
    }
  }

  Future<void> _checkCurrent(String pin) async {
    setState(() {
      _working = true;
      _problem = null;
    });
    final result = await _security.verifyPin(pin);
    if (!mounted) return;
    setState(() => _working = false);

    switch (result.status) {
      case UnlockStatus.success:
        setState(() {
          _currentPin = pin;
          _step = _Step.fresh;
        });
        _pad.currentState?.clear();
      case UnlockStatus.wrongPin:
        unawaited(_pad.currentState?.showError());
        setState(() => _problem = 'That is not your current PIN.');
      case UnlockStatus.lockedOut:
        unawaited(_pad.currentState?.showError());
        setState(() {
          _blocked = true;
          _problem = 'Too many wrong PINs. Try again in '
              '${(result.wait.inSeconds / 60).ceil()} min.';
        });
    }
  }

  Future<void> _apply(String pin) async {
    setState(() {
      _working = true;
      _problem = null;
    });
    UnlockResult result;
    try {
      result = await _security.changePin(_currentPin, pin);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _problem = 'The PIN could not be changed. Nothing was modified.';
        _step = _Step.fresh;
      });
      _pad.currentState?.clear();
      return;
    }
    if (!mounted) return;

    if (result.status != UnlockStatus.success) {
      setState(() {
        _working = false;
        _problem = 'The PIN could not be changed. Please start again.';
        _step = _Step.current;
        _currentPin = '';
      });
      _pad.currentState?.clear();
      return;
    }

    // Show the message on the screen that is still there after we close.
    final messenger = ScaffoldMessenger.of(context);
    final p = Palette.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      buildToast(p, 'Master PIN changed.', kind: ToastKind.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final stepNumber = _step.index + 1;

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: _working ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'STEP $stepNumber OF 3',
                    style: AppText.overline.copyWith(color: p.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: AppText.display.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: p.muted),
                ),
                const SizedBox(height: 28),
                PinEntry(
                  key: _pad,
                  enabled: !_working && !_blocked,
                  onCompleted: _onPin,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: Center(
                    child: _working
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : (_problem == null
                            ? null
                            : Text(
                                _problem!,
                                textAlign: TextAlign.center,
                                style: AppText.caption.copyWith(
                                  color: p.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
