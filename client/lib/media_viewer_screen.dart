import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'clean_share_service.dart';
import 'media_vault_service.dart';
import 'metadata_analysis.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_item.dart';

/// Full-screen photo viewer: swipe between photos, pinch or double-tap to
/// zoom, tap to hide the controls. Photos are decrypted in memory only.
class MediaViewerScreen extends StatefulWidget {
  final List<VaultItem> photos;
  final int initialIndex;
  final MediaVaultService media;

  /// Deletes the record and the files. Returns true when it worked.
  final Future<bool> Function(VaultItem photo) onDelete;

  const MediaViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.media,
    required this.onDelete,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late final List<VaultItem> _photos = List<VaultItem>.of(widget.photos);
  late int _index = widget.initialIndex;

  final CleanShareService _sharer = CleanShareService();

  bool _zoomed = false;
  bool _chrome = true; // are the top and bottom bars visible?
  bool _deleting = false;
  bool _sharing = false;

  @override
  void dispose() {
    _controller.dispose();
    // Let go of the decrypted pictures. Dart cannot wipe memory for certain,
    // so this is best effort.
    imageCache.clear();
    imageCache.clearLiveImages();
    super.dispose();
  }

  Future<void> _delete() async {
    final photo = _photos[_index];
    final ok = await confirmAction(
      context,
      title: 'Delete this photo?',
      message: 'The encrypted copy and its key are removed from KeyMaster. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    setState(() => _deleting = true);
    final done = await widget.onDelete(photo);
    if (!mounted) return;

    if (!done) {
      setState(() => _deleting = false);
      showToast(context, 'The photo could not be deleted.', kind: ToastKind.error);
      return;
    }
    if (_photos.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _photos.removeAt(_index);
      if (_index >= _photos.length) _index = _photos.length - 1;
      _deleting = false;
    });
  }

  /// Decrypts the photo, checks it once more for hidden data, and hands the
  /// clean copy to the share sheet.
  Future<void> _share() async {
    final photo = _photos[_index];
    final ok = await confirmAction(
      context,
      title: 'Share a clean copy?',
      message: 'KeyMaster makes a copy with no hidden data, checks it, and '
          'opens the share sheet. The app you choose keeps that copy, and '
          'KeyMaster can no longer control it. Nothing in your vault '
          'changes.',
      confirmLabel: 'Share',
      icon: Icons.share_rounded,
    );
    if (!ok || !mounted) return;

    setState(() => _sharing = true);
    try {
      final copy = await widget.media.exportCleanCopy(photo);
      if (!mounted) return;
      await _sharer.shareJpeg(copy.bytes);
      if (!mounted) return;
      final left = copy.check.hiddenFieldCount;
      showToast(
        context,
        left == 0
            ? 'Clean copy checked: 0 hidden fields.'
            : 'Clean copy checked: nothing that identifies you or the place.',
        kind: ToastKind.success,
      );
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        error is MediaVaultException
            ? error.message
            : 'The photo could not be shared.',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static IconData _iconFor(MetaCategory category) {
    return switch (category) {
      MetaCategory.location => Icons.location_on_rounded,
      MetaCategory.owner => Icons.badge_rounded,
      MetaCategory.time => Icons.schedule_rounded,
      MetaCategory.device => Icons.smartphone_rounded,
      MetaCategory.thumbnail => Icons.photo_size_select_small_rounded,
      MetaCategory.other => Icons.more_horiz_rounded,
      MetaCategory.settings => Icons.tune_rounded,
      MetaCategory.image => Icons.image_rounded,
    };
  }

  /// What was removed from this photo when it was saved. Names only.
  void _showReport() {
    final photo = _photos[_index];
    final grouped = MetadataAnalysis.groupStored(photo.sanitizedTags);

    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final p = Palette.of(sheetContext);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Privacy report', style: AppText.title),
              const SizedBox(height: 6),
              Text(
                grouped.isEmpty
                    ? 'No removed fields are recorded for this photo. Either it '
                        'had no hidden data, or it was saved by an older version '
                        'of KeyMaster, which cleaned it but did not keep a list.'
                    : 'These hidden fields were removed before the photo was '
                        'saved. Only their names are kept, never the values.',
                style: AppText.caption.copyWith(color: p.muted),
              ),
              const SizedBox(height: 16),
              for (final category in MetaCategory.values)
                if (grouped[category] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBadge(
                          icon: _iconFor(category),
                          color: p.accent,
                          size: 34,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                MetadataAnalysis.titleOf(category),
                                style: AppText.subtitle.copyWith(fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                grouped[category]!.join(' · '),
                                style: AppText.caption.copyWith(color: p.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              InfoBanner(
                icon: Icons.verified_rounded,
                color: p.success,
                text: 'Each photo is read back after cleaning, and a clean '
                    'copy is checked again just before it is shared.',
              ),
              const SizedBox(height: 16),
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

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photos[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: _photos.length,
            onPageChanged: (value) => setState(() {
              _index = value;
              _zoomed = false;
            }),
            itemBuilder: (context, i) => _PhotoPage(
              key: ValueKey<String>(_photos[i].id),
              photo: _photos[i],
              media: widget.media,
              onTap: () => setState(() => _chrome = !_chrome),
              onZoomChanged: (zoomed) {
                if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
              },
            ),
          ),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    MediaQuery.paddingOf(context).top + 4,
                    8,
                    20,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          '${_index + 1} of ${_photos.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Privacy report',
                        icon: Icon(
                          Icons.privacy_tip_rounded,
                          color: _deleting ? Colors.white38 : Colors.white,
                        ),
                        onPressed: _deleting ? null : _showReport,
                      ),
                      IconButton(
                        tooltip: 'Share a clean copy',
                        icon: _sharing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                Icons.share_rounded,
                                color: _deleting ? Colors.white38 : Colors.white,
                              ),
                        onPressed: _deleting || _sharing ? null : _share,
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: _deleting ? Colors.white38 : Colors.redAccent,
                        ),
                        onPressed: _deleting || _sharing ? null : _delete,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    28,
                    16,
                    MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        photo.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(Icons.storage_rounded, formatBytes(photo.sizeBytes)),
                          _chip(Icons.event_rounded, formatDate(photo.createdAt)),
                          _chip(Icons.lock_rounded, 'Own key'),
                          _chip(Icons.location_off_rounded, 'No hidden data'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One page of the viewer. It decrypts its photo once.
class _PhotoPage extends StatefulWidget {
  final VaultItem photo;
  final MediaVaultService media;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  const _PhotoPage({
    super.key,
    required this.photo,
    required this.media,
    required this.onTap,
    required this.onZoomChanged,
  });

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  late final Future<Uint8List> _bytes = widget.media.readPhoto(widget.photo);
  final TransformationController _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.02;

  void _onTransform() => widget.onZoomChanged(_isZoomed);

  void _doubleTap() {
    if (_isZoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    final size = context.size;
    if (size == null) return;
    const scale = 2.5;
    final dx = -size.width * (scale - 1) / 2;
    final dy = -size.height * (scale - 1) / 2;
    // Zoom in around the middle of the screen
    _transform.value =
        Matrix4(scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: _doubleTap,
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This photo could not be decrypted. '
                  'Its file may be missing or damaged.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          );
        },
      ),
    );
  }
}
