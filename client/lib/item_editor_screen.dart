import 'package:flutter/material.dart';

import 'generator_screen.dart';
import 'password_tools.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_item.dart';
import 'vault_store.dart';

/// Add a new password or note, or edit an existing one. Pops with true when
/// the item was saved.
class ItemEditorScreen extends StatefulWidget {
  final VaultItem? existing;
  final String initialType;

  const ItemEditorScreen({
    super.key,
    this.existing,
    this.initialType = 'Password',
  });

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  final VaultStore _store = VaultStore.instance;

  late String _type = widget.existing?.type ?? widget.initialType;
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _website =
      TextEditingController(text: widget.existing?.website ?? '');
  late final TextEditingController _username =
      TextEditingController(text: widget.existing?.username ?? '');
  late final TextEditingController _password =
      TextEditingController(text: widget.existing?.password ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');

  bool _obscure = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  bool get _isEditing => widget.existing != null;
  bool get _isPassword => _type == 'Password';

  @override
  void dispose() {
    _title.dispose();
    _website.dispose();
    _username.dispose();
    _password.dispose();
    _note.dispose();
    super.dispose();
  }

  void _touched() => setState(() {
        _dirty = true;
        _error = null;
      });

  Future<void> _openGenerator() async {
    final generated = await showAppSheet<String>(
      context,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Generate a password', style: AppText.title),
            const SizedBox(height: 16),
            GeneratorPanel(onUse: (value) => Navigator.pop(sheetContext, value)),
          ],
        ),
      ),
    );
    if (generated == null || !mounted) return;
    setState(() {
      _password.text = generated;
      _obscure = false; // show it, so the user can see what was made
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give this item a title.');
      return;
    }
    if (_isPassword && _password.text.isEmpty) {
      setState(() => _error = 'Enter a password, or tap Generate.');
      return;
    }
    if (!_isPassword && _note.text.trim().isEmpty) {
      setState(() => _error = 'Write something in the note.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final old = widget.existing;
    final now = DateTime.now();
    try {
      if (old == null) {
        await _store.add(
          VaultItem(
            id: '${now.microsecondsSinceEpoch}',
            type: _type,
            title: title,
            username: _isPassword ? _username.text.trim() : '',
            password: _isPassword ? _password.text : '',
            website: _isPassword ? _website.text.trim() : '',
            note: _note.text,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        final secretChanged =
            old.password != _password.text || old.note != _note.text;
        await _store.update(
          old.copyWith(
            title: title,
            username: _isPassword ? _username.text.trim() : '',
            password: _isPassword ? _password.text : '',
            website: _isPassword ? _website.text.trim() : '',
            note: _note.text,
            updatedAt: secretChanged ? now : old.updatedAt,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'The vault could not be saved. Please try again.';
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _askBeforeLeaving() async {
    final leave = await confirmAction(
      context,
      title: 'Discard changes?',
      message: 'What you typed has not been saved.',
      confirmLabel: 'Discard',
      destructive: true,
      icon: Icons.edit_off_rounded,
    );
    if (!leave || !mounted) return;
    Navigator.of(context).pop(false);
  }

  Widget _typeCard(Palette p, String type, IconData icon, String label) {
    final selected = _type == type;
    final color = type == 'Password' ? p.primary : p.violet;
    return Expanded(
      child: AppCard(
        color: selected ? color.withAlpha(30) : p.surface,
        borderColor: selected ? color : p.border,
        padding: const EdgeInsets.symmetric(vertical: 14),
        onTap: () {
          tapFeedback();
          setState(() {
            _type = type;
            _error = null;
          });
        },
        child: Column(
          children: [
            Icon(icon, color: selected ? color : p.muted),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? color : p.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _passwordFields(Palette p) {
    final strength = PasswordTools.evaluate(_password.text);
    return [
      AppField(
        controller: _website,
        label: 'Website (optional)',
        hint: 'example.com',
        icon: Icons.language_rounded,
        keyboardType: TextInputType.url,
        secret: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => _touched(),
      ),
      const SizedBox(height: 14),
      AppField(
        controller: _username,
        label: 'Username or email',
        icon: Icons.person_outline_rounded,
        keyboardType: TextInputType.emailAddress,
        secret: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => _touched(),
      ),
      const SizedBox(height: 14),
      AppField(
        controller: _password,
        label: 'Password',
        icon: Icons.lock_outline_rounded,
        obscure: _obscure,
        secret: true,
        onChanged: (_) => _touched(),
        suffix: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            color: p.muted,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: StrengthMeter(
              level: strength.level,
              empty: _password.text.isEmpty,
              label: _password.text.isEmpty ? 'Not set' : strength.label,
            ),
          ),
          const SizedBox(width: 12),
          SoftButton(
            label: 'Generate',
            icon: Icons.auto_awesome_rounded,
            onPressed: _openGenerator,
          ),
        ],
      ),
      if (_password.text.isNotEmpty && strength.tips.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          strength.tips.first,
          style: AppText.caption.copyWith(color: p.muted),
        ),
      ],
      const SizedBox(height: 14),
      AppField(
        controller: _note,
        label: 'Notes (optional)',
        icon: Icons.notes_rounded,
        minLines: 2,
        maxLines: 5,
        keyboardType: TextInputType.multiline,
        onChanged: (_) => _touched(),
      ),
    ];
  }

  List<Widget> _noteFields() {
    return [
      AppField(
        controller: _note,
        label: 'Your secret note',
        minLines: 8,
        maxLines: 14,
        keyboardType: TextInputType.multiline,
        onChanged: (_) => _touched(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _askBeforeLeaving();
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Row(
                children: [
                  RoundIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: Text(
                      'Save',
                      style: TextStyle(
                        color: p.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _isEditing ? 'Edit item' : 'New item',
                style: AppText.display,
              ),
              const SizedBox(height: 6),
              Text(
                'Encrypted on this phone before it is saved.',
                style: AppText.body.copyWith(color: p.muted),
              ),
              const SizedBox(height: 22),
              if (!_isEditing) ...[
                Row(
                  children: [
                    _typeCard(p, 'Password', Icons.key_rounded, 'Password'),
                    const SizedBox(width: 12),
                    _typeCard(p, 'Note', Icons.sticky_note_2_rounded, 'Secure note'),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              AppField(
                controller: _title,
                label: _isPassword ? 'Title or service' : 'Title',
                hint: _isPassword ? 'Google, bank, Wi-Fi...' : 'Recovery codes...',
                icon: Icons.title_rounded,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _touched(),
              ),
              const SizedBox(height: 14),
              ..._isPassword ? _passwordFields(p) : _noteFields(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                InfoBanner(
                  icon: Icons.error_outline_rounded,
                  color: p.danger,
                  text: _error!,
                ),
              ],
              const SizedBox(height: 24),
              GradientButton(
                label: _isEditing ? 'Save changes' : 'Save to vault',
                icon: Icons.lock_rounded,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
