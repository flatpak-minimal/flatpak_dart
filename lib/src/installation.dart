// FlatpakInstallation — wraps the C++ InstallationReader handle.
// All read operations are synchronous FFI calls that post results
// to a ReceivePort.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'application.dart';
import 'exceptions.dart';
import 'ffi/bindings.dart';
import 'ffi/codec.dart';
import 'permissions.dart';
import 'remote.dart';

class FlatpakInstallation {
  final String name;
  late final Pointer<Void> _readerHandle;

  Pointer<Void> get readerHandle => _readerHandle;

  FlatpakInstallation(this.name);

  void initReader(int port) {
    _readerHandle = FlatpakBindings.readerCreate(port, name);
  }

  /// List installed applications (and optionally runtimes).
  Future<List<FlatpakApplication>> listApplications({
    bool includeRuntimes = false,
  }) async {
    final port = ReceivePort('flatpak.listApps');
    final completer = Completer<List<FlatpakApplication>>();
    final results = <FlatpakApplication>[];

    initReader(port.sendPort.nativePort);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeInstalledApp(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          completer.completeError(FlatpakNotFoundException(err));
          port.close();
        case 0xFF:
          completer.complete(results);
          port.close();
      }
    });

    FlatpakBindings.readerListApps(_readerHandle, includeRuntimes);
    return completer.future;
  }

  /// List configured remotes.
  Future<List<FlatpakRemote>> listRemotes() async {
    final port = ReceivePort('flatpak.listRemotes');
    final completer = Completer<List<FlatpakRemote>>();
    final results = <FlatpakRemote>[];

    initReader(port.sendPort.nativePort);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeFlatpakRemote(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          completer.completeError(FlatpakException(err) as Object);
          port.close();
        case 0xFF:
          completer.complete(results);
          port.close();
      }
    });

    FlatpakBindings.readerListRemotes(_readerHandle);
    return completer.future;
  }

  /// Get detailed info for one remote.
  Future<FlatpakRemote> getRemoteInfo(String name) async {
    final port = ReceivePort('flatpak.remoteInfo');
    final completer = Completer<FlatpakRemote>();

    initReader(port.sendPort.nativePort);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            completer.complete(GlazeCodec.decodeFlatpakRemote(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          completer.completeError(FlatpakNotFoundException(err));
          port.close();
        case 0xFF:
          port.close();
      }
    });

    FlatpakBindings.readerGetRemoteInfo(_readerHandle, name);
    return completer.future;
  }

  /// Stream refs available in a remote.
  Stream<FlatpakRef> listRemoteApps(String remoteName, {
    String arch = '',
    bool includeRuntimes = false,
  }) {
    final controller = StreamController<FlatpakRef>();
    final port = ReceivePort('flatpak.listRemoteApps');

    initReader(port.sendPort.nativePort);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            controller.add(GlazeCodec.decodeFlatpakRef(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          controller.addError(FlatpakNotFoundException(err));
          controller.close();
          port.close();
        case 0xFF:
          controller.close();
          port.close();
      }
    });

    FlatpakBindings.readerListRemoteApps(
        _readerHandle, remoteName, arch, includeRuntimes);
    return controller.stream;
  }

  /// Get detailed info for one installed application.
  Future<FlatpakApplication> getAppInfo(String appId, {
    String arch = '',
    String branch = '',
  }) async {
    final port = ReceivePort('flatpak.appInfo');
    final completer = Completer<FlatpakApplication>();

    initReader(port.sendPort.nativePort);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            completer.complete(GlazeCodec.decodeInstalledApp(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          completer.completeError(FlatpakNotFoundException(err));
          port.close();
        case 0xFF:
          port.close();
      }
    });

    FlatpakBindings.readerGetAppInfo(_readerHandle, appId, arch, branch);
    return completer.future;
  }

  /// Get permission overrides for an application.
  Future<List<FlatpakPermission>> getPermissions(String appId) async {
    final port = ReceivePort('flatpak.permissions');
    final completer = Completer<List<FlatpakPermission>>();
    final results = <FlatpakPermission>[];

    initReader(port.sendPort.nativePort);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0xFF:
          completer.complete(results);
          port.close();
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          completer.completeError(FlatpakNotFoundException(err));
          port.close();
      }
    });

    FlatpakBindings.readerGetPermissions(_readerHandle, appId);
    return completer.future;
  }

  /// Check which installed applications have updates available.
  Future<List<FlatpakRef>> checkForUpdates() async {
    final port = ReceivePort('flatpak.checkUpdates');
    final completer = Completer<List<FlatpakRef>>();
    final results = <FlatpakRef>[];

    initReader(port.sendPort.nativePort);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeFlatpakRef(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          completer.completeError(FlatpakException(err) as Object);
          port.close();
        case 0xFF:
          completer.complete(results);
          port.close();
      }
    });

    FlatpakBindings.readerCheckUpdates(_readerHandle);
    return completer.future;
  }

  void close() {
    FlatpakBindings.readerDestroy(_readerHandle);
  }
}
