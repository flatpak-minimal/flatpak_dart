/// Top-level entry point. Mirrors the `flatpak` CLI surface.
///
/// ```dart
/// final client = FlatpakClient.system();
/// final apps = await client.listApplications();
/// print('${apps.length} applications installed');
/// await client.close();
/// ```
import 'application.dart';
import 'installation.dart';
import 'permissions.dart';
import 'remote.dart';
import 'remote_manager.dart';
import 'transaction.dart';
import 'update_monitor.dart';

class FlatpakClient {
  final FlatpakInstallation _installation;
  final TransactionBridge _tx;
  final bool _isSystem;

  FlatpakClient._(this._installation, this._tx, this._isSystem);

  factory FlatpakClient.system() {
    final inst = FlatpakInstallation('system');
    return FlatpakClient._(inst, TransactionBridge.create('system'), true);
  }

  factory FlatpakClient.user() {
    final inst = FlatpakInstallation('user');
    return FlatpakClient._(inst, TransactionBridge.create('user'), false);
  }

  factory FlatpakClient.at(String path) {
    final inst = FlatpakInstallation(path);
    return FlatpakClient._(inst, TransactionBridge.create(path), false);
  }

  // ── Read operations (libflatpak — no D-Bus, no polkit) ────────────────

  /// List installed applications.
  Future<List<FlatpakApplication>> listApplications(
          {bool includeRuntimes = false}) =>
      _installation.listApplications(includeRuntimes: includeRuntimes);

  /// List configured remotes.
  Future<List<FlatpakRemote>> listRemotes() => _installation.listRemotes();

  /// Get detailed info for one application.
  Future<FlatpakApplication> info(String appId,
          {String arch = '', String branch = ''}) =>
      _installation.getAppInfo(appId, arch: arch, branch: branch);

  /// Get permission overrides for an application.
  Future<List<FlatpakPermission>> permissions(String appId) =>
      _installation.getPermissions(appId);

  /// Check which installed applications have updates available.
  Future<List<FlatpakRef>> checkForUpdates() =>
      _installation.checkForUpdates();

  // ── Write operations (libflatpak FlatpakTransaction serial queue) ───────

  /// Install an application from a remote.
  FlatpakTransaction install(String remote, String ref) =>
      _tx.install(remote, ref);

  /// Update an installed application. Pass empty string to update all.
  FlatpakTransaction update({String ref = ''}) => _tx.update(ref);

  /// Uninstall an application.
  FlatpakTransaction uninstall(String ref) => _tx.uninstall(ref);

  /// Install from a .flatpak bundle file.
  FlatpakTransaction installBundle(String bundlePath) =>
      _tx.installBundle(bundlePath);

  /// Build a multi-operation transaction.
  TransactionBuilder transaction() => TransactionBuilder._(_tx);

  // ── Remote management ────────────────────────────────────────────────

  late final FlatpakRemoteManager remotes = FlatpakRemoteManager.create(
    _installation,
    isSystem: _isSystem,
  );

  Future<void> close() async {
    _installation.close();
    _tx.close();
  }
}
