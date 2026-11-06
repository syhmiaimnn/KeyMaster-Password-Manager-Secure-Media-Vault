import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';
import 'password_tools.dart';
import 'recovery_phrase.dart';
import 'security_service.dart';
import 'ui/pin_entry.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'wipe_service.dart';

enum _Stage { phrase, fresh, confirm }

/// "Forgot PIN?": the user types the 12-word recovery phrase, then chooses a
/// new PIN. The passwords and photos are not touched, because the phrase
/// unlocks the same vault key that the old PIN did.
///
/// Nothing is saved until the new PIN has been entered twice, so leaving this
/// screen halfway changes nothing.
class RecoverAccessScreen extends StatefulWidget {
  const RecoverAccessScreen({super.key});

  @override
  State<RecoverAccessScreen> createState() => _RecoverAccessScreenState();
}

class _RecoverAccessScreenState extends State<RecoverAccessScreen> {
  final SecurityService _security = SecurityService();
  final GlobalKey<PinEntryState> _pad = GlobalKey<PinEntryState>();
  final TextEditingController _phrase = TextEditingController();

  _Stage _stage = _Stage.phrase;
  String _newPin = '';
  String? _problem;
  bool _working = false;
  bool _noPhrase = false; // this vault never got a recovery phrase
  bool _keyHeld = false; // the phrase was right, so the key is in memory
  bool _finished = false;

  int get _typedWords => RecoveryPhrase.split(_phrase.text).length;

  @override
  void dispose() {
    _phrase.dispose();
    // Leaving after the phrase was accepted but before the PIN was set:
    // forget the recovered key again.
    if (_keyHeld && !_finished) _security.lock();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Step 1: the phrase
  // ---------------------------------------------------------------

  String _explain(PhraseCheck check) {
    switch (check.problem) {
      case PhraseProblem.wrongCount:
        return 'A recovery phrase has 12 words. You typed '
            '${check.words.length}.';
      case PhraseProblem.unknownWord:
        return 'Word number ${check.badIndex + 1} '
            '("${check.words[check.badIndex]}") is not in the word list. '
            'Check the spelling.';
      case PhraseProblem.badChecksum:
        return 'These 12 words are not a valid phrase. A word may be '
            'misspelled, in the wrong place or replaced.';
      case null:
        return '';
    }
  }

  Future<void> _submitPhrase() async {
    if (_working) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _problem = null;
      _noPhrase = false;
    });

    final check = await _security.checkRecoveryText(_phrase.text);
    if (!mounted) return;
    if (!check.isValid) {
      setState(() {
        _working = false;
        _problem = _explain(check);
      });
      return;
    }

    final outcome = await _security.recoverWithPhrase(check.words);
    if (!mounted) return;

    switch (outcome) {
      case RecoveryOutcome.success:
        _keyHeld = true;
        _phrase.clear();
        setState(() {
          _working = false;
          _stage = _Stage.fresh;
        });
      case RecoveryOutcome.wrongPhrase:
        setState(() {
          _working = false;
          _problem = 'These words are a valid phrase, but not the one for '
              'this vault. Check that you are using your latest paper copy.';
        });
      case RecoveryOutcome.notSet:
        setState(() {
          _working = false;
          _noPhrase = true;
        });
    }
  }

  Future<void> _eraseInstead() async {
    final sure = await confirmAction(
      context,
      title: 'Erase everything?',
      message: 'Without a recovery phrase the data cannot be opened. Erasing '
          'deletes every password, note and photo from this phone so you can '
          'start again with a new PIN. This cannot be undone.',
      confirmLabel: 'Erase',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!sure || !mounted) return;

    setState(() => _working = true);
    await WipeService.eraseEverything();
    if (!mounted) return;
    _finished = true;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute<void>(const OnboardingScreen()),
      (route) => false,
    );
  }

  // ---------------------------------------------------------------
  // Steps 2 and 3: the new PIN
  // ---------------------------------------------------------------

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
    await _finish(pin);
  }

  Future<void> _finish(String pin) async {
    setState(() {
      _working = true;
      _problem = null;
    });
    try {
      await _security.finishRecovery(pin);
    } on PinNotAllowedException catch (e) {
      // The new PIN already opens the other vault. Nothing was changed.
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
        _problem = 'The PIN could not be reset. Nothing was changed. '
            'Please try again.';
      });
      _pad.currentState?.clear();
      return;
    }
    if (!mounted) return;

    _finished = true;
    AppSettings.instance.recordUnlock();

    // Keep these before the screen changes, so the message can still be shown.
    final messenger = ScaffoldMessenger.of(context);
    final p = Palette.of(context);
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute<void>(const HomeShell()),
      (route) => false,
    );
    messenger.showSnackBar(
      buildToast(p, 'PIN reset. Welcome back.', kind: ToastKind.success),
    );
  }

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  int get _stepNumber => _stage.index + 1;

  String get _title {
    switch (_stage) {
      case _Stage.phrase:
        return 'Enter your recovery phrase';
      case _Stage.fresh:
        return 'Choose a new PIN';
      case _Stage.confirm:
        return 'Confirm the new PIN';
    }
  }

  String get _subtitle {
    switch (_stage) {
      case _Stage.phrase:
        return 'Type the 12 words from your paper, in order.';
      case _Stage.fresh:
        return 'Your phrase worked. Pick six digits for the new PIN.';
      case _Stage.confirm:
        return 'Enter the new PIN once more.';
    }
  }

  Widget _phraseStage(Palette p) {
    final count = _typedWords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          controller: _phrase,
          label: 'Recovery phrase',
          hint: 'word1 word2 word3 ...',
          icon: Icons.key_rounded,
          secret: true,
          maxLines: 4,
          minLines: 3,
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() => _problem = null),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$count of ${RecoveryPhrase.wordCount} words',
            style: AppText.caption.copyWith(
              color: count == RecoveryPhrase.wordCount ? p.success : p.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: Center(
            child: _problem == null
                ? null
                : Text(
                    _problem!,
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(
                      color: p.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        GradientButton(
          label: 'Check phrase',
          icon: Icons.lock_open_rounded,
          loading: _working,
          onPressed: count == 0 ? null : _submitPhrase,
        ),
        if (_noPhrase) ...[
          const SizedBox(height: 20),
          InfoBanner(
            icon: Icons.error_outline_rounded,
            color: p.danger,
            text: 'This vault has no recovery phrase, so a forgotten PIN '
                'cannot be recovered. The only way forward is to erase the '
                'vault and start again.',
          ),
          const SizedBox(height: 12),
          Center(
            child: SoftButton(
              label: 'Erase everything and start again',
              icon: Icons.delete_forever_rounded,
              color: p.danger,
              onPressed: _working ? null : _eraseInstead,
            ),
          ),
        ],
      ],
    );
  }

  Widget _pinStage(Palette p) {
    return Column(
      children: [
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
                        'Securing your vault with the new PIN...',
                        style: AppText.caption.copyWith(color: p.muted),
                      ),
                    ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: _working ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'STEP $_stepNumber OF 3',
                      style: AppText.overline.copyWith(color: p.primary),
                    ),
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
                const SizedBox(height: 26),
                if (_stage == _Stage.phrase) _phraseStage(p) else _pinStage(p),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
