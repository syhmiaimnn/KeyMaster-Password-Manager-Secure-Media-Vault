import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'media_vault_service.dart';
import 'vault_item.dart';

/// Shows one photo. Pops with true when the user confirms a delete.
class MediaViewerScreen extends StatefulWidget {
  final VaultItem item;
  final MediaVaultService media;

  const MediaViewerScreen({
    super.key,
    required this.item,
    required this.media,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decrypt();
  }

  Future<void> _decrypt() async {
    try {
      final bytes = await widget.media.readPhoto(widget.item);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'This photo could not be decrypted. '
            'Its file may be missing or damaged.';
      });
    }
  }

  @override
  void dispose() {
    // Let go of the decrypted picture. Dart cannot wipe memory for certain,
    // so this is best effort.
    _bytes = null;
    imageCache.clear();
    imageCache.clearLiveImages();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text(
          'The encrypted copy and its key are removed from KeyMaster. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  String get _sizeText {
    final kb = widget.item.sizeBytes / 1024;
    return kb >= 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB'
        : '${kb.round()} KB';
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: Text(widget.item.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '$_sizeText - own encryption key, hidden photo data removed',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ),
    );
  }
}