import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'media_vault_service.dart';
import 'media_viewer_screen.dart';
import 'security_service.dart';
import 'vault_item.dart';

class MediaVaultScreen extends StatefulWidget {
  const MediaVaultScreen({super.key});

  @override
  State<MediaVaultScreen> createState() => _MediaVaultScreenState();
}

class _MediaVaultScreenState extends State<MediaVaultScreen> {
  final SecurityService _security = SecurityService();
  final MediaVaultService _media = MediaVaultService();
  final ImagePicker _picker = ImagePicker();

  List<VaultItem> _photos = [];
  bool _loading = true;
  String? _busyText; // set while photos are being encrypted

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final items = await _security.loadVaultItems();
      if (!mounted) return;
      setState(() {
        _photos = items.where((item) => item.isPhoto).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
        _loading = false;
      });
    } catch (_) {
      // The vault locked while loading. The lock screen takes over.
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
      _say('The gallery could not be opened.');
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
      _say('The camera could not be opened.');
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
        final all = await _security.loadVaultItems();
        all.addAll(imported.map((photo) => photo.item));
        await _security.saveVaultItems(all);
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
    await _loadPhotos();
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

  Future<void> _showReport(
    List<ImportedPhoto> imported,
    int failed,
    String? problem,
  ) async {
    if (!mounted) return;
    final lines = <String>[];
    if (imported.isNotEmpty) {
      final withLocation = imported.where((p) => p.report.hadLocation).length;
      final withCamera = imported.where((p) => p.report.hadCameraInfo).length;
      lines.add('${imported.length} photo(s) encrypted and saved.');
      lines.add('Hidden photo data (EXIF) was removed from every photo.');
      lines.add(withLocation > 0
          ? 'A GPS location was found and removed in $withLocation photo(s).'
          : 'No GPS location was found.');
      lines.add(withCamera > 0
          ? 'Camera make or model was found and removed in $withCamera photo(s).'
          : 'No camera details were found.');
      lines.add('Your original is still in the gallery. Delete it there if you do '
          'not want it to stay. KeyMaster cannot do that for you yet.');
    }
    if (failed > 0) {
      lines.add('$failed photo(s) could not be imported.');
      if (problem != null) lines.add(problem);
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import finished'),
        content: Text(lines.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Opening and deleting
  // ---------------------------------------------------------------

  Future<void> _open(VaultItem photo) async {
    final deleteIt = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => MediaViewerScreen(item: photo, media: _media),
      ),
    );
    if (deleteIt == true && mounted) await _deletePhoto(photo);
  }

  Future<void> _deletePhoto(VaultItem photo) async {
    try {
      final all = await _security.loadVaultItems();
      all.removeWhere((item) => item.id == photo.id);
      await _security.saveVaultItems(all); // the record, and its key, go first
      await _media.deletePhotoFiles(photo);
    } catch (_) {
      _say('The photo could not be deleted.');
      return;
    }
    await _loadPhotos();
    _say('Photo deleted.');
  }

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.tealAccent),
              title: const Text('Choose from gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _chooseFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.tealAccent),
              title: const Text('Take a photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _takePhoto();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_photos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No photos yet.\nTap the button to add one. Each photo is encrypted with its own key.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return GestureDetector(
          onTap: () => _open(photo),
          child: _ThumbTile(key: ValueKey(photo.id), item: photo, media: _media),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Vault'),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_busyText != null) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_busyText!, style: const TextStyle(color: Colors.grey)),
            ),
          ],
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent,
        onPressed: _busyText == null ? _showAddSheet : null,
        child: const Icon(Icons.add_a_photo, color: Colors.black),
      ),
    );
  }
}

/// One grid cell. It decrypts its own thumbnail once, when it first appears.
class _ThumbTile extends StatefulWidget {
  final VaultItem item;
  final MediaVaultService media;

  const _ThumbTile({super.key, required this.item, required this.media});

  @override
  State<_ThumbTile> createState() => _ThumbTileState();
}

class _ThumbTileState extends State<_ThumbTile> {
  late final Future<Uint8List> _thumb = widget.media.readThumbnail(widget.item);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: const Color(0xFF1E1E1E),
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
              return const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
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
    );
  }
}