import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'password_tools.dart';
import 'security_service.dart';
import 'vault_item.dart';

/// The one in-memory copy of the vault that every screen shares.
///
/// Before Phase 3 each screen loaded the list, changed it and saved it. Two
/// screens could then overwrite each other's changes. Now every change goes
/// through this class, which keeps the list in memory, tells the screens
/// (so they redraw) and saves the encrypted list in order.
class VaultStore extends ChangeNotifier {
  VaultStore._();
  static final VaultStore instance = VaultStore._();

  final SecurityService _security = SecurityService();

  List<VaultItem> _items = [];
  bool _loaded = false;
  String? _loadError;

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

  /// Decrypts the list from storage. Call it after every unlock.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      _items = await _security.loadVaultItems();
      _loaded = true;
      _loadError = null;
    } catch (_) {
      _loadError = 'The vault could not be opened.';
    }
    notifyListeners();
  }

  Future<void> add(VaultItem item) => _commit([..._items, item]);

  Future<void> addAll(Iterable<VaultItem> items) =>
      _commit([..._items, ...items]);

  Future<void> update(VaultItem item) {
    return _commit([
      for (final existing in _items) existing.id == item.id ? item : existing,
    ]);
  }

  Future<void> remove(String id) => removeMany([id]);

  Future<void> removeMany(Iterable<String> ids) {
    final gone = ids.toSet();
    return _commit(_items.where((item) => !gone.contains(item.id)).toList());
  }

  Future<void> toggleFavorite(String id) {
    final item = byId(id);
    if (item == null) return Future<void>.value();
    return update(item.copyWith(favorite: !item.favorite));
  }

  /// Forget everything in memory. Called when the app locks.
  void clear() {
    _items = [];
    _loaded = false;
    _loadError = null;
    notifyListeners();
  }

  /// Show the change at once, then save it. If saving fails the screen goes
  /// back to how it was and the error is passed on to the caller.
  Future<void> _commit(List<VaultItem> next) async {
    final previous = _items;
    _items = next;
    notifyListeners();
    try {
      await _write(next);
    } catch (_) {
      _items = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _write(List<VaultItem> snapshot) {
    final job = _queue.then((_) => _security.saveVaultItems(snapshot));
    _queue = job.catchError((Object _) {});
    return job;
  }
}
