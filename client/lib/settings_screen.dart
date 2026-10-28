import 'package:flutter/material.dart';

import 'about_screen.dart';
import 'app_lock.dart';
import 'app_settings.dart';
import 'change_pin_screen.dart';
import 'onboarding_screen.dart';
import 'security_service.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_store.dart';
import 'wipe_service.dart';

/// The Settings tab.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettings _settings = AppSettings.instance;
  bool _biometricSupported = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final supported = await SecurityService().isBiometricSupported();
    if (!mounted) return;
    setState(() => _biometricSupported = supported);
  }

  // ---------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------

  Future<void> _toggleBiometric(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);

    final security = SecurityService();
    var ok = true;
    if (on) {
      ok = await security.enableBiometrics();
    } else {
      await security.disableBiometrics();
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (on && !ok) {
      showToast(
        context,
        'Biometric unlock was not turned on.',
        kind: ToastKind.warning,
      );
      return;
    }
    _settings.setBiometricOn(on);
    showToast(
      context,
      on ? 'Biometric unlock is on.' : 'Biometric unlock is off.',
      kind: ToastKind.success,
    );
  }

  String _autoLockSubtitle(int seconds) {
    return seconds == 0
        ? 'Immediately when you leave the app'
        : 'After ${secondsLabel(seconds).toLowerCase()} away';
  }

  Future<void> _pickAutoLock() async {
    final value = await pickChoice<int>(
      context,
      title: 'Auto-lock',
      selected: _settings.autoLockSeconds,
      choices: [
        const Choice<int>(0, 'Immediately', 'Most secure. Locks as soon as you leave.'),
        const Choice<int>(30, 'After 30 seconds', 'Time to check a message'),
        const Choice<int>(60, 'After 1 minute'),
        const Choice<int>(300, 'After 5 minutes', 'Convenient, less secure'),
      ],
    );
    if (value != null) await _settings.setAutoLockSeconds(value);
  }

  Future<void> _pickClipboard() async {
    final value = await pickChoice<int>(
      context,
      title: 'Clear the clipboard after',
      selected: _settings.clipboardSeconds,
      choices: [
        for (final seconds in AppSettings.clipboardChoices)
          Choice<int>(seconds, secondsLabel(seconds)),
      ],
    );
    if (value != null) await _settings.setClipboardSeconds(value);
  }

  Future<void> _erase() async {
    final first = await confirmAction(
      context,
      title: 'Erase all data?',
      message: 'Every password, note and photo and your Master PIN will be '
          'deleted from this phone. This cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (!first || !mounted) return;

    final typed = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => const _TypeToConfirm(word: 'ERASE'),
    );
    if (typed != true || !mounted) return;

    setState(() => _busy = true);
    await WipeService.eraseEverything();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute<void>(const OnboardingScreen()),
      (route) => false,
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (context) => page));
  }

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  Widget _profileCard(Palette p) {
    final store = VaultStore.instance;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const BrandMark(size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('KeyMaster', style: AppText.title),
                const SizedBox(height: 3),
                Text(
                  '${store.logins.length} passwords · '
                  '${store.notes.length} notes · '
                  '${store.photos.length} photos',
                  style: AppText.caption.copyWith(color: p.muted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: p.success),
                    const SizedBox(width: 6),
                    Text(
                      'Encrypted on this phone',
                      style: AppText.caption.copyWith(
                        color: p.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themePicker(Palette p) {
    return AppCard(
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: p.surface,
            foregroundColor: p.muted,
            selectedBackgroundColor: p.primary.withAlpha(40),
            selectedForegroundColor: p.primary,
            side: BorderSide(color: p.border),
          ),
          segments: const [
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              label: Text('System'),
              icon: Icon(Icons.brightness_auto_rounded),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode_rounded),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_rounded),
            ),
          ],
          selected: {_settings.themeMode},
          onSelectionChanged: (selection) {
            tapFeedback();
            _settings.setThemeMode(selection.first);
          },
        ),
      ),
    );
  }

  Widget _body(Palette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const PageTitle(eyebrow: 'Make it yours', title: 'Settings'),
        const SizedBox(height: 18),
        _profileCard(p),
        const SectionLabel('Appearance'),
        _themePicker(p),
        const SectionLabel('Security'),
        SettingGroup(
          children: [
            SettingTile(
              icon: Icons.fingerprint_rounded,
              color: p.accent,
              title: 'Biometric unlock',
              subtitle: _biometricSupported
                  ? 'Fingerprint or face instead of the PIN'
                  : 'Not available on this phone',
              onTap: _biometricSupported
                  ? () => _toggleBiometric(!_settings.biometricOn)
                  : null,
              trailing: Switch(
                value: _settings.biometricOn,
                onChanged: (_biometricSupported && !_busy) ? _toggleBiometric : null,
              ),
            ),
            SettingTile(
              icon: Icons.timer_rounded,
              color: p.warning,
              title: 'Auto-lock',
              subtitle: _autoLockSubtitle(_settings.autoLockSeconds),
              onTap: _pickAutoLock,
            ),
            SettingTile(
              icon: Icons.pin_rounded,
              color: p.primary,
              title: 'Change Master PIN',
              subtitle: 'Your data stays as it is',
              onTap: () => _open(const ChangePinScreen()),
            ),
            SettingTile(
              icon: Icons.screenshot_rounded,
              color: p.violet,
              title: 'Block screenshots',
              subtitle: 'Hides the app in screenshots and the app switcher. '
                  'Turn off to take screenshots.',
              onTap: () => _settings.setBlockScreenshots(!_settings.blockScreenshots),
              trailing: Switch(
                value: _settings.blockScreenshots,
                onChanged: _settings.setBlockScreenshots,
              ),
            ),
          ],
        ),
        const SectionLabel('Privacy'),
        SettingGroup(
          children: [
            SettingTile(
              icon: Icons.content_paste_off_rounded,
              color: p.danger,
              title: 'Clear clipboard after',
              subtitle: secondsLabel(_settings.clipboardSeconds),
              onTap: _pickClipboard,
            ),
          ],
        ),
        const SectionLabel('Vault'),
        SettingGroup(
          children: [
            SettingTile(
              icon: Icons.lock_rounded,
              color: p.primary,
              title: 'Lock now',
              subtitle: 'Forget the keys and return to the PIN screen',
              onTap: AppLock.instance.lockNow,
            ),
            SettingTile(
              icon: Icons.delete_forever_rounded,
              title: 'Erase all data',
              subtitle: 'Deletes everything on this phone',
              danger: true,
              onTap: _busy ? null : _erase,
            ),
          ],
        ),
        const SectionLabel('About'),
        SettingGroup(
          children: [
            SettingTile(
              icon: Icons.shield_moon_rounded,
              color: p.accent,
              title: 'How KeyMaster protects you',
              subtitle: 'Encryption, keys and limits explained',
              onTap: () => _open(const AboutScreen()),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([_settings, VaultStore.instance]),
          builder: (context, child) => _body(p),
        ),
      ),
    );
  }
}

/// A bottom sheet that asks the user to type a word before a risky action.
class _TypeToConfirm extends StatefulWidget {
  final String word;
  const _TypeToConfirm({required this.word});

  @override
  State<_TypeToConfirm> createState() => _TypeToConfirmState();
}

class _TypeToConfirmState extends State<_TypeToConfirm> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final matches = _controller.text.trim() == widget.word;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Type ERASE to confirm', style: AppText.title),
          const SizedBox(height: 8),
          Text(
            'This is the last step. After this, the app is as new and nothing '
            'can be recovered.',
            style: AppText.body.copyWith(color: p.muted),
          ),
          const SizedBox(height: 18),
          AppField(
            controller: _controller,
            label: 'Type ${widget.word}',
            icon: Icons.warning_amber_rounded,
            secret: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          GradientButton(
            label: 'Erase everything',
            icon: Icons.delete_forever_rounded,
            danger: true,
            onPressed: matches ? () => Navigator.pop(context, true) : null,
          ),
        ],
      ),
    );
  }
}
