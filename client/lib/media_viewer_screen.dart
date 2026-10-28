import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'media_vault_service.dart';
import 'ui/format.dart';
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

  bool _zoomed = false;
  bool _chrome = true; // are the top and bottom bars visible?
  bool _deleting = false;

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
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: _deleting ? Colors.white38 : Colors.redAccent,
                        ),
                        onPressed: _deleting ? null : _delete,
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
