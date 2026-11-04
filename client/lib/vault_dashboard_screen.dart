import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'app_settings.dart';
import 'clipboard_service.dart';
import 'item_detail_screen.dart';
import 'item_editor_screen.dart';
import 'password_tools.dart';
import 'ui/format.dart';
import 'ui/score_ring.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_item.dart';
import 'vault_store.dart';

enum _Filter { all, passwords, notes, favorites }

enum _Sort { recent, name, weakest }

/// The Vault tab: health summary, search, filters and the list of passwords
/// and notes. (Photos have their own tab.)
class VaultDashboardScreen extends StatefulWidget {
  /// Called when the health card is tapped (the shell switches tab).
  final VoidCallback? onOpenSecurity;

  const VaultDashboardScreen({super.key, this.onOpenSecurity});

  @override
  State<VaultDashboardScreen> createState() => _VaultDashboardScreenState();
}

class _VaultDashboardScreenState extends State<VaultDashboardScreen> {
  final VaultStore _store = VaultStore.instance;
  final TextEditingController _search = TextEditingController();

  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.recent;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------

  double _bitsOf(VaultItem item) {
    return item.isPassword
        ? PasswordTools.evaluate(item.password).bits
        : double.infinity; // notes go last when sorting by weakest
  }

  int _compare(VaultItem a, VaultItem b) {
    final favorite = (b.favorite ? 1 : 0) - (a.favorite ? 1 : 0);
    if (favorite != 0) return favorite; // favourites first
    switch (_sort) {
      case _Sort.recent:
        return b.createdAt.compareTo(a.createdAt);
      case _Sort.name:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case _Sort.weakest:
        return _bitsOf(a).compareTo(_bitsOf(b));
    }
  }

  List<VaultItem> _visible() {
    final query = _query.trim().toLowerCase();
    var list = _store.items.where((item) => item.type != 'Media').toList();

    if (_filter == _Filter.passwords) {
      list = list.where((item) => item.isPassword).toList();
    } else if (_filter == _Filter.notes) {
      list = list.where((item) => item.isNote).toList();
    } else if (_filter == _Filter.favorites) {
      list = list.where((item) => item.favorite).toList();
    }

    if (query.isNotEmpty) {
      list = list.where((item) {
        return item.title.toLowerCase().contains(query) ||
            item.username.toLowerCase().contains(query) ||
            item.website.toLowerCase().contains(query) ||
            (item.isNote && item.note.toLowerCase().contains(query));
      }).toList();
    }

    list.sort(_compare);
    return list;
  }

  // ---------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------

  Future<void> _add() async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute<bool>(builder: (context) => const ItemEditorScreen()),
    );
    if (saved == true && mounted) {
      showToast(context, 'Saved securely.', kind: ToastKind.success);
    }
  }

  Future<void> _copyPassword(VaultItem item) async {
    await ClipboardService.copySensitive(item.password);
    if (!mounted) return;
    final seconds = AppSettings.instance.clipboardSeconds;
    showToast(
      context,
      'Password copied. It clears in $seconds seconds.',
      kind: ToastKind.success,
    );
  }

  Future<void> _swipeDelete(VaultItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final p = Palette.of(context);
    try {
      await _store.remove(item.id);
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'The item could not be deleted.', kind: ToastKind.error);
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      buildToast(
        p,
        'Deleted "${item.title}".',
        actionLabel: 'Undo',
        onAction: () => _store.add(item),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------

  Widget _healthCard(Palette p, SecurityReport report) {
    final issues = report.issueCount;
    final String line;
    if (issues > 0) {
      line = issues == 1
          ? '1 item needs attention.'
          : '$issues items need attention.';
    } else if (report.passwordCount == 0) {
      line = 'Add passwords to see insights.';
    } else {
      line = 'All passwords look healthy.';
    }

    return AppCard(
      onTap: widget.onOpenSecurity,
      child: Row(
        children: [
          ScoreRing(score: report.score, size: 78, strokeWidth: 8),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VAULT HEALTH',
                  style: AppText.overline.copyWith(color: p.muted),
                ),
                const SizedBox(height: 4),
                Text(report.verdict, style: AppText.title),
                const SizedBox(height: 2),
                Text(line, style: AppText.caption.copyWith(color: p.muted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ],
      ),
    );
  }

  Widget _stat(Palette p, IconData icon, Color color, int value, String label) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: p.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(_Sort sort) {
    switch (sort) {
      case _Sort.recent:
        return 'Newest first';
      case _Sort.name:
        return 'Name (A to Z)';
      case _Sort.weakest:
        return 'Weakest first';
    }
  }

  Widget _searchRow(Palette p) {
    return Row(
      children: [
        Expanded(
          child: AppField(
            controller: _search,
            label: 'Search your vault',
            icon: Icons.search_rounded,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            suffix: _query.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, color: p.muted),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<_Sort>(
          tooltip: 'Sort',
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: p.border),
          ),
          onSelected: (value) => setState(() => _sort = value),
          itemBuilder: (context) => [
            for (final sort in _Sort.values)
              CheckedPopupMenuItem<_Sort>(
                value: sort,
                checked: sort == _sort,
                child: Text(_sortLabel(sort)),
              ),
          ],
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.border),
            ),
            child: Icon(Icons.swap_vert_rounded, color: p.muted),
          ),
        ),
      ],
    );
  }

  Widget _filters(List<VaultItem> all) {
    final texts = all.where((item) => item.type != 'Media').toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          PillChip(
            label: 'All',
            count: texts.length,
            selected: _filter == _Filter.all,
            onTap: () => setState(() => _filter = _Filter.all),
          ),
          const SizedBox(width: 8),
          PillChip(
            label: 'Passwords',
            icon: Icons.key_rounded,
            count: texts.where((item) => item.isPassword).length,
            selected: _filter == _Filter.passwords,
            onTap: () => setState(() => _filter = _Filter.passwords),
          ),
          const SizedBox(width: 8),
          PillChip(
            label: 'Notes',
            icon: Icons.sticky_note_2_rounded,
            count: texts.where((item) => item.isNote).length,
            selected: _filter == _Filter.notes,
            onTap: () => setState(() => _filter = _Filter.notes),
          ),
          const SizedBox(width: 8),
          PillChip(
            label: 'Favourites',
            icon: Icons.star_rounded,
            count: texts.where((item) => item.favorite).length,
            selected: _filter == _Filter.favorites,
            onTap: () => setState(() => _filter = _Filter.favorites),
          ),
        ],
      ),
    );
  }

  Widget _tile(Palette p, VaultItem item, int index) {
    final strength = item.isPassword
        ? PasswordTools.evaluate(item.password)
        : null;

    String subtitle;
    if (item.isNote) {
      subtitle = item.note.trim().split('\n').first;
      if (subtitle.isEmpty) subtitle = 'Empty note';
    } else if (item.username.isNotEmpty) {
      subtitle = item.username;
    } else if (item.website.isNotEmpty) {
      subtitle = item.website;
    } else {
      subtitle = 'No username';
    }

    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Dismissible(
          key: ValueKey<String>(item.id),
          direction: DismissDirection.endToStart,
          onDismissed: (direction) => _swipeDelete(item),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: p.danger.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.delete_outline_rounded, color: p.danger),
          ),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            onTap: () => openItemDetail(context, item.id),
            child: Row(
              children: [
                Hero(
                  tag: 'avatar-${item.id}',
                  child: ItemAvatar(title: item.title, isNote: item.isNote),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.subtitle,
                            ),
                          ),
                          if (item.favorite) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.star_rounded, size: 16, color: p.warning),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (strength != null) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: strengthColor(p, strength.level),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(color: p.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (item.isPassword && item.password.isNotEmpty)
                  IconButton(
                    tooltip: 'Copy password',
                    onPressed: () => _copyPassword(item),
                    icon: Icon(Icons.copy_rounded, size: 20, color: p.muted),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(Palette p) {
    if (!_store.isLoaded) {
      if (_store.loadError != null) {
        return EmptyState(
          icon: Icons.error_outline_rounded,
          color: p.danger,
          title: 'Could not open the vault',
          message: _store.loadError!,
          actionLabel: 'Try again',
          onAction: () => _store.load(force: true),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final all = _store.items;
    final visible = _visible();
    final report = _store.report();
    final textCount = all.where((item) => item.type != 'Media').length;
    final filtering = _query.trim().isNotEmpty || _filter != _Filter.all;

    final Widget list;
    if (textCount == 0) {
      list = SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.key_rounded,
          title: 'Your vault is empty',
          message: 'Add your first password or secure note. '
              'Everything is encrypted on this phone.',
          actionLabel: 'Add item',
          onAction: _add,
        ),
      );
    } else if (visible.isEmpty && filtering) {
      list = const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          message: 'Try a different search word or another filter.',
        ),
      );
    } else {
      list = SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _tile(p, visible[i], i),
            childCount: visible.length,
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                PageTitle(
                  eyebrow: greeting(),
                  title: 'Your vault',
                  trailing: RoundIconButton(
                    icon: Icons.lock_rounded,
                    tooltip: 'Lock now',
                    onPressed: AppLock.instance.lockNow,
                  ),
                ),
                const SizedBox(height: 18),
                _healthCard(p, report),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _stat(p, Icons.key_rounded, p.primary,
                        _store.logins.length, 'Passwords'),
                    const SizedBox(width: 10),
                    _stat(p, Icons.sticky_note_2_rounded, p.violet,
                        _store.notes.length, 'Notes'),
                    const SizedBox(width: 10),
                    _stat(p, Icons.photo_library_rounded, p.accent,
                        _store.photos.length, 'Photos'),
                  ],
                ),
                const SizedBox(height: 18),
                _searchRow(p),
                const SizedBox(height: 12),
                _filters(all),
              ],
            ),
          ),
        ),
        list,
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
          listenable: Listenable.merge([_store, AppSettings.instance]),
          builder: (context, child) => _body(p),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
