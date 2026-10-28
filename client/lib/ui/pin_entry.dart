import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'widgets.dart';

/// A PIN dot row plus a number keypad. It collects the digits and calls
/// [onCompleted] once [length] digits are in. It never stores or checks the
/// PIN: the screen that owns it decides what happens next.
///
/// Keep a `GlobalKey<PinEntryState>` to call [PinEntryState.clear] (start over)
/// or [PinEntryState.showError] (shake, then start over).
class PinEntry extends StatefulWidget {
  final int length;
  final bool enabled;
  final ValueChanged<String> onCompleted;

  /// The empty key at the bottom left. The unlock screen puts the fingerprint
  /// button here.
  final Widget? leading;

  const PinEntry({
    super.key,
    required this.onCompleted,
    this.length = 6,
    this.enabled = true,
    this.leading,
  });

  @override
  State<PinEntry> createState() => PinEntryState();
}

class PinEntryState extends State<PinEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  String _pin = '';
  bool _error = false;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  /// Forget the digits typed so far.
  void clear() {
    if (_pin.isEmpty && !_error) return;
    setState(() {
      _pin = '';
      _error = false;
    });
  }

  /// Turn the dots red, shake them, then start over.
  Future<void> showError() async {
    if (!mounted) return;
    setState(() => _error = true);
    HapticFeedback.heavyImpact().catchError((Object _) {});
    await _shake.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _pin = '';
      _error = false;
    });
  }

  void _add(String digit) {
    if (!widget.enabled || _pin.length >= widget.length) return;
    tapFeedback();
    setState(() {
      _pin += digit;
      _error = false;
    });
    if (_pin.length == widget.length) widget.onCompleted(_pin);
  }

  void _backspace() {
    if (!widget.enabled || _pin.isEmpty) return;
    tapFeedback();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  Widget _dots(Palette p) {
    final color = _error ? p.danger : p.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pin.length ? color : Colors.transparent,
              border: Border.all(
                color: i < _pin.length ? color : p.border,
                width: 2,
              ),
              boxShadow: i < _pin.length
                  ? [BoxShadow(color: color.withAlpha(110), blurRadius: 10)]
                  : const [],
            ),
          ),
      ],
    );
  }

  Widget _digitKey(Palette p, double size, String digit) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: p.surface,
        shape: CircleBorder(side: BorderSide(color: p.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.enabled ? () => _add(digit) : null,
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w500,
                color: p.text,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _backspaceKey(Palette p, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: widget.enabled ? _backspace : null,
        onLongPress: widget.enabled ? clear : null,
        child: Center(
          child: Icon(Icons.backspace_outlined, color: p.muted, size: size * 0.34),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final compact = MediaQuery.sizeOf(context).height < 680;
    final size = compact ? 62.0 : 74.0;

    Widget row(List<Widget> cells) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 5 : 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: cells,
        ),
      );
    }

    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final t = _shake.value;
              final dx = math.sin(t * math.pi * 6) * 12 * (1 - t);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: _dots(p),
          ),
          SizedBox(height: compact ? 22 : 36),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Column(
              children: [
                row([
                  _digitKey(p, size, '1'),
                  _digitKey(p, size, '2'),
                  _digitKey(p, size, '3'),
                ]),
                row([
                  _digitKey(p, size, '4'),
                  _digitKey(p, size, '5'),
                  _digitKey(p, size, '6'),
                ]),
                row([
                  _digitKey(p, size, '7'),
                  _digitKey(p, size, '8'),
                  _digitKey(p, size, '9'),
                ]),
                row([
                  SizedBox(width: size, height: size, child: widget.leading),
                  _digitKey(p, size, '0'),
                  _backspaceKey(p, size),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
