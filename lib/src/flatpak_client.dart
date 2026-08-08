/// Top-level entry point. Mirrors the `flatpak` CLI surface.
///
/// ```dart
/// final client = FlatpakClient.system();
/// final apps = await client.listApplications();
/// print('${apps.length} applications installed');
/// await client.close();
/// ```
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'application.dart';
import 'appstream/catalog.dart';
import 'exceptions.dart';
import 'ffi/bindings.dart';
import 'ffi/codec.dart' show MetadataEntry;
import 'installation.dart';
import 'installation_info.dart';
import 'instance.dart';
import 'permissions.dart';
import 'portal/permission_flow.dart';
import 'portal/permission_store.dart';
import 'remote.dart';
import 'remote_manager.dart';
import 'storage_info.dart';
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
  Future<List<FlatpakApplication>> listApplications({
    bool includeRuntimes = false,
  }) => _installation.listApplications(includeRuntimes: includeRuntimes);

  /// List configured remotes.
  Future<List<FlatpakRemote>> listRemotes() => _installation.listRemotes();

  /// Get detailed info for one application.
  Future<FlatpakApplication> info(
    String appId, {
    String arch = '',
    String branch = '',
  }) => _installation.getAppInfo(appId, arch: arch, branch: branch);

  /// Get permission overrides for an application.
  Future<List<FlatpakPermission>> permissions(String appId) =>
      _installation.getPermissions(appId);

  /// Fetch metadata (sandbox permissions) for a remote ref before installing.
  /// Returns parsed key-value entries from the `Context`, `Session Bus Policy`,
  /// `System Bus Policy`, and `Environment` sections of the app's metadata.
  Future<List<MetadataEntry>> fetchRemoteMetadata(String remote, String ref) =>
      _installation.fetchRemoteMetadata(remote, ref);

  /// Check which installed applications have updates available.
  Future<List<FlatpakRef>> checkForUpdates() => _installation.checkForUpdates();

  // ── App lifecycle (libflatpak launch / instances) ──────────────────────

  /// Launch an installed application in its sandbox ("tap to open").
  /// Pass empty [arch]/[branch]/[commit] to use the installed defaults.
  /// Returns the [FlatpakInstance] libflatpak created for the launch.
  ///
  /// [FlatpakInstance.childPid] is best-effort — `0` if the app exits before
  /// bwrap publishes it. Every other field is always populated.
  Future<FlatpakInstance> launch(
    String appId, {
    String arch = '',
    String branch = '',
    String commit = '',
  }) => _installation.launch(appId, arch: arch, branch: branch, commit: commit);

  /// Stop every running instance of [appId] across the host. Flatpak
  /// instances are not scoped to an installation, so this stops matching
  /// instances regardless of whether they were launched from the user or
  /// system installation.
  ///
  /// Returns once SIGTERM has been sent; grace period + SIGKILL escalation
  /// continue in the background.
  ///
  /// Throws [FlatpakNotFoundException] if nothing matched, or
  /// [FlatpakStopException] if instances matched but none could be signalled.
  Future<void> stop(String appId) => _installation.stop(appId);

  /// List running sandbox instances across the host.
  Future<List<FlatpakInstance>> listRunning() => _installation.listRunning();

  // ── AppStream catalog + icons ─────────────────────────────────────────

  /// AppStream metadata (icons, screenshots, releases) and installed-app
  /// icon resolution, backed by the appstream_dart engine.
  late final FlatpakAppStream appStream = FlatpakAppStream.forName(
    _installation,
  );

  // ── Portal permissions (xdg-desktop-portal PermissionStore) ────────────

  PermissionStorePortal? _permissionsStore;

  /// xdg-desktop-portal PermissionStore client (session bus). Persists per-app
  /// permission decisions for devices, location, notifications, background.
  PermissionStorePortal get permissionsStore =>
      _permissionsStore ??= PermissionStorePortal();

  PermissionFlow? _permissionFlow;

  /// Launch-time permission prompts. Listen to [PermissionFlow.requests] and
  /// call `respond()`; decisions persist via [permissionsStore].
  PermissionFlow get permissionFlow =>
      _permissionFlow ??= PermissionFlow(permissionsStore, permissions);

  /// Resolve an app's requested permissions (prompting for unset ones via
  /// [permissionFlow]) and then [launch] it.
  Future<void> launchWithPermissions(
    String appId, {
    String arch = '',
    String branch = '',
    String commit = '',
  }) async {
    await permissionFlow.ensureLaunchPermissions(appId);
    await launch(appId, arch: arch, branch: branch, commit: commit);
  }

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
  TransactionBuilder transaction() => TransactionBuilder.internal(_tx);

  // ── Remote management ────────────────────────────────────────────────

  late final FlatpakRemoteManager remotes = FlatpakRemoteManager.create(
    _installation,
    isSystem: _isSystem,
  );

  /// Invalidate cached data so subsequent reads return fresh results.
  /// Call after mutations (add/remove/enable/disable remote) when using
  /// the same client for both writes and reads.
  void dropCaches() => _installation.dropCaches();

  /// The libflatpak version this build links against.
  Future<String> getVersion() => _installation.getVersion();

  /// The host's default Flatpak architecture.
  Future<String> getDefaultArch() => _installation.getDefaultArch();

  /// Architectures Flatpak can run on this host, primary arch first.
  Future<List<String>> getSupportedArches() =>
      _installation.getSupportedArches();

  /// Every configured Flatpak installation on this host.
  Future<List<FlatpakInstallationInfo>> listSystemInstallations() =>
      _installation.listSystemInstallations();

  Future<void> ensureRuntime(String appId) async {
    final runtimeRef = await _installation.getRuntimeRef(appId);
    final fullRef = 'runtime/$runtimeRef';
    if (await _installation.isRefInstalled(fullRef)) return;
    final app = await info(appId);
    await install(app.origin, fullRef).result;
  }

  /// Install every extension [appId] declares (skipping `no-autodownload`).
  Future<void> installExtensions(String appId) async {
    final missing = await _installation.listMissingExtensions(appId);
    if (missing.isEmpty) return;
    final app = await info(appId);
    for (final ref in missing) {
      await install(app.origin, ref).result;
    }
  }

  /// Disk usage of the filesystem backing this client's installation.
  Future<StorageInfo> getSystemStorage() async {
    final path = _installationPath();
    final result = await Process.run('df', [
      '-B1',
      '--output=size,avail',
      path,
    ]);
    if (result.exitCode != 0) {
      throw FlatpakRemoteException('df failed for $path: ${result.stderr}');
    }
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) {
      throw FlatpakRemoteException('unexpected df output for $path');
    }
    final parts = lines.last.trim().split(RegExp(r'\s+'));
    final total = int.parse(parts[0]);
    final available = int.parse(parts[1]);
    return StorageInfo(totalBytes: total, availableBytes: available);
  }

  String _installationPath() {
    switch (_installation.name) {
      case 'user':
        final xdg = Platform.environment['XDG_DATA_HOME'];
        final base = (xdg != null && xdg.isNotEmpty)
            ? xdg
            : '${Platform.environment['HOME'] ?? ''}/.local/share';
        return '$base/flatpak';
      case 'system':
        return '/var/lib/flatpak';
      default:
        return _installation.name;
    }
  }

  // ── Update monitor (FlatpakMonitor GObject API, libflatpak >= 1.5.3) ──

  /// Watch for update availability using FlatpakMonitor.
  /// Emits [UpdateAvailableEvent] when installed refs have changed.
  /// Works on the host; no sandbox required.
  UpdateMonitor watchUpdates() {
    final port = ReceivePort('flatpak.monitor');
    final controller = StreamController<UpdateAvailableEvent>.broadcast();

    final handle = FlatpakBindings.monitorCreate(
      port.sendPort.nativePort,
      _installation.name,
    );

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      if (msg[0] == 0x11) {
        controller.add(const UpdateAvailableEvent());
      }
    });

    return UpdateMonitor(
      events: controller.stream,
      close: () async {
        FlatpakBindings.monitorClose(handle);
        FlatpakBindings.monitorDestroy(handle);
        controller.close();
        port.close();
      },
    );
  }

  Future<void> close() async {
    _installation.close();
    _tx.close();
    await _permissionFlow?.close();
    await _permissionsStore?.close();
  }
}
