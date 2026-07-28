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
import 'dart:isolate';
import 'dart:typed_data';

import 'application.dart';
import 'appstream/catalog.dart';
import 'ffi/bindings.dart';
import 'ffi/codec.dart' show MetadataEntry;
import 'installation.dart';
import 'instance.dart';
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
  Future<FlatpakInstance> launch(
    String appId, {
    String arch = '',
    String branch = '',
    String commit = '',
  }) => _installation.launch(appId, arch: arch, branch: branch, commit: commit);

  /// Stop every running instance of [appId]. Returns once SIGTERM has been
  /// sent; grace period + SIGKILL escalation continue in the background.
  Future<void> stop(String appId) => _installation.stop(appId);

  /// List running sandbox instances across the host.
  Future<List<FlatpakInstance>> listRunning() => _installation.listRunning();

  // ── AppStream catalog + icons ─────────────────────────────────────────

  /// AppStream metadata (icons, screenshots, releases) and installed-app
  /// icon resolution, backed by the appstream_dart engine.
  late final FlatpakAppStream appStream = FlatpakAppStream.forName(
    _installation,
  );

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
  }
}
