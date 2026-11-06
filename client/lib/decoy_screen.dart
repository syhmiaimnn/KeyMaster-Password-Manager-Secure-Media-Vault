import 'dart:async';

import 'package:flutter/material.dart';

import 'confirm_pin_sheet.dart';
import 'media_vault_service.dart';
import 'password_tools.dart';
import 'security_service.dart';
import 'ui/pin_entry.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_slot.dart';

/// Settings > Decoy vault (FR12). Only the real vault can open this screen.
///
/// A decoy PIN opens a second, harmless vault. It is for the moment someone
/// makes you unlock your phone: you type the decoy PIN, and they see a vault
/// with ordinary entries. The real vault is not shown, and nothing on screen
/// says that another one exists.
class DecoyScreen extends StatefulWidget {
  const DecoyScreen({super.key});

  @override
  State<DecoyScreen> createState() => _DecoyScreenState();
}

class _DecoyScreenState extends State<DecoyScreen> {
  final SecurityService _security = SecurityService();

  bool _loading = true;
  bool _on = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var on = false;
    try {
      on = await _security.isDecoyEnabled();
    } catch (_) {
      // Shown as off.
    }
    if (!mounted) return;
    setState(() {
      _on = on;
      _loading = false;
    });
  }

  Future<void> _setOrChange() async {
    final changing = _on;
    final ok = await confirmPin(
      context,
      title: changing ? 'Change the decoy PIN' : 'Set a decoy PIN',
      message: 'Enter your real Master PIN to continue.',
    );
    if (!ok || !mounted) return;

    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => DecoyPinScreen(changing: changing),
      ),
    );
    if (done != true || !mounted) return;

    // A new decoy vault starts with an empty photo folder.
    if (!changing) await MediaVaultService.clearSlot(VaultSlot.decoy);
    await _load();
    if (!mounted) return;
    showToast(
      context,
      changing ? 'Decoy PIN changed.' : 'Decoy vault is on.',
      kind: ToastKind.success,
    );
  }

  Future<void> _turnOff() async {
    final sure = await confirmAction(
      context,
      title: 'Turn off the decoy vault?',
      message: 'The decoy PIN stops working. Everything inside the decoy '
          'vault, including its photos, is deleted. Your real vault is not '
          'touched.',
      confirmLabel: 'Turn off',
      destructive: true,
      icon: Icons.layers_clear_rounded,
    );
    if (!sure || !mounted) return;

    final ok = await confirmPin(
      context,
      title: 'Confirm your PIN',
      message: 'Enter your real Master PIN to turn the decoy vault off.',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await _security.removeDecoy();
      await MediaVaultService.clearSlot(VaultSlot.decoy);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, 'The decoy vault could not be turned off.',
          kind: ToastKind.error);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (!mounted) return;
    showToast(context, 'Decoy vault is off.', kind: ToastKind.success);
  }

  Widget _point(Palette p, IconData icon, String title, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: p.violet, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.subtitle.copyWith(fontSize: 15)),
                const SizedBox(height: 3),
                Text(text, style: AppText.caption.copyWith(color: p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final divider = Divider(height: 1, thickness: 1, indent: 66, color: p.border);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const PageTitle(eyebrow: 'Under pressure', title: 'Decoy vault'),
            const SizedBox(height: 14),
            Text(
              'A second PIN that opens a different vault with ordinary, '
              'harmless entries. Use it if someone makes you unlock your phone.',
              style: AppText.body.copyWith(color: p.muted),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              AppCard(
                child: Row(
                  children: [
                    IconBadge(
                      icon: _on ? Icons.check_circle_rounded : Icons.layers_outlined,
                      color: _on ? p.success : p.muted,
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _on ? 'Decoy vault is on' : 'Decoy vault is off',
                            style: AppText.subtitle,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _on
                                ? 'Your decoy PIN opens the harmless vault.'
                                : 'Only your real PIN works.',
                            style: AppText.caption.copyWith(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GradientButton(
                label: _on ? 'Change decoy PIN' : 'Set a decoy PIN',
                icon: Icons.pin_rounded,
                onPressed: _busy ? null : _setOrChange,
              ),
              if (_on) ...[
                const SizedBox(height: 10),
                SoftButton(
                  label: 'Turn off decoy vault',
                  icon: Icons.layers_clear_rounded,
                  onPressed: _busy ? null : _turnOff,
                ),
              ],
            ],
            const SectionLabel('How it works'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _point(
                    p,
                    Icons.vpn_key_rounded,
                    'Two vaults, two keys',
                    'The decoy vault has its own key, its own entries and its '
                        'own photo folder. It shares nothing with the real one.',
                  ),
                  divider,
                  _point(
                    p,
                    Icons.timer_rounded,
                    'Same wait for both PINs',
                    'The app always checks both PINs, in the same way, so the '
                        'time it takes does not show which one you typed.',
                  ),
                  divider,
                  _point(
                    p,
                    Icons.storage_rounded,
                    'Looks the same inside the phone',
                    'With the decoy off, the second vault holds random bytes '
                        'in the same shape as a real one. A look at the stored '
                        'data does not show whether a decoy exists.',
                  ),
                  divider,
                  _point(
                    p,
                    Icons.visibility_off_rounded,
                    'Fewer settings in the decoy',
                    'Inside the decoy vault the settings for fingerprint, '
                        'recovery phrase, PIN change, decoy and intruder photos '
                        'are not shown.',
                  ),
                ],
              ),
            ),
            const SectionLabel('Honest limits'),
            const InfoBanner(
              icon: Icons.info_outline_rounded,
              text: 'Someone who knows how KeyMaster works could notice the '
                  'missing settings. The fingerprint always opens the real '
                  'vault, so do not press it when you are being forced. The '
                  'decoy PIN must differ from your real PIN. Changing the '
                  'decoy PIN keeps what is inside it. Turning it off deletes '
                  'it.',
            ),
          ],
        ),
      ),
    );
  }
}

enum _Stage { fresh, confirm }

/// Asks for the new decoy PIN twice. Pops true when it was saved.
class DecoyPinScreen extends StatefulWidget {
  final bool changing;
  const DecoyPinScreen({super.key, required this.changing});

  @override
  State<DecoyPinScreen> createState() => _DecoyPinScreenState();
}

class _DecoyPinScreenState extends State<DecoyPinScreen> {
  final GlobalKey<PinEntryState> _pad = GlobalKey<PinEntryState>();

  _Stage _stage = _Stage.fresh;
  String _newPin = '';
  String? _problem;
  bool _working = false;

  Future<void> _onPin(String pin) async {
    if (_working) return;

    if (_stage == _Stage.fresh) {
      final problem = PinPolicy.validate(pin);
      if (problem != null) {
        setState(() => _problem = problem);
        unawaited(_pad.currentState?.showError());
        return;
      }
      setState(() {
        _newPin = pin;
        _stage = _Stage.confirm;
        _problem = null;
      });
      _pad.currentState?.clear();
      return;
    }

    if (pin != _newPin) {
      setState(() {
        _problem = 'The two PINs did not match. Choose again.';
        _stage = _Stage.fresh;
        _newPin = '';
      });
      unawaited(_pad.currentState?.showError());
      return;
    }
    await _save(pin);
  }

  Future<void> _save(String pin) async {
    setState(() {
      _working = true;
      _problem = null;
    });
    try {
      await SecurityService().setDecoyPin(pin);
    } on PinNotAllowedException catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _stage = _Stage.fresh;
        _newPin = '';
        _problem = e.message;
      });
      _pad.currentState?.clear();
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _stage = _Stage.fresh;
        _newPin = '';
        _problem = 'The decoy PIN could not be saved. Please try again.';
      });
      _pad.currentState?.clear();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fresh = _stage == _Stage.fresh;

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
                    onPressed: _working ? null : () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.violet.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'DECOY PIN · STEP ${fresh ? 1 : 2} OF 2',
                    style: AppText.overline.copyWith(color: p.violet),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  fresh ? 'Choose a decoy PIN' : 'Confirm the decoy PIN',
                  textAlign: TextAlign.center,
                  style: AppText.display.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  fresh
                      ? 'Six digits. It must be different from your real PIN, '
                          'and easy for you to remember under stress.'
                      : 'Enter the decoy PIN once more.',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: p.muted),
                ),
                const SizedBox(height: 28),
                PinEntry(
                  key: _pad,
                  enabled: !_working,
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
