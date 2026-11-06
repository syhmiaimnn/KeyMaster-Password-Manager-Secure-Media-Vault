import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'key_tree.dart';
import 'password_tools.dart';
import 'photo_folder.dart';
import 'security_service.dart';
import 'vault_data.dart';
import 'vault_item.dart';

/// The one in-memory copy of the vault that every screen shares.
///
/// Before Phase 3 each screen loaded the list, changed it and saved it. Two
/// screens could then overwrite each other's changes. Now every change goes
/// through this class, which keeps the list in memory, tells the screens
/// (so they redraw) and saves the encrypted data in order.
///
/// Since Phase 6 it also holds the photo folders. Items and folders are always
/// saved together, so a photo record and the folder key that opens it can
/// never be saved out of step.
class VaultStore extends ChangeNotifier {
  VaultStore._();
  static final VaultStore instance = VaultStore._();

  final SecurityService _security = SecurityService();
  final KeyTree _tree = KeyTree();

  List<VaultItem> _items = [];
  List<PhotoFolder> _folders = [];
  bool _loaded = false;
  String? _loadError;

  // Folders that asked for the PIN and got it right. Forgotten when the app
  // locks.
  final Set<String> _openFolders = <String>{};

  // Saves run one after another, so the last change always wins.
  Future<void> _queue = Future<void>.value();

  bool get isLoaded => _loaded;
  String? get loadError => _loadError;

  List<VaultItem> get items => List<VaultItem>.unmodifiable(_items);
  List<VaultItem> get logins =>
      _items.where((item) => item.type == 'Password').toList();
  List<VaultItem> get notes =>
      _items.where((item) => item.type == 'Note').toList();
  List<VaultItem> get photos => _items.where((item) => item.isPhoto).toList();

  // ---------------------------------------------------------------
  // Folders (read)
  // ---------------------------------------------------------------

  List<PhotoFolder> get folders => List<PhotoFolder>.unmodifiable(_folders);

  PhotoFolder? folderById(String id) {
    for (final folder in _folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  /// The first folder. Photos go here when no folder is named, and photos from
  /// before Phase 6 were moved here.
  PhotoFolder? get defaultFolder => _folders.isEmpty ? null : _folders.first;

  /// The photo records in one folder.
  ///
  /// A photo whose folder cannot be found (it should not happen) is shown in
  /// the first folder, so a photo can never become invisible.
  List<VaultItem> photosIn(String folderId) {
    final homeId = defaultFolder?.id;
    return _items.where((item) {
      if (!item.isPhoto) return false;
      if (item.folderId == folderId) return true;
      return folderId == homeId && folderById(item.folderId) == null;
    }).toList();
  }

  /// False only for a folder that asks for the PIN and has not had it yet.
  bool isFolderOpen(PhotoFolder folder) {
    return !folder.requiresPin || _openFolders.contains(folder.id);
  }

  /// Call after the PIN was checked for [folderId].
  void markFolderOpen(String folderId) {
    _openFolders.add(folderId);
  }

  /// Looks at every password and at the device settings. Cheap enough to call
  /// whenever a screen is drawn.
  SecurityReport report() {
    final settings = AppSettings.instance;
    return SecurityReport.analyze(
      _items,
      biometricOn: settings.biometricOn,
      autoLockSeconds: settings.autoLockSeconds,
      screenshotsBlocked: settings.blockScreenshots,
      clipboardSeconds: settings.clipboardSeconds,
    );
  }

  VaultItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Load
  // ---------------------------------------------------------------

  /// Decrypts the data from storage. Call it after every unlock.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final data = await _security.loadVaultData();
      _items = data.items;
      _folders = data.folders;
      _loaded = true;
      _loadError = null;
    } catch (_) {
      _loadError = 'The vault could not be opened.';
      notifyListeners();
      return;
    }

    try {
      await _prepareFolders();
    } catch (_) {
      // The vault itself opened. If this step could not save, it runs again
      // at the next unlock, and photos from before Phase 6 still open.
    }
    notifyListeners();
  }

  /// Makes sure there is at least one folder, and that every photo is in one.
  ///
  /// A vault from before Phase 6 has photos with plain keys and no folders.
  /// The first time it is opened, a first folder is created and each photo key
  /// is locked with that folder's key. The photo files are not touched.
  Future<void> _prepareFolders() async {
    var changed = false;

    if (_folders.isEmpty) {
      _folders = [_tree.newFolder('My photos')];
      changed = true;
    }
    final home = _folders.first;

    final next = <VaultItem>[];
    for (final item in _items) {
      final plainKey = item.isPhoto &&
          item.fileKey.isNotEmpty &&
          !KeyTree.isWrapped(item.fileKey);
      if (plainKey) {
        next.add(await _tree.adopt(item, home));
        changed = true;
      } else {
        next.add(item);
      }
    }

    if (!changed) return;
    _items = next;
    await _write(VaultData(_items, _folders));
  }

  // ---------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------

  Future<void> add(VaultItem item) => _commit(items: [..._items, item]);

  Future<void> addAll(Iterable<VaultItem> items) =>
      _commit(items: [..._items, ...items]);

  Future<void> update(VaultItem item) {
    return _commit(items: [
      for (final existing in _items) existing.id == item.id ? item : existing,
    ]);
  }

  /// Replaces several items in one save.
  Future<void> updateMany(Iterable<VaultItem> changed) {
    final byId = <String, VaultItem>{for (final item in changed) item.id: item};
    return _commit(items: [
      for (final existing in _items) byId[existing.id] ?? existing,
    ]);
  }

  Future<void> remove(String id) => removeMany([id]);

  Future<void> removeMany(Iterable<String> ids) {
    final gone = ids.toSet();
    return _commit(
      items: _items.where((item) => !gone.contains(item.id)).toList(),
    );
  }

  Future<void> toggleFavorite(String id) {
    final item = byId(id);
    if (item == null) return Future<void>.value();
    return update(item.copyWith(favorite: !item.favorite));
  }

  // ---------------------------------------------------------------
  // Folders (change)
  // ---------------------------------------------------------------

  Future<void> addFolder(PhotoFolder folder) {
    return _commit(folders: [..._folders, folder]);
  }

  Future<void> updateFolder(PhotoFolder folder) {
    return _commit(folders: [
      for (final existing in _folders)
        existing.id == folder.id ? folder : existing,
    ]);
  }

  /// Deletes a folder and the records of the photos in it, in ONE save. The
  /// folder key is gone as soon as this finishes, so those photos can never be
  /// opened again, even if a file is left behind. Returns the removed photo
  /// records, so the caller can delete their files.
  Future<List<VaultItem>> removeFolder(String folderId) async {
    final doomed = photosIn(folderId);
    final doomedIds = doomed.map((photo) => photo.id).toSet();
    await _commit(
      items: _items.where((item) => !doomedIds.contains(item.id)).toList(),
      folders: _folders.where((folder) => folder.id != folderId).toList(),
    );
    _openFolders.remove(folderId);
    return doomed;
  }

  /// Moves photos to another folder. Only the photo keys are locked again, with
  /// the key of the new folder, and saved in one write. The photo files are
  /// not touched. Returns how many photos moved.
  Future<int> movePhotos(Iterable<String> photoIds, String toFolderId) async {
    final target = folderById(toFolderId);
    if (target == null) throw StateError('The target folder does not exist.');

    final wanted = photoIds.toSet();
    final changed = <VaultItem>[];
    for (final item in _items) {
      if (!wanted.contains(item.id)) continue;
      if (!item.isPhoto || item.folderId == toFolderId) continue;
      changed.add(
        await _tree.moveToFolder(item, folderById(item.folderId), target),
      );
    }
    if (changed.isEmpty) return 0;
    await updateMany(changed);
    return changed.length;
  }

  // ---------------------------------------------------------------
  // Lock and save
  // ---------------------------------------------------------------

  /// Forget everything in memory. Called when the app locks.
  void clear() {
    _items = [];
    _folders = [];
    _openFolders.clear();
    _loaded = false;
    _loadError = null;
    notifyListeners();
  }

  /// Show the change at once, then save it. If saving fails the screen goes
  /// back to how it was and the error is passed on to the caller.
  Future<void> _commit({
    List<VaultItem>? items,
    List<PhotoFolder>? folders,
  }) async {
    final previousItems = _items;
    final previousFolders = _folders;
    _items = items ?? _items;
    _folders = folders ?? _folders;
    notifyListeners();
    try {
      await _write(VaultData(_items, _folders));
    } catch (_) {
      _items = previousItems;
      _folders = previousFolders;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _write(VaultData snapshot) {
    final job = _queue.then((_) => _security.saveVaultData(snapshot));
    _queue = job.catchError((Object _) {});
    return job;
  }
}
