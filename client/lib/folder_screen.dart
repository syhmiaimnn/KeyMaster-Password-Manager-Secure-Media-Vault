import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'folder_actions.dart';
import 'media_vault_service.dart';
import 'media_viewer_screen.dart';
import 'photo_folder.dart';
import 'sanitization_preview_screen.dart';
import 'security_service.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_item.dart';
import 'vault_store.dart';

/// What happened while a batch of photos was imported.
class _Batch {
  final List<ImportedPhoto> imported = <ImportedPhoto>[];
  int failed = 0;
  int skipped = 0;
  String? problem;
}

/// The photos of one folder: a grid of encrypted photos. New photos are saved
/// in this folder, with a key locked by this folder's key. Long-press a photo
/// to select several, then move or delete them.
class FolderScreen extends StatefulWidget {
  final String folderId;
  const FolderScreen({super.key, required this.folderId});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final SecurityService _security = SecurityService();
  final VaultStore _store = VaultStore.instance;
  late final MediaVaultService _media =
      MediaVaultService(importFolderId: widget.folderId);
  final ImagePicker _picker = ImagePicker();

  final Set<String> _selected = <String>{};
  String? _busyText; // set while photos are being encrypted
  bool _bannerHidden = false;

  bool get _selecting => _selected.isNotEmpty;

  List<VaultItem> get _photos {
    return _store.photosIn(widget.folderId)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // ---------------------------------------------------------------
  // Adding photos
  // ---------------------------------------------------------------

  Future<void> _chooseFromGallery() async {
    var files = <XFile>[];
    _security.pauseAutoLock(); // the gallery covers the app
    try {
      files = await _picker.pickMultiImage();
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'The gallery could not be opened.', kind: ToastKind.error);
      return;
    } finally {
      _security.resumeAutoLock();
    }
    await _importFiles(files);
  }

  Future<void> _takePhoto() async {
    XFile? shot;
    _security.pauseAutoLock(); // the camera covers the app
    try {
      shot = await _picker.pickImage(source: ImageSource.camera);
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'The camera could not be opened.', kind: ToastKind.error);
      return;
    } finally {
      _security.resumeAutoLock();
    }
    if (shot != null) await _importFiles([shot]);
  }

  Future<void> _importFiles(List<XFile> files) async {
    if (files.isEmpty || !mounted) return;
    if (!_security.isUnlocked) return; // locked while the picker was open

    final batch = _Batch();
    try {
      await _process(files, batch);
    } finally {
      // image_picker copies each choice into the app's cache as a normal,
      // readable file. Delete every copy, whatever happened.
      for (final file in files) {
        await _deleteTempCopy(file);
      }
    }

    if (!mounted) return;
    setState(() => _busyText = null);
    if (batch.imported.isEmpty && batch.failed == 0) {
      showToast(context, 'Nothing was added.');
      return;
    }
    await _showReport(batch);
  }

  /// Goes through the photos one by one. Each photo gets a privacy preview,
  /// unless the user chose to clean all the remaining ones without looking.
  Future<void> _process(List<XFile> files, _Batch batch) async {
    var cleanRest = false;

    for (var i = 0; i < files.length; i++) {
      if (!mounted || !_security.isUnlocked) return;
      try {
        setState(() => _busyText = 'Reading photo ${i + 1} of ${files.length}...');
        final bytes = await files[i].readAsBytes();
        final before = await _media.analyze(bytes);
        if (!mounted) return;

        if (cleanRest) {
          setState(() => _busyText = 'Cleaning photo ${i + 1} of ${files.length}...');
          batch.imported.add(await importIntoVault(_media, bytes, before: before));
          continue;
        }

        setState(() => _busyText = null);
        final result = await Navigator.of(context).push<PreviewResult>(
          MaterialPageRoute<PreviewResult>(
            builder: (context) => SanitizationPreviewScreen(
              bytes: bytes,
              before: before,
              media: _media,
              position: i + 1,
              total: files.length,
            ),
          ),
        );
        if (!mounted) return;

        if (result == null || result.action == PreviewAction.stopAll) {
          batch.skipped += files.length - i;
          return;
        }
        if (result.action == PreviewAction.saved && result.photo != null) {
          batch.imported.add(result.photo!);
          cleanRest = result.cleanRest;
        } else if (result.action == PreviewAction.failed) {
          batch.failed++;
          batch.problem ??= result.error;
        } else {
          batch.skipped++;
        }
      } catch (error) {
        batch.failed++;
        batch.problem ??= error is MediaVaultException ? error.message : null;
      }
    }
  }

  /// image_picker copies each choice into the app's cache as a normal,
  /// readable file. Delete that copy as soon as the photo is encrypted.
  Future<void> _deleteTempCopy(XFile file) async {
    try {
      await File(file.path).delete();
    } catch (_) {
      // Already gone, or not a normal file.
    }
  }

  Widget _reportRow(Palette p, IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: AppText.body),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReport(_Batch batch) async {
    if (!mounted) return;
    final folder = _store.folderById(widget.folderId);
    final imported = batch.imported;
    final failed = batch.failed;
    final withLocation = imported.where((photo) => photo.before.hasLocation).length;
    final withDevice = imported.where((photo) => photo.before.hasDevice).length;
    final withOwner = imported.where((photo) => photo.before.hasOwner).length;
    final removed = imported.fold<int>(
      0,
      (sum, photo) => sum + photo.before.hiddenFieldCount,
    );

    await showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final p = Palette.of(sheetContext);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                imported.isNotEmpty ? 'Photos secured' : 'Nothing was added',
                style: AppText.title,
              ),
              const SizedBox(height: 16),
              if (imported.isNotEmpty) ...[
                _reportRow(
                  p,
                  Icons.lock_rounded,
                  p.success,
                  imported.length == 1
                      ? '1 photo encrypted with its own key.'
                      : '${imported.length} photos encrypted, each with its own key.',
                ),
                _reportRow(
                  p,
                  Icons.folder_rounded,
                  p.primary,
                  folder == null
                      ? 'The photo keys are locked with the folder key.'
                      : 'Saved in "${folder.name}". The photo keys are locked '
                          'with this folder\'s own key.',
                ),
                _reportRow(
                  p,
                  Icons.cleaning_services_rounded,
                  p.accent,
                  removed > 0
                      ? 'Hidden photo data removed: $removed fields.'
                      : 'No hidden photo data was found.',
                ),
                _reportRow(
                  p,
                  Icons.location_off_rounded,
                  withLocation > 0 ? p.warning : p.success,
                  withLocation > 0
                      ? 'A GPS location was found and removed in $withLocation photo(s).'
                      : 'No GPS location was found.',
                ),
                _reportRow(
                  p,
                  Icons.photo_camera_rounded,
                  withDevice > 0 ? p.warning : p.success,
                  withDevice > 0
                      ? 'Camera or phone details were found and removed in $withDevice photo(s).'
                      : 'No camera details were found.',
                ),
                if (withOwner > 0)
                  _reportRow(
                    p,
                    Icons.badge_rounded,
                    p.warning,
                    'Owner, serial number or description fields were found '
                    'and removed in $withOwner photo(s).',
                  ),
                _reportRow(
                  p,
                  Icons.verified_rounded,
                  p.success,
                  imported.length == 1
                      ? 'The saved copy was read back and checked. Nothing that identifies you or the place is left.'
                      : 'Every saved copy was read back and checked. Nothing that identifies you or the place is left.',
                ),
                const InfoBanner(
                  icon: Icons.info_outline_rounded,
                  text: 'Your originals are still in the gallery. Delete them '
                      'there if you do not want them to stay. KeyMaster cannot '
                      'do that for you yet.',
                ),
              ],
              if (batch.skipped > 0) ...[
                const SizedBox(height: 14),
                _reportRow(
                  p,
                  Icons.skip_next_rounded,
                  p.muted,
                  batch.skipped == 1
                      ? '1 photo was skipped.'
                      : '${batch.skipped} photos were skipped.',
                ),
              ],
              if (failed > 0) ...[
                const SizedBox(height: 14),
                _reportRow(
                  p,
                  Icons.error_outline_rounded,
                  p.danger,
                  batch.problem == null
                      ? '$failed photo(s) could not be imported.'
                      : '$failed photo(s) could not be imported. ${batch.problem}',
                ),
              ],
              const SizedBox(height: 10),
              GradientButton(
                label: 'Done',
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddSheet() {
    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final p = Palette.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add photos', style: AppText.title),
              const SizedBox(height: 6),
              Text(
                'You see what each photo gives away first. Then it is cleaned, '
                'checked and encrypted into this folder.',
                style: AppText.caption.copyWith(color: p.muted),
              ),
              const SizedBox(height: 14),
              SettingGroup(
                children: [
                  SettingTile(
                    icon: Icons.photo_library_rounded,
                    color: p.accent,
                    title: 'Choose from gallery',
                    subtitle: 'Pick one or many photos',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _chooseFromGallery();
                    },
                  ),
                  SettingTile(
                    icon: Icons.photo_camera_rounded,
                    color: p.primary,
                    title: 'Take a photo',
                    subtitle: 'Straight into the vault',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _takePhoto();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------
  // Opening, selecting, moving, deleting
  // ---------------------------------------------------------------

  Future<void> _open(List<VaultItem> photos, int index) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MediaViewerScreen(
          photos: photos,
          initialIndex: index,
          media: _media,
          onDelete: _deleteOne,
        ),
      ),
    );
  }

  /// Used by the viewer. The record (and with it the key) goes first.
  Future<bool> _deleteOne(VaultItem photo) async {
    try {
      await _store.remove(photo.id);
      await _media.deletePhotoFiles(photo);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _toggle(String id) {
    tapFeedback();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final ok = await confirmAction(
      context,
      title: ids.length == 1 ? 'Delete this photo?' : 'Delete ${ids.length} photos?',
      message: 'The encrypted copies and their keys are removed from '
          'KeyMaster. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    final doomed = _store.photos.where((photo) => ids.contains(photo.id)).toList();
    try {
      await _store.removeMany(ids); // the records, and their keys, go first
      for (final photo in doomed) {
        await _media.deletePhotoFiles(photo);
      }
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'The photos could not be deleted.', kind: ToastKind.error);
      return;
    }
    if (!mounted) return;
    setState(_selected.clear);
    showToast(
      context,
      doomed.length == 1 ? 'Photo deleted.' : '${doomed.length} photos deleted.',
      kind: ToastKind.success,
    );
  }

  /// Moves the selected photos to another folder. Only their keys are locked
  /// again, with the key of the new folder. The photo files do not change.
  Future<void> _moveSelected() async {
    final targets =
        _store.folders.where((folder) => folder.id != widget.folderId).toList();
    if (targets.isEmpty) {
      showToast(context, 'Create another folder first.');
      return;
    }

    final target = await showAppSheet<PhotoFolder>(
      context,
      builder: (sheetContext) {
        final p = Palette.of(sheetContext);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Move to folder', style: AppText.title),
              const SizedBox(height: 6),
              Text(
                'Each photo key is locked again with the key of the new '
                'folder. The photo files are not changed.',
                style: AppText.caption.copyWith(color: p.muted),
              ),
              const SizedBox(height: 14),
              SettingGroup(
                children: [
                  for (final folder in targets)
                    SettingTile(
                      icon: Icons.folder_rounded,
                      color: folderColor(p, folder.colorIndex),
                      title: folder.name,
                      subtitle: '${_store.photosIn(folder.id).length} photos',
                      onTap: () => Navigator.pop(sheetContext, folder),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (target == null || !mounted) return;

    try {
      final moved = await _store.movePhotos(_selected.toList(), target.id);
      if (!mounted) return;
      setState(_selected.clear);
      showToast(
        context,
        moved == 1
            ? 'Moved 1 photo to "${target.name}".'
            : 'Moved $moved photos to "${target.name}".',
        kind: ToastKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'The photos could not be moved.', kind: ToastKind.error);
    }
  }

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  Widget _header(Palette p, PhotoFolder folder, List<VaultItem> photos) {
    if (_selecting) {
      return Row(
        children: [
          RoundIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Cancel',
            onPressed: () => setState(_selected.clear),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('${_selected.length} selected', style: AppText.title),
          ),
          RoundIconButton(
            icon: Icons.select_all_rounded,
            tooltip: 'Select all',
            onPressed: () => setState(() {
              _selected
                ..clear()
                ..addAll(photos.map((photo) => photo.id));
            }),
          ),
          const SizedBox(width: 8),
          RoundIconButton(
            icon: Icons.drive_file_move_rounded,
            tooltip: 'Move to folder',
            onPressed: _moveSelected,
          ),
          const SizedBox(width: 8),
          RoundIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            color: p.danger,
            onPressed: _deleteSelected,
          ),
        ],
      );
    }

    final totalBytes = photos.fold<int>(0, (sum, photo) => sum + photo.sizeBytes);
    return Row(
      children: [
        RoundIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: PageTitle(
            eyebrow: photos.isEmpty
                ? 'Own key'
                : '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'} · ${formatBytes(totalBytes)}',
            title: folder.name,
          ),
        ),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'Folder options',
          onPressed: () => showFolderMenu(
            context,
            folder,
            onDeleted: () {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _banner(Palette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: p.accent.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.accent.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_rounded, color: p.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This folder has its own key, and each photo has its own key '
              'locked by it. You see a photo\'s hidden data first, and it is '
              'removed and checked when you add it.',
              style: AppText.caption.copyWith(color: p.text),
            ),
          ),
          IconButton(
            tooltip: 'Hide',
            onPressed: () => setState(() => _bannerHidden = true),
            icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
          ),
        ],
      ),
    );
  }

  Widget _busyCard(Palette p) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_busyText!, style: AppText.subtitle.copyWith(fontSize: 14.5)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: const LinearProgressIndicator(minHeight: 6),
          ),
        ],
      ),
    );
  }

  Widget _body(Palette p, PhotoFolder folder) {
    final photos = _photos;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                _header(p, folder, photos),
                if (_busyText != null) ...[
                  const SizedBox(height: 16),
                  _busyCard(p),
                ] else if (!_bannerHidden && !_selecting) ...[
                  const SizedBox(height: 16),
                  _banner(p),
                ],
              ],
            ),
          ),
        ),
        if (photos.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.add_photo_alternate_rounded,
              color: folderColor(p, folder.colorIndex),
              title: 'No photos in this folder',
              message: 'Add photos you want to keep private. Each one is '
                  'previewed, stripped of hidden data and encrypted.',
              actionLabel: 'Add photos',
              onAction: _busyText == null ? _showAddSheet : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final photo = photos[index];
                  return _PhotoTile(
                    key: ValueKey<String>(photo.id),
                    item: photo,
                    media: _media,
                    selected: _selected.contains(photo.id),
                    selecting: _selecting,
                    onTap: () {
                      if (_selecting) {
                        _toggle(photo.id);
                      } else {
                        _open(photos, index);
                      }
                    },
                    onLongPress: () => _toggle(photo.id),
                  );
                },
                childCount: photos.length,
              ),
            ),
          ),
      ],
    );
  }

  /// The folder was deleted, or the vault locked. Leave this screen, unless
  /// the lock screen is already taking over.
  Widget _gone() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _security.isUnlocked && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return const Scaffold(body: SizedBox.shrink());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return ListenableBuilder(
      listenable: _store,
      builder: (context, child) {
        final folder = _store.folderById(widget.folderId);
        if (folder == null) return _gone();

        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, result) {
            // Back while photos are selected only clears the selection.
            if (!didPop) setState(_selected.clear);
          },
          child: Scaffold(
            body: SafeArea(bottom: false, child: _body(p, folder)),
            floatingActionButton: _selecting
                ? null
                : FloatingActionButton.extended(
                    onPressed: _busyText == null ? _showAddSheet : null,
                    backgroundColor: p.accent,
                    foregroundColor: const Color(0xFF031A18),
                    icon: const Icon(Icons.add_a_photo_rounded),
                    label: const Text(
                      'Add photos',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// One grid cell. It decrypts its own thumbnail once, when it first appears.
class _PhotoTile extends StatefulWidget {
  final VaultItem item;
  final MediaVaultService media;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PhotoTile({
    super.key,
    required this.item,
    required this.media,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  late final Future<Uint8List> _thumb = widget.media.readThumbnail(widget.item);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final radius = BorderRadius.circular(14);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: widget.selected ? 0.92 : 1,
        duration: const Duration(milliseconds: 150),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: p.surfaceAlt,
                child: FutureBuilder<Uint8List>(
                  future: _thumb,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Icon(Icons.broken_image_rounded, color: p.muted),
                      );
                    }
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              ),
              if (widget.selected)
                ColoredBox(color: p.primary.withAlpha(70)),
              if (widget.selecting)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected ? p.primary : Colors.black38,
                      border: Border.all(color: Colors.white, width: 1.6),
                    ),
                    child: widget.selected
                        ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
