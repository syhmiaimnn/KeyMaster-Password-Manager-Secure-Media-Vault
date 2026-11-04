import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'media_vault_service.dart';
import 'media_viewer_screen.dart';
import 'security_service.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_item.dart';
import 'vault_store.dart';

/// The Photos tab: a grid of encrypted photos. Long-press to select several.
class MediaVaultScreen extends StatefulWidget {
  const MediaVaultScreen({super.key});

  @override
  State<MediaVaultScreen> createState() => _MediaVaultScreenState();
}

class _MediaVaultScreenState extends State<MediaVaultScreen> {
  final SecurityService _security = SecurityService();
  final VaultStore _store = VaultStore.instance;
  final MediaVaultService _media = MediaVaultService();
  final ImagePicker _picker = ImagePicker();

  final Set<String> _selected = <String>{};
  String? _busyText; // set while photos are being encrypted
  bool _bannerHidden = false;

  bool get _selecting => _selected.isNotEmpty;

  List<VaultItem> get _photos {
    return _store.photos..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

    final imported = <ImportedPhoto>[];
    var failed = 0;
    String? firstProblem;

    for (var i = 0; i < files.length; i++) {
      if (!mounted) {
        await _discard(imported);
        return;
      }
      setState(() => _busyText = 'Encrypting photo ${i + 1} of ${files.length}...');
      try {
        final bytes = await files[i].readAsBytes();
        imported.add(await _media.importPhoto(bytes));
      } catch (error) {
        failed++;
        firstProblem ??= error is MediaVaultException ? error.message : null;
      } finally {
        await _deleteTempCopy(files[i]);
      }
    }

    if (imported.isNotEmpty) {
      try {
        await _store.addAll(imported.map((photo) => photo.item));
      } catch (_) {
        // The records were not saved, so the files would have no key.
        await _discard(imported);
        failed += imported.length;
        imported.clear();
        firstProblem = 'The vault could not be saved. Please try again.';
      }
    }

    if (!mounted) return;
    setState(() => _busyText = null);
    await _showReport(imported, failed, firstProblem);
  }

  Future<void> _discard(List<ImportedPhoto> photos) async {
    for (final photo in photos) {
      await _media.deletePhotoFiles(photo.item);
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

  Future<void> _showReport(
    List<ImportedPhoto> imported,
    int failed,
    String? problem,
  ) async {
    if (!mounted) return;
    final withLocation = imported.where((photo) => photo.report.hadLocation).length;
    final withCamera = imported.where((photo) => photo.report.hadCameraInfo).length;
    final tagCount = imported.fold<int>(0, (sum, photo) => sum + photo.report.tagCount);

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
                  Icons.cleaning_services_rounded,
                  p.accent,
                  tagCount > 0
                      ? 'Hidden photo data (EXIF) removed: $tagCount fields.'
                      : 'Hidden photo data (EXIF) removed from every photo.',
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
                  withCamera > 0 ? p.warning : p.success,
                  withCamera > 0
                      ? 'Camera make or model was found and removed in $withCamera photo(s).'
                      : 'No camera details were found.',
                ),
                InfoBanner(
                  icon: Icons.info_outline_rounded,
                  text: 'Your original is still in the gallery. Delete it '
                      'there if you do not want it to stay. KeyMaster cannot '
                      'do that for you yet.',
                ),
              ],
              if (failed > 0) ...[
                const SizedBox(height: 14),
                _reportRow(
                  p,
                  Icons.error_outline_rounded,
                  p.danger,
                  problem == null
                      ? '$failed photo(s) could not be imported.'
                      : '$failed photo(s) could not be imported. $problem',
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
                'They are encrypted and cleaned of hidden data before they are saved.',
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
  // Opening, selecting, deleting
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

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  Widget _header(Palette p, List<VaultItem> photos) {
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
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            color: p.danger,
            onPressed: _deleteSelected,
          ),
        ],
      );
    }

    final totalBytes = photos.fold<int>(0, (sum, photo) => sum + photo.sizeBytes);
    return PageTitle(
      eyebrow: photos.isEmpty
          ? 'Encrypted gallery'
          : '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'} · ${formatBytes(totalBytes)}',
      title: 'Photos',
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
              'Each photo has its own key. Location and camera details are '
              'removed when you add it.',
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

  Widget _body(Palette p) {
    final photos = _photos;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                _header(p, photos),
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
              color: p.accent,
              title: 'No photos yet',
              message: 'Add photos you want to keep private. They are '
                  'encrypted one by one and stripped of hidden data.',
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
