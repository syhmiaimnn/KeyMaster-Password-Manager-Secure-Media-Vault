import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'clipboard_service.dart';
import 'item_editor_screen.dart';
import 'password_tools.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_item.dart';
import 'vault_store.dart';

/// Opens the detail page. If the user deletes the item there, it is removed
/// here and an Undo message is shown, so every screen deletes the same way.
Future<void> openItemDetail(BuildContext context, String id) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final p = Palette.of(context);

  final deleted = await navigator.push<VaultItem>(
    MaterialPageRoute<VaultItem>(
      builder: (context) => ItemDetailScreen(itemId: id),
    ),
  );
  if (deleted == null) return;

  try {
    await VaultStore.instance.remove(deleted.id);
  } catch (_) {
    messenger.showSnackBar(
      buildToast(p, 'The item could not be deleted.', kind: ToastKind.error),
    );
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    buildToast(
      p,
      'Deleted "${deleted.title}".',
      actionLabel: 'Undo',
      onAction: () => VaultStore.instance.add(deleted),
    ),
  );
}

/// Everything about one password or note. Pops with the item when the user
/// confirms a delete (the caller deletes it, see [openItemDetail]).
class ItemDetailScreen extends StatefulWidget {
  final String itemId;
  const ItemDetailScreen({super.key, required this.itemId});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final VaultStore _store = VaultStore.instance;
  bool _reveal = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    _hideTimer?.cancel();
    setState(() => _reveal = !_reveal);
    if (_reveal) {
      // Hide the password again after a while, in case the phone is put down.
      _hideTimer = Timer(const Duration(seconds: 20), () {
        if (mounted) setState(() => _reveal = false);
      });
    }
  }

  Future<void> _copy(String what, String value) async {
    await ClipboardService.copySensitive(value);
    if (!mounted) return;
    final seconds = AppSettings.instance.clipboardSeconds;
    showToast(
      context,
      '$what copied. It clears in $seconds seconds.',
      kind: ToastKind.success,
    );
  }

  Future<void> _edit(VaultItem item) async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => ItemEditorScreen(existing: item),
      ),
    );
    if (saved == true && mounted) {
      showToast(context, 'Changes saved.', kind: ToastKind.success);
    }
  }

  Future<void> _delete(VaultItem item) async {
    final ok = await confirmAction(
      context,
      title: 'Delete "${item.title}"?',
      message: 'It is removed from your vault. You can undo for a few seconds.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop(item);
  }

  Widget _field(
    Palette p, {
    required String label,
    required String value,
    List<Widget> actions = const [],
    Widget? valueWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppText.overline.copyWith(color: p.muted),
                ),
                const SizedBox(height: 5),
                valueWidget ??
                    Text(value, style: const TextStyle(fontSize: 16.5)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _copyButton(Palette p, String what, String value) {
    return IconButton(
      tooltip: 'Copy $what',
      onPressed: () => _copy(what, value),
      icon: Icon(Icons.copy_rounded, size: 20, color: p.primary),
    );
  }

  Widget _passwordSection(Palette p, VaultItem item) {
    final strength = PasswordTools.evaluate(item.password);
    final shownTips = strength.tips.take(2).toList();
    final others = _store.logins
        .where((other) => other.id != item.id && other.password == item.password)
        .toList();
    final age = DateTime.now().difference(item.updatedAt).inDays;
    final isOld = age > SecurityReport.oldAfterDays;

    final divider = Divider(height: 1, thickness: 1, color: p.border);

    return Column(
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (item.username.isNotEmpty) ...[
                _field(
                  p,
                  label: 'Username or email',
                  value: item.username,
                  actions: [_copyButton(p, 'username', item.username)],
                ),
                divider,
              ],
              if (item.website.isNotEmpty) ...[
                _field(
                  p,
                  label: 'Website',
                  value: item.website,
                  actions: [_copyButton(p, 'website', item.website)],
                ),
                divider,
              ],
              _field(
                p,
                label: 'Password',
                value: item.password,
                valueWidget: item.password.isEmpty
                    ? Text('No password saved', style: TextStyle(color: p.muted))
                    : _reveal
                        ? ColoredPassword(password: item.password, fontSize: 17)
                        : Text(
                            '•' * 12,
                            style: const TextStyle(
                              fontSize: 17,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                actions: item.password.isEmpty
                    ? const []
                    : [
                        IconButton(
                          tooltip: _reveal ? 'Hide password' : 'Show password',
                          onPressed: _toggleReveal,
                          icon: Icon(
                            _reveal
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                            color: p.muted,
                          ),
                        ),
                        _copyButton(p, 'password', item.password),
                      ],
              ),
              if (item.password.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: StrengthMeter(
                    level: strength.level,
                    label: '${strength.label} · ${strength.bits.round()} bits',
                  ),
                ),
            ],
          ),
        ),
        if (item.password.isNotEmpty) ...[
          const SizedBox(height: 14),
          if (others.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoBanner(
                icon: Icons.copy_all_rounded,
                color: p.danger,
                text: 'This password is also used by '
                    '${others.map((other) => other.title).take(3).join(', ')}'
                    '${others.length > 3 ? ' and ${others.length - 3} more' : ''}. '
                    'Use a different one for every account.',
              ),
            ),
          if (strength.isWeak)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoBanner(
                icon: Icons.warning_amber_rounded,
                color: p.warning,
                text: shownTips.isEmpty
                    ? 'This password is easy to guess.'
                    : 'Easy to guess. ${shownTips.join(' ')}',
              ),
            ),
          if (isOld)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoBanner(
                icon: Icons.history_rounded,
                color: p.warning,
                text: 'Changed ${timeAgo(item.updatedAt)}. '
                    'Consider updating it.',
              ),
            ),
        ],
      ],
    );
  }

  Widget _noteSection(Palette p, VaultItem item) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              item.note.isEmpty ? 'This note is empty.' : item.note,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
          if (item.note.isNotEmpty) _copyButton(p, 'note', item.note),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, VaultItem item) {
    final p = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            RoundIconButton(
              icon: item.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              tooltip: item.favorite ? 'Remove from favourites' : 'Add to favourites',
              color: item.favorite ? p.warning : null,
              onPressed: () => _store.toggleFavorite(item.id),
            ),
            const SizedBox(width: 8),
            RoundIconButton(
              icon: Icons.edit_rounded,
              tooltip: 'Edit',
              onPressed: () => _edit(item),
            ),
            const SizedBox(width: 8),
            RoundIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete',
              color: p.danger,
              onPressed: () => _delete(item),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: Hero(
            tag: 'avatar-${item.id}',
            child: ItemAvatar(title: item.title, isNote: item.isNote, size: 84),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          item.title,
          textAlign: TextAlign.center,
          style: AppText.display.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 6),
        Text(
          item.isNote ? 'Secure note' : 'Password',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: p.muted),
        ),
        const SizedBox(height: 24),
        Reveal(
          child: item.isNote ? _noteSection(p, item) : _passwordSection(p, item),
        ),
        if (item.isPassword && item.note.isNotEmpty) ...[
          const SectionLabel('Notes'),
          AppCard(
            child: SelectableText(
              item.note,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Center(
          child: Text(
            'Added ${formatDate(item.createdAt)}'
            '${item.updatedAt.isAfter(item.createdAt) ? ' · Changed ${timeAgo(item.updatedAt)}' : ''}',
            style: AppText.caption.copyWith(color: p.muted),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, child) {
            final item = _store.byId(widget.itemId);
            if (item == null) {
              return const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Item not found',
                message: 'It may have been deleted.',
              );
            }
            return _body(context, item);
          },
        ),
      ),
    );
  }
}
