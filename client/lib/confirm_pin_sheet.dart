import 'dart:async';

import 'package:flutter/material.dart';

import 'security_service.dart';
import 'ui/pin_entry.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

/// Asks for the Master PIN in a bottom sheet before a sensitive action, such
/// as creating a recovery phrase. Returns true only when the PIN was right.
///
/// The vault is already open when this is shown, so without it anyone holding
/// the unlocked phone could add their own way into the vault. Wrong PINs are
/// counted like on the unlock screen.
Future<bool> confirmPin(
  BuildContext context, {
  String title = 'Confirm your PIN',
  String message = 'Enter your Master PIN to continue.',
}) async {
  final ok = await showAppSheet<bool>(
    context,
    builder: (sheetContext) => _ConfirmPinSheet(title: title, message: message),
  );
  return ok == true;
}

class _ConfirmPinSheet extends StatefulWidget {
  final String title;
  final String message;
  const _ConfirmPinSheet({required this.title, required this.message});

  @override
  State<_ConfirmPinSheet> createState() => _ConfirmPinSheetState();
}

class _ConfirmPinSheetState extends State<_ConfirmPinSheet> {
  final GlobalKey<PinEntryState> _pad = GlobalKey<PinEntryState>();

  String? _problem;
  bool _working = false;
  bool _blocked = false;

  Future<void> _onPin(String pin) async {
    if (_working || _blocked) return;
    setState(() {
      _working = true;
      _problem = null;
    });
    final result = await SecurityService().verifyPin(pin);
    if (!mounted) return;
    setState(() => _working = false);

    switch (result.status) {
      case UnlockStatus.success:
        Navigator.of(context).pop(true);
      case UnlockStatus.wrongPin:
        unawaited(_pad.currentState?.showError());
        final left = result.attemptsLeft;
        setState(() {
          _problem = left > 0
              ? 'Incorrect PIN. $left ${left == 1 ? 'try' : 'tries'} left '
                  'before a lockout.'
              : 'Incorrect PIN.';
        });
      case UnlockStatus.lockedOut:
        unawaited(_pad.currentState?.showError());
        setState(() {
          _blocked = true;
          _problem = 'Too many wrong PINs. Try again in '
              '${(result.wait.inSeconds / 60).ceil()} min.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: AppText.title,
          ),
          const SizedBox(height: 8),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: p.muted),
          ),
          const SizedBox(height: 22),
          PinEntry(
            key: _pad,
            enabled: !_working && !_blocked,
            onCompleted: _onPin,
          ),
          const SizedBox(height: 12),
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
    );
  }
}
