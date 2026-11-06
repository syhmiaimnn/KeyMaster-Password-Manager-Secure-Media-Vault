import 'package:flutter/material.dart';

import 'confirm_pin_sheet.dart';
import 'key_tree.dart';
import 'media_vault_service.dart';
import 'photo_folder.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_store.dart';

// Shared by the Photos tab and the folder screen: make, edit, lock and delete
// a folder.

/// One of the six folder colours.
Color folderColor(Palette p, int index) {
  final colors = <Color>[
    p.accent,
    p.primary,
    p.violet,
    p.warning,
    p.success,
    p.danger,
  ];
  return colors[index.abs() % colors.length];
}

/// What the user typed in the folder editor.
class FolderDraft {
  final String name;
  final int colorIndex;
  final bool requiresPin;
  const FolderDraft(this.name, this.colorIndex, this.requiresPin);
}

/// Opens the folder editor. [existing] is the folder being edited, or null for
/// a new one. [others] are the other folders (names must not repeat).
Future<FolderDraft?> showFolderEditor(
  BuildContext context, {
  PhotoFolder? existing,
  required Iterable<PhotoFolder> others,
}) {
  final otherList = others.toList();
  return showAppSheet<FolderDraft>(
    context,
    builder: (sheetContext) => _FolderEditor(existing: existing, others: otherList),
  );
}

class _FolderEditor extends StatefulWidget {
  final PhotoFolder? existing;
  final List<PhotoFolder> others;
  const _FolderEditor({required this.existing, required this.others});

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late int _color = widget.existing?.colorIndex ?? 0;
  late bool _pin = widget.existing?.requiresPin ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final problem = PhotoFolder.validateName(_name.text, widget.others);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(FolderDraft(_name.text.trim(), _color, _pin));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final isNew = widget.existing == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isNew ? 'New folder' : 'Edit folder', style: AppText.title),
          const SizedBox(height: 6),
          Text(
            'Every folder gets its own key. The keys of the photos inside it '
            'are locked with that key.',
            style: AppText.caption.copyWith(color: p.muted),
          ),
          const SizedBox(height: 16),
          AppField(
            controller: _name,
            label: 'Folder name',
            icon: Icons.folder_rounded,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                _error!,
                style: AppText.caption.copyWith(
                  color: p.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text('COLOUR', style: AppText.overline.copyWith(color: p.muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < PhotoFolder.colorCount; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: folderColor(p, i),
                        border: Border.all(
                          color: _color == i ? p.text : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: _color == i
                          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pin,
            onChanged: (value) => setState(() => _pin = value),
            title: const Text(
              'Ask for my PIN to open',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'An extra check in the app each time the vault is unlocked. The '
              'folder key itself stays protected by your vault key.',
              style: AppText.caption.copyWith(color: p.muted),
            ),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: isNew ? 'Create folder' : 'Save',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Actions
// ---------------------------------------------------------------

/// Asks for a name and makes a new folder with its own key. Returns it, or
/// null if the user cancelled or saving failed.
Future<PhotoFolder?> createFolder(BuildContext context) async {
  final store = VaultStore.instance;
  final draft = await showFolderEditor(context, others: store.folders);
  if (draft == null || !context.mounted) return null;

  final folder = KeyTree().newFolder(
    draft.name,
    requiresPin: draft.requiresPin,
    colorIndex: draft.colorIndex,
  );
  try {
    await store.addFolder(folder);
  } catch (_) {
    if (context.mounted) {
      showToast(context, 'The folder could not be saved.', kind: ToastKind.error);
    }
    return null;
  }
  if (context.mounted) {
    showToast(context, 'Folder "${folder.name}" created.', kind: ToastKind.success);
  }
  return folder;
}

/// Changes the name, colour and PIN setting of a folder.
Future<void> editFolder(BuildContext context, PhotoFolder folder) async {
  final store = VaultStore.instance;
  final current = store.folderById(folder.id) ?? folder;
  final draft = await showFolderEditor(
    context,
    existing: current,
    others: store.folders.where((other) => other.id != current.id),
  );
  if (draft == null || !context.mounted) return;

  // Switching the PIN check off needs the PIN, or anyone holding the open
  // phone could remove it.
  if (current.requiresPin && !draft.requiresPin) {
    final ok = await confirmPin(
      context,
      title: 'Confirm your PIN',
      message: 'Enter your Master PIN to stop asking for it on this folder.',
    );
    if (!ok || !context.mounted) return;
  }

  try {
    await store.updateFolder(
      current.copyWith(
        name: draft.name,
        colorIndex: draft.colorIndex,
        requiresPin: draft.requiresPin,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showToast(context, 'The folder could not be saved.', kind: ToastKind.error);
    }
  }
}

/// Turns the PIN check of a folder on or off.
Future<void> togglePinGate(BuildContext context, PhotoFolder folder) async {
  final store = VaultStore.instance;
  final current = store.folderById(folder.id) ?? folder;

  if (current.requiresPin) {
    final ok = await confirmPin(
      context,
      title: 'Confirm your PIN',
      message: 'Enter your Master PIN to stop asking for it on this folder.',
    );
    if (!ok || !context.mounted) return;
  }

  try {
    await store.updateFolder(current.copyWith(requiresPin: !current.requiresPin));
  } catch (_) {
    if (context.mounted) {
      showToast(context, 'The folder could not be saved.', kind: ToastKind.error);
    }
    return;
  }
  if (context.mounted) {
    showToast(
      context,
      current.requiresPin
          ? 'This folder no longer asks for the PIN.'
          : 'This folder now asks for the PIN.',
      kind: ToastKind.success,
    );
  }
}

/// Deletes a folder with all its photos. The folder key goes first, so the
/// photos can no longer be opened even if a file is left behind. Returns true
/// when the folder is gone.
Future<bool> deleteFolder(BuildContext context, PhotoFolder folder) async {
  final store = VaultStore.instance;
  final count = store.photosIn(folder.id).length;

  // The folder screen closes as soon as the folder is gone, so the screen that
  // called this may no longer exist when the message is shown. Take what the
  // message needs now.
  final messenger = ScaffoldMessenger.of(context);
  final palette = Palette.of(context);
  void say(String text, ToastKind kind) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(buildToast(palette, text, kind: kind));
  }


  final ok = await confirmAction(
    context,
    title: 'Delete "${folder.name}"?',
    message: count == 0
        ? 'The folder and its key are removed.'
        : 'The folder, its key and the $count ${count == 1 ? 'photo' : 'photos'} '
            'inside it are removed. Without the folder key those photos can '
            'never be opened again. This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
    icon: Icons.delete_outline_rounded,
  );
  if (!ok || !context.mounted) return false;

  if (folder.requiresPin) {
    final pinOk = await confirmPin(
      context,
      title: 'Confirm your PIN',
      message: 'Enter your Master PIN to delete this folder.',
    );
    if (!pinOk || !context.mounted) return false;
  }

  try {
    // The folder record, and with it the key, goes first. Then the files.
    final doomed = await store.removeFolder(folder.id);
    final media = MediaVaultService();
    for (final photo in doomed) {
      await media.deletePhotoFiles(photo);
    }
  } catch (_) {
    say('The folder could not be deleted.', ToastKind.error);
    return false;
  }
  say('Folder deleted.', ToastKind.success);
  return true;
}

/// The options sheet of a folder. [onDeleted] runs after the folder is gone.
Future<void> showFolderMenu(
  BuildContext context,
  PhotoFolder folder, {
  VoidCallback? onDeleted,
}) {
  final store = VaultStore.instance;
  final photos = store.photosIn(folder.id);
  final bytes = photos.fold<int>(0, (sum, photo) => sum + photo.sizeBytes);

  return showAppSheet<void>(
    context,
    builder: (sheetContext) {
      final p = Palette.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folder.name,
              style: AppText.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Own key · ${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}'
              ' · ${formatBytes(bytes)}',
              style: AppText.caption.copyWith(color: p.muted),
            ),
            const SizedBox(height: 14),
            SettingGroup(
              children: [
                SettingTile(
                  icon: Icons.edit_rounded,
                  color: p.primary,
                  title: 'Rename or recolour',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    editFolder(context, folder);
                  },
                ),
                SettingTile(
                  icon: Icons.lock_outline_rounded,
                  color: p.violet,
                  title: 'Ask for PIN to open',
                  subtitle: folder.requiresPin ? 'On' : 'Off',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    togglePinGate(context, folder);
                  },
                ),
                SettingTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete folder',
                  subtitle: 'Removes its key and every photo inside',
                  danger: true,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final done = await deleteFolder(context, folder);
                    if (done) onDeleted?.call();
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
