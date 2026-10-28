import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'clipboard_service.dart';
import 'password_generator.dart';
import 'password_tools.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

/// The generator controls and result. It is used inside a bottom sheet (when
/// adding a password) and on the Generator screen (from the Security tab).
/// With [onUse] it shows a "Use this password" button, otherwise "Copy".
class GeneratorPanel extends StatefulWidget {
  final ValueChanged<String>? onUse;
  const GeneratorPanel({super.key, this.onUse});

  @override
  State<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<GeneratorPanel> {
  double _length = 16;
  bool _upper = true;
  bool _lower = true;
  bool _digits = true;
  bool _symbols = true;
  bool _lookAlikes = false;

  late String _password = _make();

  String _make() {
    return PasswordGenerator.generate(
      length: _length.round(),
      useUppercase: _upper,
      useLowercase: _lower,
      useDigits: _digits,
      useSymbols: _symbols,
      avoidLookAlikes: _lookAlikes,
    );
  }

  void _regenerate() => setState(() => _password = _make());

  void _change({bool? upper, bool? lower, bool? digits, bool? symbols}) {
    final u = upper ?? _upper;
    final l = lower ?? _lower;
    final d = digits ?? _digits;
    final s = symbols ?? _symbols;
    if (!(u || l || d || s)) {
      showToast(
        context,
        'Keep at least one kind of character switched on.',
        kind: ToastKind.warning,
      );
      return;
    }
    setState(() {
      _upper = u;
      _lower = l;
      _digits = d;
      _symbols = s;
      _password = _make();
    });
  }

  Future<void> _copy() async {
    await ClipboardService.copySensitive(_password);
    if (!mounted) return;
    final seconds = AppSettings.instance.clipboardSeconds;
    showToast(
      context,
      'Password copied. It clears in $seconds seconds.',
      kind: ToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final strength = PasswordTools.evaluate(_password);
    final onUse = widget.onUse;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ColoredPassword(password: _password, fontSize: 21),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StrengthMeter(
                      level: strength.level,
                      label: strength.label,
                    ),
                  ),
                  const SizedBox(width: 12),
                  RoundIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Generate another',
                    onPressed: _regenerate,
                  ),
                  const SizedBox(width: 8),
                  RoundIconButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy',
                    onPressed: _copy,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text('Length', style: AppText.subtitle.copyWith(fontSize: 15)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: p.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_length.round()}',
                style: TextStyle(
                  color: p.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: _length,
          min: 8,
          max: 40,
          divisions: 32,
          onChanged: (value) {
            setState(() {
              _length = value;
              _password = _make();
            });
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillChip(
              label: 'A-Z',
              selected: _upper,
              onTap: () => _change(upper: !_upper),
            ),
            PillChip(
              label: 'a-z',
              selected: _lower,
              onTap: () => _change(lower: !_lower),
            ),
            PillChip(
              label: '0-9',
              selected: _digits,
              onTap: () => _change(digits: !_digits),
            ),
            PillChip(
              label: '#\$%&',
              selected: _symbols,
              onTap: () => _change(symbols: !_symbols),
            ),
            PillChip(
              label: 'No look-alikes',
              icon: Icons.visibility_outlined,
              selected: _lookAlikes,
              onTap: () {
                setState(() {
                  _lookAlikes = !_lookAlikes;
                  _password = _make();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (onUse != null)
          GradientButton(
            label: 'Use this password',
            icon: Icons.check_rounded,
            onPressed: () => onUse(_password),
          )
        else
          GradientButton(
            label: 'Copy password',
            icon: Icons.copy_rounded,
            onPressed: _copy,
          ),
      ],
    );
  }
}

/// The generator as a full page.
class GeneratorScreen extends StatelessWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
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
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Password generator', style: AppText.display),
            const SizedBox(height: 8),
            Text(
              'Random passwords made on this phone. Nothing is sent anywhere.',
              style: AppText.body.copyWith(color: p.muted),
            ),
            const SizedBox(height: 22),
            const GeneratorPanel(),
          ],
        ),
      ),
    );
  }
}
