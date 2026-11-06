import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'intruder_payload.dart';
import 'intruder_service.dart';
import 'security_service.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

/// Settings > Intruder photos (FR13). Only the real vault can open this
/// screen.
///
/// Switch it on, and after five wrong PINs the front camera takes a photo.
/// The photo is locked with a public key (see sealed_box.dart), so it can be
/// taken while the app is locked, and only this screen, with the real vault
/// open, can unlock it again.
class IntruderLogScreen extends StatefulWidget {
  const IntruderLogScreen({super.key});

  @override
  State<IntruderLogScreen> createState() => _IntruderLogScreenState();
}

class _IntruderLogScreenState extends State<IntruderLogScreen> {
  final IntruderService _service = IntruderService.instance;
  final SecurityService _security = SecurityService();
  final AppSettings _settings = AppSettings.instance;

  IntruderKeys? _keys;
  List<IntruderEntry> _entries = const <IntruderEntry>[];
  // One decryption per photo, kept so the list does not redo it on redraw.
  final Map<String, Future<IntruderPayload?>> _opened =
      <String, Future<IntruderPayload?>>{};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keys?.clear();
    super.dispose();
  }

  Future<void> _load() async {
    IntruderKeys? keys;
    var entries = const <IntruderEntry>[];
    try {
      if (await _service.isSetUp()) {
        keys = await _service.loadKeys();
        entries = await _service.list();
      }
      await _service.markSeen();
    } catch (_) {
      // Shown as an empty list.
    }
    if (!mounted) {
      keys?.clear();
      return;
    }
    _keys?.clear();
    setState(() {
      _keys = keys;
      _entries = entries;
      _opened.clear();
      _loading = false;
    });
  }

  Future<IntruderPayload?> _payloadOf(IntruderEntry entry) {
    return _opened.putIfAbsent(entry.name, () async {
      final keys = _keys;
      if (keys == null) return null;
      try {
        return await _service.open(entry, keys);
      } catch (_) {
        return null; // damaged, or locked with another key
      }
    });
  }

  String _failText(CaptureResult result) {
    switch (result) {
      case CaptureResult.saved:
        return '';
      case CaptureResult.permissionDenied:
        return 'KeyMaster needs the camera permission. Allow it and try again.';
      case CaptureResult.noFrontCamera:
        return 'This phone has no front camera.';
      case CaptureResult.notReady:
        return 'Intruder photos are not set up yet.';
      case CaptureResult.busy:
        return 'A photo is already being taken. Try again in a moment.';
      case CaptureResult.failed:
        return 'The photo could not be taken. Close other camera apps and '
            'try again.';
    }
  }

  /// Takes a photo the same way the lock screen does. The Android permission
  /// dialog covers the app, so the auto-lock is paused while it runs.
  Future<CaptureResult> _takeTestPhoto() async {
    _security.pauseAutoLock();
    try {
      return await _service.capture(failedCount: 0);
    } finally {
      _security.resumeAutoLock();
    }
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;

    if (!on) {
      await _settings.setIntruderOn(false);
      if (!mounted) return;
      showToast(context, 'Intruder photos are off.', kind: ToastKind.success);
      return;
    }

    setState(() => _busy = true);
    var result = CaptureResult.failed;
    try {
      await _service.setUp();
      // A test photo proves that the camera, the permission and the locking
      // all work on this phone before the feature is switched on.
      result = await _takeTestPhoto();
    } catch (_) {
      result = CaptureResult.failed;
    }
    if (!mounted) return;

    if (result != CaptureResult.saved) {
      setState(() => _busy = false);
      showToast(context, _failText(result), kind: ToastKind.warning);
      return;
    }

    await _settings.setIntruderOn(true);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(
      context,
      'Intruder photos are on. A test photo was saved below.',
      kind: ToastKind.success,
    );
  }

  Future<void> _test() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _takeTestPhoto();
    if (result == CaptureResult.saved) await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(
      context,
      result == CaptureResult.saved
          ? 'Test photo saved below.'
          : _failText(result),
      kind: result == CaptureResult.saved ? ToastKind.success : ToastKind.warning,
    );
  }

  Future<void> _deleteOne(IntruderEntry entry) async {
    await _service.delete(entry);
    await _load();
  }

  Future<void> _deleteAll() async {
    final sure = await confirmAction(
      context,
      title: 'Delete all intruder photos?',
      message: 'The ${_entries.length} saved '
          '${_entries.length == 1 ? 'photo is' : 'photos are'} deleted from this '
          'phone. This cannot be undone.',
      confirmLabel: 'Delete all',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!sure || !mounted) return;
    await _service.deleteAll();
    await _load();
  }

  String _why(IntruderPayload payload) {
    if (payload.isTest) return 'Test photo';
    final count = payload.failedCount;
    return 'After $count wrong PINs';
  }

  Future<void> _view(IntruderEntry entry, IntruderPayload payload) async {
    final p = Palette.of(context);
    final delete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  child: Image.memory(
                    payload.jpeg,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => Container(
                      height: 160,
                      alignment: Alignment.center,
                      color: p.surfaceAlt,
                      child: Text(
                        'This photo cannot be shown.',
                        style: AppText.caption.copyWith(color: p.muted),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(formatDateTime(payload.time), style: AppText.subtitle),
              const SizedBox(height: 2),
              Text(
                '${_why(payload)} · ${timeAgo(payload.time)}',
                style: AppText.caption.copyWith(color: p.muted),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text('Delete', style: TextStyle(color: p.danger)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text('Close', style: TextStyle(color: p.primary)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (delete == true) await _deleteOne(entry);
  }

  Widget _tile(Palette p, IntruderEntry entry) {
    return FutureBuilder<IntruderPayload?>(
      future: _payloadOf(entry),
      builder: (context, snapshot) {
        final payload = snapshot.data;
        final waiting = snapshot.connectionState != ConnectionState.done;

        Widget picture;
        if (payload != null) {
          picture = Image.memory(
            payload.jpeg,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            cacheWidth: 160,
            errorBuilder: (context, error, stack) => Icon(
              Icons.broken_image_outlined,
              color: p.muted,
            ),
          );
        } else if (waiting) {
          picture = const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else {
          picture = Icon(Icons.lock_outline_rounded, color: p.muted);
        }

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: payload == null ? null : () => _view(entry, payload),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    color: p.surfaceAlt,
                    child: picture,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDateTime(payload?.time ?? entry.modified),
                        style: AppText.subtitle.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        payload == null
                            ? (waiting ? 'Unlocking...' : 'Cannot be opened')
                            : _why(payload),
                        style: AppText.caption.copyWith(
                          color: payload == null ? p.warning : p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _deleteOne(entry),
                  icon: Icon(Icons.delete_outline_rounded, color: p.muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _settings,
          builder: (context, child) {
            final on = _settings.intruderOn;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const PageTitle(eyebrow: 'Who tried?', title: 'Intruder photos'),
                const SizedBox(height: 14),
                Text(
                  'After five wrong PINs, the front camera takes a photo. It '
                  'is saved locked, and only you can open it here.',
                  style: AppText.body.copyWith(color: p.muted),
                ),
                const SizedBox(height: 18),
                SettingGroup(
                  children: [
                    SettingTile(
                      icon: Icons.camera_front_rounded,
                      color: p.danger,
                      title: 'Photo after wrong PINs',
                      subtitle: on
                          ? 'On. Every wrong PIN from the fifth one on.'
                          : 'Off. The camera permission is asked when you '
                              'switch it on.',
                      onTap: _busy ? null : () => _toggle(!on),
                      trailing: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : Switch(value: on, onChanged: _toggle),
                    ),
                  ],
                ),
                if (on) ...[
                  const SizedBox(height: 10),
                  SoftButton(
                    label: 'Take a test photo',
                    icon: Icons.camera_alt_rounded,
                    onPressed: _busy ? null : _test,
                  ),
                ],
                SectionLabel(
                  _entries.isEmpty
                      ? 'Saved photos'
                      : 'Saved photos (${_entries.length} of '
                          '${IntruderService.maxPhotos})',
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_entries.isEmpty)
                  AppCard(
                    child: Text(
                      'No photos yet. That is good news: nobody has entered a '
                      'wrong PIN five times.',
                      style: AppText.body.copyWith(color: p.muted),
                    ),
                  )
                else ...[
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _entries.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 90,
                              color: p.border,
                            ),
                          _tile(p, _entries[i]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: SoftButton(
                      label: 'Delete all photos',
                      icon: Icons.delete_outline_rounded,
                      onPressed: _busy ? null : _deleteAll,
                    ),
                  ),
                ],
                const SectionLabel('Honest limits'),
                const InfoBanner(
                  icon: Icons.info_outline_rounded,
                  text: 'Android 12 and newer show a small green dot while the '
                      'camera is on, so a careful person can see it. If you '
                      'take the camera permission away later, Android may ask '
                      'for it again on the lock screen, so switch the feature '
                      'off first. The camera cannot be used while another app '
                      'holds it. Only the last 20 photos are kept. A photo '
                      'is taken for every wrong PIN from the fifth on, but '
                      'not while the lock timer is running.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
