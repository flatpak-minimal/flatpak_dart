// remote_manager.dart
// Mirrors the `flatpak remote-*` CLI surface.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'application.dart';
import 'exceptions.dart';
import 'ffi/bindings.dart';
import 'ffi/codec.dart';
import 'installation.dart';
import 'remote.dart';

class FlatpakRemoteManager {
  final FlatpakInstallation _installation;
  final bool _isSystem;

  FlatpakRemoteManager._(this._installation, this._isSystem);

  factory FlatpakRemoteManager.create(
    FlatpakInstallation installation, {
    required bool isSystem,
  }) => FlatpakRemoteManager._(installation, isSystem);

  // ── Read operations ───────────────────────────────────────────────────

  /// List all configured remotes.
  Future<List<FlatpakRemote>> list() => _installation.listRemotes();

  /// Get detailed info for one remote by name.
  Future<FlatpakRemote> info(String name) => _installation.getRemoteInfo(name);

  /// Stream all refs available in a remote.
  Stream<FlatpakRef> listApps(
    String name, {
    String arch = '',
    bool includeRuntimes = false,
  }) => _installation.listRemoteApps(
    name,
    arch: arch,
    includeRuntimes: includeRuntimes,
  );

  // ── Write operations ───────────────────────────────────────────────────

  /// Add a remote by name with explicit configuration.
  Future<void> add(
    String name,
    FlatpakRemoteConfig config, {
    bool ifNotExists = true,
  }) async {
    if (config.flatpakrepoPath != null) {
      return addFromFile(
        name,
        config.flatpakrepoPath!,
        ifNotExists: ifNotExists,
      );
    }
    final buf = GlazeCodec.encodeRemoteConfig(config);
    final port = ReceivePort('flatpak.remoteAdd');
    final completer = Completer<void>();

    _listenForResult(port, completer);

    if (_isSystem) {
      final handle = FlatpakBindings.systemRemoteCreate(
        port.sendPort.nativePort,
      );
      FlatpakBindings.systemRemoteAdd(handle, name, buf, ifNotExists);
    } else {
      final handle = FlatpakBindings.userRemoteCreate(port.sendPort.nativePort);
      FlatpakBindings.userRemoteAdd(handle, name, buf, ifNotExists);
    }

    return completer.future;
  }

  /// Add a remote by parsing a local `.flatpakrepo` keyfile.
  Future<void> addFromFile(
    String name,
    String flatpakrepoPath, {
    bool ifNotExists = true,
  }) async {
    final port = ReceivePort('flatpak.remoteAddFile');
    final completer = Completer<void>();

    _listenForResult(port, completer);

    if (_isSystem) {
      final handle = FlatpakBindings.systemRemoteCreate(
        port.sendPort.nativePort,
      );
      FlatpakBindings.systemRemoteAddFromFile(
        handle,
        name,
        flatpakrepoPath,
        ifNotExists,
      );
    } else {
      final handle = FlatpakBindings.userRemoteCreate(port.sendPort.nativePort);
      FlatpakBindings.userRemoteAddFromFile(
        handle,
        name,
        flatpakrepoPath,
        ifNotExists,
      );
    }

    return completer.future;
  }

  /// Modify properties of an existing remote.
  Future<void> modify(String name, FlatpakRemoteConfig changes) async {
    final buf = GlazeCodec.encodeRemoteConfig(changes);
    final port = ReceivePort('flatpak.remoteModify');
    final completer = Completer<void>();

    _listenForResult(port, completer);

    if (_isSystem) {
      final handle = FlatpakBindings.systemRemoteCreate(
        port.sendPort.nativePort,
      );
      FlatpakBindings.systemRemoteModify(handle, name, buf);
    } else {
      final handle = FlatpakBindings.userRemoteCreate(port.sendPort.nativePort);
      FlatpakBindings.userRemoteModify(handle, name, buf);
    }

    return completer.future;
  }

  /// Change the subset filter on an existing Flathub remote.
  Future<void> modifySubset(String name, RemoteSubset subset) async {
    // Both setting and clearing a subset use modify — the C++ bridge
    // writes the subset key to the remote's ostree config.
    // Passing RemoteSubset.none sends an empty string which clears it.
    await modify(name, FlatpakRemoteConfig(subset: subset));
  }

  /// Enable a disabled remote.
  Future<void> enable(String name) =>
      modify(name, const FlatpakRemoteConfig(disabled: false));

  /// Disable a remote without removing it.
  Future<void> disable(String name) =>
      modify(name, const FlatpakRemoteConfig(disabled: true));

  /// Change the search priority of a remote.
  Future<void> setPriority(String name, int priority) =>
      modify(name, FlatpakRemoteConfig(priority: priority));

  /// Remove a remote.
  Future<void> remove(String name, {bool force = false}) async {
    final port = ReceivePort('flatpak.remoteRemove');
    final completer = Completer<void>();

    _listenForResult(port, completer);

    if (_isSystem) {
      final handle = FlatpakBindings.systemRemoteCreate(
        port.sendPort.nativePort,
      );
      FlatpakBindings.systemRemoteRemove(handle, name, force);
    } else {
      final handle = FlatpakBindings.userRemoteCreate(port.sendPort.nativePort);
      FlatpakBindings.userRemoteRemove(handle, name, force);
    }

    return completer.future;
  }

  /// Refresh the remote summary / appstream data.
  Future<void> update(String name) async {
    final port = ReceivePort('flatpak.remoteUpdate');
    final completer = Completer<void>();

    _listenForResult(port, completer);

    if (_isSystem) {
      final handle = FlatpakBindings.systemRemoteCreate(
        port.sendPort.nativePort,
      );
      FlatpakBindings.systemRemoteUpdate(handle, name);
    } else {
      final handle = FlatpakBindings.userRemoteCreate(port.sendPort.nativePort);
      FlatpakBindings.userRemoteUpdate(handle, name);
    }

    return completer.future;
  }

  void _listenForResult(ReceivePort port, Completer<void> completer) {
    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (!completer.isCompleted) completer.complete();
          port.close();
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakRemoteException(err));
          }
          port.close();
      }
    });
  }
}
