import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import 'about_screen.dart';
import 'app_lock.dart';
import 'app_settings.dart';
import 'change_pin_screen.dart';
import 'confirm_pin_sheet.dart';
import 'decoy_screen.dart';
import 'intruder_log_screen.dart';
import 'intruder_service.dart';
import 'keystore_biometric.dart';
import 'onboarding_screen.dart';
import 'recovery_phrase_screen.dart';
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
  BiometricStatus _biometricStatus = BiometricStatus.unavailable;
  bool _hasPhrase = false;
  bool _decoyOn = false;
  int _newIntruderPhotos = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  /// Reads what the security service knows: can this phone guard a key with
  /// the fingerprint sensor, does the vault have a recovery phrase, is a decoy
  /// PIN set, and were there new intruder photos?
  Future<void> _loadStatus() async {
    final security = SecurityService();
    final status = await security.biometricStatus();
    final hasPhrase = await security.hasRecoveryPhrase();
    // Only the real vault can read these two. The decoy vault never shows them.
    final real = security.isUnlocked && !security.isDecoySession;
    var decoyOn = false;
    var newPhotos = 0;
    if (real) {
      try {
        decoyOn = await security.isDecoyEnabled();
        newPhotos = await IntruderService.instance.unseenCount();
      } catch (_) {
        // Shown as off.
      }
    }
    if (!mounted) return;
    setState(() {
      _biometricStatus = status;
      _hasPhrase = hasPhrase;
      _decoyOn = decoyOn;
      _newIntruderPhotos = newPhotos;
    });
  }

  bool get _canToggleBiometric {
    if (_busy) return false;
    // Turning it off is always allowed. Turning it on needs a strong sensor.
    return _biometricStatus == BiometricStatus.ready || _settings.biometricOn;
  }

  String get _biometricSubtitle {
    switch (_biometricStatus) {
      case BiometricStatus.ready:
        return "Fingerprint opens the vault. The key stays in the phone's "
            'Keystore.';
      case BiometricStatus.notEnrolled:
        return 'Save a fingerprint in your phone settings first';
      case BiometricStatus.weakOnly:
        return "This phone's sensor is rated too weak to guard a key";
      case BiometricStatus.unavailable:
        return 'Not available on this phone';
    }
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
        'Fingerprint unlock was not turned on.',
        kind: ToastKind.warning,
      );
      return;
    }
    _settings.setBiometricOn(on);
    showToast(
      context,
      on ? 'Fingerprint unlock is on.' : 'Fingerprint unlock is off.',
      kind: ToastKind.success,
    );
  }

  /// Create or replace the recovery phrase. The PIN is asked first, because
  /// the vault is already open and a recovery phrase is a second way in.
  Future<void> _openRecovery() async {
    final replacing = _hasPhrase;
    final ok = await confirmPin(
      context,
      title: replacing ? 'Replace your recovery phrase' : 'Create a recovery phrase',
      message: 'Enter your Master PIN to continue.',
    );
    if (!ok || !mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => RecoveryPhraseScreen(replacing: replacing),
      ),
    );
    if (!mounted) return;
    await _loadStatus();
  }

  /// Opens a real-only screen, and reads the status again when it closes.
  Future<void> _openAndRefresh(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => page),
    );
    if (!mounted) return;
    await _loadStatus();
  }

  String get _intruderSubtitle {
    final fresh = _newIntruderPhotos > 0
        ? ' $_newIntruderPhotos new ${_newIntruderPhotos == 1 ? 'photo' : 'photos'}.'
        : '';
    return _settings.intruderOn
        ? 'On. The front camera takes a photo after 5 wrong PINs.$fresh'
        : 'Off. Take a photo of whoever enters the PIN wrongly.$fresh';
  }

  void _openSpeedTest() {
    showAppSheet<void>(
      context,
      builder: (sheetContext) => const _SpeedTestSheet(),
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
      message: 'Every password, note and photo, your Master PIN and your '
          'recovery phrase will be deleted from this phone. This cannot be '
          'undone.',
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
    // In a decoy session the rows that belong to the real vault are not shown:
    // the decoy has no fingerprint, no recovery phrase, no PIN to change and
    // nothing to erase from there.
    final decoy = SecurityService().isDecoySession;
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
            if (!decoy)
              SettingTile(
                icon: Icons.fingerprint_rounded,
                color: p.accent,
                title: 'Fingerprint unlock',
                subtitle: _biometricSubtitle,
                onTap: _canToggleBiometric
                    ? () => _toggleBiometric(!_settings.biometricOn)
                    : null,
                trailing: Switch(
                  value: _settings.biometricOn,
                  onChanged: _canToggleBiometric ? _toggleBiometric : null,
                ),
              ),
            if (!decoy)
              SettingTile(
                icon: Icons.key_rounded,
                color: _hasPhrase ? p.success : p.warning,
                title: 'Recovery phrase',
                subtitle: _hasPhrase
                    ? 'Set. Opens the vault if you forget the PIN.'
                    : 'Not set up. A forgotten PIN means lost data.',
                onTap: _busy ? null : _openRecovery,
              ),
            SettingTile(
              icon: Icons.timer_rounded,
              color: p.warning,
              title: 'Auto-lock',
              subtitle: _autoLockSubtitle(_settings.autoLockSeconds),
              onTap: _pickAutoLock,
            ),
            if (!decoy)
              SettingTile(
                icon: Icons.pin_rounded,
                color: p.primary,
                title: 'Change Master PIN',
                subtitle: 'Your data stays as it is',
                onTap: () => _open(const ChangePinScreen()),
              ),
            if (!decoy)
              SettingTile(
                icon: Icons.theater_comedy_rounded,
                color: p.violet,
                title: 'Decoy vault',
                subtitle: _decoyOn
                    ? 'On. A second PIN opens a harmless vault.'
                    : 'Off. A second PIN can open a harmless vault.',
                onTap: _busy ? null : () => _openAndRefresh(const DecoyScreen()),
              ),
            if (!decoy)
              SettingTile(
                icon: Icons.camera_front_rounded,
                color: p.danger,
                title: 'Intruder photos',
                subtitle: _intruderSubtitle,
                onTap: _busy
                    ? null
                    : () => _openAndRefresh(const IntruderLogScreen()),
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
            if (!decoy)
              SettingTile(
                icon: Icons.delete_forever_rounded,
                title: 'Erase all data',
                subtitle: 'Deletes everything on this phone',
                danger: true,
                onTap: _busy ? null : _erase,
              ),
          ],
        ),
        const SectionLabel('Diagnostics'),
        SettingGroup(
          children: [
            SettingTile(
              icon: Icons.speed_rounded,
              color: p.accent,
              title: 'Test unlock speed',
              subtitle: 'Times a real unlock on this phone',
              onTap: _openSpeedTest,
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

/// Runs the real Argon2id key derivation a few times and shows how long the
/// unlock step takes on this phone. This is the evidence for the report's
/// unlock-speed requirement (NFR4).
class _SpeedTestSheet extends StatefulWidget {
  const _SpeedTestSheet();

  @override
  State<_SpeedTestSheet> createState() => _SpeedTestSheetState();
}

class _SpeedTestSheetState extends State<_SpeedTestSheet> {
  static const int _runs = 5;

  /// The target from the report (NFR4). Change it if your report says other.
  static const int _targetMs = 2000;

  String get _targetText => '${(_targetMs / 1000).toStringAsFixed(1)} s';

  List<int>? _times;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    try {
      final times = await SecurityService().measureUnlockSpeed(_runs);
      if (!mounted) return;
      setState(() => _times = times);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _again() {
    setState(() {
      _times = null;
      _failed = false;
    });
    _measure();
  }

  Widget _stat(Palette p, String label, int ms, {bool big = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$ms',
            style: TextStyle(
              fontSize: big ? 30 : 22,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$label (ms)',
            style: AppText.caption.copyWith(color: p.muted),
          ),
        ],
      ),
    );
  }

  Widget _results(Palette p, List<int> times) {
    final sorted = [...times]..sort();
    var total = 0;
    for (final ms in times) {
      total += ms;
    }
    final average = (total / times.length).round();
    final ok = average <= _targetMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _stat(p, 'Fastest', sorted.first),
            _stat(p, 'Average', average, big: true),
            _stat(p, 'Slowest', sorted.last),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Runs: ${times.join(', ')} ms',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: p.muted),
        ),
        const SizedBox(height: 16),
        InfoBanner(
          icon: ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          color: ok ? p.success : p.warning,
          text: ok
              ? 'The average is within the $_targetText target.'
              : 'The average is over the $_targetText target.',
        ),
        if (!kReleaseMode) ...[
          const SizedBox(height: 10),
          InfoBanner(
            icon: Icons.bug_report_rounded,
            color: p.violet,
            text: 'This is a debug build, which is several times slower than '
                'the real app. Run the app with flutter run --release and '
                'test again before you copy these numbers.',
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Unlocking takes about this long, plus a few milliseconds for '
          'decryption. Write your phone model next to the numbers. On a phone '
          'with one fast core the pair can take up to twice as long as one.',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: p.muted),
        ),
        const SizedBox(height: 16),
        Center(
          child: SoftButton(
            label: 'Run again',
            icon: Icons.refresh_rounded,
            onPressed: _again,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final times = _times;

    Widget body;
    if (_failed) {
      body = Column(
        children: [
          Text(
            'The test could not run.',
            style: AppText.body.copyWith(color: p.danger),
          ),
          const SizedBox(height: 14),
          SoftButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: _again,
          ),
        ],
      );
    } else if (times == null) {
      body = Column(
        children: [
          const SizedBox(height: 10),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Timing $_runs unlocks...',
            style: AppText.body.copyWith(color: p.muted),
          ),
          const SizedBox(height: 10),
        ],
      );
    } else {
      body = _results(p, times);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Unlock speed', style: AppText.title),
          const SizedBox(height: 6),
          Text(
            'How long a PIN takes to turn into keys. An unlock does this for '
            'both vault slots at the same time, with the real Argon2id '
            'settings, so you wait the same whichever PIN you type.',
            style: AppText.body.copyWith(color: p.muted),
          ),
          const SizedBox(height: 20),
          body,
        ],
      ),
    );
  }
}
