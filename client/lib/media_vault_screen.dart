import 'dart:async';

import 'package:flutter/material.dart';

import 'clean_share_service.dart';
import 'confirm_pin_sheet.dart';
import 'folder_actions.dart';
import 'folder_screen.dart';
import 'photo_folder.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_store.dart';

/// The Photos tab: your photo folders. Every folder has its own key, and the
/// photos inside it have their own keys locked by the folder key (the key tree
/// from report section 3.4.2). Tap a folder to open it, long-press for options.
class MediaVaultScreen extends StatefulWidget {
  const MediaVaultScreen({super.key});

  @override
  State<MediaVaultScreen> createState() => _MediaVaultScreenState();
}

class _MediaVaultScreenState extends State<MediaVaultScreen> {
  final VaultStore _store = VaultStore.instance;

  @override
  void initState() {
    super.initState();
    // Remove readable copies left over from sharing a clean photo.
    unawaited(CleanShareService.clearTemporaryShares());
  }

  // ---------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------

  /// Opens a folder. A folder that asks for the PIN needs it once per unlock.
  Future<void> _open(PhotoFolder folder) async {
    if (!_store.isFolderOpen(folder)) {
      final ok = await confirmPin(
        context,
        title: 'Open "${folder.name}"',
        message: 'This folder asks for your Master PIN.',
      );
      if (!ok || !mounted) return;
      _store.markFolderOpen(folder.id);
      setState(() {});
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => FolderScreen(folderId: folder.id),
      ),
    );
  }

  Future<void> _newFolder() async {
    await createFolder(context);
  }

  void _showKeyTree() {
    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final p = Palette.of(sheetContext);

        Widget level(IconData icon, Color color, String title, String text) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icon: icon, color: color, size: 38),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.subtitle),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: AppText.caption.copyWith(color: p.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How your photos are locked', style: AppText.title),
              const SizedBox(height: 6),
              Text(
                'Three levels of keys, each one locked by the level above it.',
                style: AppText.caption.copyWith(color: p.muted),
              ),
              const SizedBox(height: 18),
              level(
                Icons.key_rounded,
                p.primary,
                'Vault key',
                'One random key. Your PIN, your recovery phrase and your '
                    'fingerprint each hold their own locked copy of it. It '
                    'protects every folder key.',
              ),
              level(
                Icons.folder_rounded,
                p.accent,
                'Folder key',
                'A new random key for every folder. It is kept inside the '
                    'encrypted vault data and locks the keys of the photos in '
                    'that folder.',
              ),
              level(
                Icons.photo_rounded,
                p.violet,
                'Photo key',
                'A new random key for every photo. It encrypts that one photo '
                    'and its thumbnail, and it is stored locked with the '
                    'folder key.',
              ),
              const SizedBox(height: 4),
              const InfoBanner(
                icon: Icons.info_outline_rounded,
                text: 'A leaked photo key opens one photo. A leaked folder key '
                    'opens one folder. Deleting a folder removes its key, so '
                    'its photos can never be opened again.',
              ),
              const SizedBox(height: 10),
              InfoBanner(
                icon: Icons.lock_outline_rounded,
                color: p.warning,
                text: '"Ask for PIN to open" is an extra check inside the app. '
                    'The folder key itself is always protected by your vault '
                    'key, which opens when you unlock.',
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Got it',
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  Widget _header(Palette p, List<PhotoFolder> folders) {
    final photoCount = _store.photos.length;
    final eyebrow = '${folders.length} ${folders.length == 1 ? 'folder' : 'folders'}'
        ' · $photoCount ${photoCount == 1 ? 'photo' : 'photos'}';

    return PageTitle(
      eyebrow: eyebrow,
      title: 'Photos',
      trailing: RoundIconButton(
        icon: Icons.account_tree_rounded,
        tooltip: 'How your photos are locked',
        onPressed: _showKeyTree,
      ),
    );
  }

  Widget _folderCard(Palette p, PhotoFolder folder) {
    final photos = _store.photosIn(folder.id);
    final bytes = photos.fold<int>(0, (sum, photo) => sum + photo.sizeBytes);
    final color = folderColor(p, folder.colorIndex);
    final locked = !_store.isFolderOpen(folder);

    final details = photos.isEmpty
        ? 'Empty'
        : '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}'
            ' · ${formatBytes(bytes)}';

    return AppCard(
      onTap: () => _open(folder),
      onLongPress: () => showFolderMenu(context, folder),
      child: Row(
        children: [
          IconBadge(
            icon: locked ? Icons.folder_special_rounded : Icons.folder_rounded,
            color: color,
            size: 48,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  style: AppText.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (folder.requiresPin) ...[
                      Icon(Icons.lock_outline_rounded, size: 14, color: p.muted),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        folder.requiresPin ? 'PIN · $details' : details,
                        style: AppText.caption.copyWith(color: p.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Folder options',
            onPressed: () => showFolderMenu(context, folder),
            icon: Icon(Icons.more_horiz_rounded, color: p.muted),
          ),
        ],
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

    final folders = _store.folders;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _header(p, folders),
          ),
        ),
        if (folders.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.create_new_folder_rounded,
              color: p.accent,
              title: 'No folders yet',
              message: 'Make a folder for your private photos. Every folder '
                  'gets its own key.',
              actionLabel: 'New folder',
              onAction: _newFolder,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index.isOdd) return const SizedBox(height: 12);
                  return _folderCard(p, folders[index ~/ 2]);
                },
                childCount: folders.length * 2 - 1,
              ),
            ),
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
          listenable: _store,
          builder: (context, child) => _body(p),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newFolder,
        backgroundColor: p.accent,
        foregroundColor: const Color(0xFF031A18),
        icon: const Icon(Icons.create_new_folder_rounded),
        label: const Text(
          'New folder',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
