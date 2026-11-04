import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'home_shell.dart';
import 'security_service.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

enum _Stage { show, check, saved }

/// Creates the 12-word recovery phrase in two steps:
///   1. The words are shown. The user writes them on paper.
///   2. The user types three of them back, to prove the paper is right.
///
/// Nothing is saved until step 2 succeeds, so an old phrase keeps working if
/// the user leaves halfway. The phrase is never saved as words anywhere. Only
/// the vault key, wrapped with a key made from the words, is stored.
class RecoveryPhraseScreen extends StatefulWidget {
  /// True right after the first PIN setup. "Done" and "Skip" then open the
  /// home screen instead of going back to Settings.
  final bool firstRun;

  /// True when a phrase already exists and this one will replace it.
  final bool replacing;

  const RecoveryPhraseScreen({
    super.key,
    this.firstRun = false,
    this.replacing = false,
  });

  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen> {
  static const int _quizCount = 3;

  final SecurityService _security = SecurityService();
  final List<TextEditingController> _answers = [
    for (var i = 0; i < _quizCount; i++) TextEditingController(),
  ];

  _Stage _stage = _Stage.show;
  List<String> _words = <String>[];
  List<int> _quiz = <int>[]; // positions (from 0) the user must type back
  String? _problem;
  bool _saving = false;
  bool _failedToMake = false;

  @override
  void initState() {
    super.initState();
    // While the words are on screen, screenshots and screen recordings stay
    // blocked, even if the user turned "Block screenshots" off in Settings.
    unawaited(ScreenGuard.setSecure(true));
    unawaited(_makeWords());
  }

  @override
  void dispose() {
    unawaited(ScreenGuard.setSecure(AppSettings.instance.blockScreenshots));
    for (final controller in _answers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _makeWords() async {
    try {
      final words = await _security.generateRecoveryWords();
      if (!mounted) return;
      setState(() => _words = words);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failedToMake = true);
    }
  }

  // ---------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------

  void _goToCheck() {
    // Pick three different positions out of 12, in order.
    final rng = Random.secure();
    final picks = <int>{};
    while (picks.length < _quizCount) {
      picks.add(rng.nextInt(_words.length));
    }
    for (final controller in _answers) {
      controller.clear();
    }
    setState(() {
      _quiz = picks.toList()..sort();
      _problem = null;
      _stage = _Stage.check;
    });
  }

  void _backToWords() {
    setState(() {
      _problem = null;
      _stage = _Stage.show;
    });
  }

  Future<void> _verifyAndSave() async {
    if (_saving) return;
    for (var i = 0; i < _quizCount; i++) {
      final typed = _answers[i].text.trim().toLowerCase();
      if (typed != _words[_quiz[i]]) {
        setState(() {
          _problem = 'One of the words is not right. Check your paper copy, '
              'or go back to see the words again.';
        });
        return;
      }
    }

    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await _security.storeRecoveryWords(_words);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _problem = 'The phrase could not be saved. Nothing was changed. '
            'Please try again.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _words = <String>[]; // do not keep the words around any longer
      _stage = _Stage.saved;
    });
  }

  Future<void> _skip() async {
    final sure = await confirmAction(
      context,
      title: 'Skip the recovery phrase?',
      message: 'Without it, a forgotten PIN means your data cannot be '
          'recovered. You can set it up later in Settings.',
      confirmLabel: 'Skip for now',
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (!sure || !mounted) return;
    _leave();
  }

  /// Close this screen: home on first run, otherwise back to Settings.
  void _leave() {
    if (widget.firstRun) {
      Navigator.of(context).pushAndRemoveUntil(
        fadeRoute<void>(const HomeShell()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------

  Widget _chip(Palette p, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: AppText.overline.copyWith(color: p.primary)),
    );
  }

  Widget _wordCell(Palette p, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: AppText.caption.copyWith(
                  color: p.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              _words[index],
              style: TextStyle(
                color: p.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Words 1 to 6 on the left, 7 to 12 on the right, so the user can copy
  /// them down column by column.
  Widget _wordGrid(Palette p) {
    final half = _words.length ~/ 2;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (var row = 0; row < half; row++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: _wordCell(p, row)),
                  const SizedBox(width: 10),
                  Expanded(child: _wordCell(p, row + half)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _backButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: RoundIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Back',
        onPressed: _saving
            ? null
            : () {
                if (_stage == _Stage.check) {
                  _backToWords();
                } else {
                  Navigator.of(context).pop();
                }
              },
      ),
    );
  }

  Widget _showStage(Palette p) {
    if (_failedToMake) {
      return Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.error_outline_rounded, color: p.danger, size: 48),
          const SizedBox(height: 16),
          Text(
            'Could not make a recovery phrase on this phone.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: p.muted),
          ),
          const SizedBox(height: 20),
          SoftButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: () {
              setState(() => _failedToMake = false);
              unawaited(_makeWords());
            },
          ),
        ],
      );
    }
    if (_words.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _wordGrid(p),
        const SizedBox(height: 16),
        InfoBanner(
          icon: Icons.edit_note_rounded,
          color: p.warning,
          text: 'Write the 12 words on paper, in this order. Keep the paper '
              'away from this phone. There is no copy button on purpose, and '
              'screenshots are blocked on this screen.',
        ),
        const SizedBox(height: 10),
        InfoBanner(
          icon: Icons.key_rounded,
          color: p.danger,
          text: 'Anyone who has these words can open your vault, so treat '
              'them like the PIN itself. Do not switch to another app while '
              'writing: KeyMaster locks when you leave, and you would start '
              'again.',
        ),
        if (widget.replacing) ...[
          const SizedBox(height: 10),
          InfoBanner(
            icon: Icons.swap_horiz_rounded,
            text: 'Your old phrase keeps working until you finish step 2. '
                'After that, only this new one works.',
          ),
        ],
        const SizedBox(height: 22),
        GradientButton(
          label: 'I wrote them down',
          icon: Icons.check_rounded,
          onPressed: _goToCheck,
        ),
        if (widget.firstRun) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _skip,
            child: Text('Skip for now', style: TextStyle(color: p.muted)),
          ),
        ],
      ],
    );
  }

  Widget _checkStage(Palette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _quizCount; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          AppField(
            controller: _answers[i],
            label: 'Word number ${_quiz[i] + 1}',
            icon: Icons.tag_rounded,
            secret: true,
            textInputAction:
                i == _quizCount - 1 ? TextInputAction.done : TextInputAction.next,
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
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
          label: 'Save recovery phrase',
          icon: Icons.lock_rounded,
          loading: _saving,
          onPressed: _verifyAndSave,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _saving ? null : _backToWords,
          child: Text('Show the words again', style: TextStyle(color: p.muted)),
        ),
      ],
    );
  }

  Widget _savedStage(Palette p) {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [p.success, p.accent]),
            boxShadow: [BoxShadow(color: p.success.withAlpha(110), blurRadius: 36)],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
        ),
        const SizedBox(height: 24),
        const Text('Recovery phrase saved', style: AppText.display),
        const SizedBox(height: 12),
        Text(
          'Keep the paper somewhere safe. If you ever forget your PIN, tap '
          '"Forgot PIN?" on the unlock screen and type these words.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: p.muted),
        ),
        const SizedBox(height: 28),
        GradientButton(
          label: 'Done',
          icon: Icons.arrow_forward_rounded,
          onPressed: _leave,
        ),
      ],
    );
  }

  String get _headline {
    switch (_stage) {
      case _Stage.show:
        return 'Your recovery phrase';
      case _Stage.check:
        return 'Check your paper';
      case _Stage.saved:
        return '';
    }
  }

  String get _subline {
    switch (_stage) {
      case _Stage.show:
        return 'Twelve words that can open your vault if you forget the PIN.';
      case _Stage.check:
        return 'Type the words below, exactly as written on your paper.';
      case _Stage.saved:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // On the first run there is nothing behind step 1 to go back
                // to, so the back button only appears from step 2 onwards.
                if (_stage == _Stage.check ||
                    (_stage == _Stage.show && !widget.firstRun))
                  _backButton()
                else
                  const SizedBox(height: 48),
                if (_stage != _Stage.saved) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: _chip(
                      p,
                      _stage == _Stage.show
                          ? 'WRITE IT DOWN · 1 OF 2'
                          : 'CHECK IT · 2 OF 2',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _headline,
                    textAlign: TextAlign.center,
                    style: AppText.display.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _subline,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(color: p.muted),
                  ),
                  const SizedBox(height: 24),
                ],
                if (_stage == _Stage.show) _showStage(p),
                if (_stage == _Stage.check) _checkStage(p),
                if (_stage == _Stage.saved) _savedStage(p),
              ],
            ),
          ),
        ),
      ),
    );
  }
}