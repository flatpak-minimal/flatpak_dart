// FlatpakInstallation — wraps the C++ InstallationReader handle.
// Reader is created once; each operation gets its own ReceivePort.

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
  late final Pointer<Void> _handle = FlatpakBindings.readerCreate(name);

  FlatpakInstallation(this.name);

  /// Invalidate libflatpak's cached data so subsequent reads return fresh results.
  void dropCaches() => FlatpakBindings.readerDropCaches(_handle);

  Future<List<FlatpakApplication>> listApplications({
    bool includeRuntimes = false,
  }) async {
    final port = ReceivePort('flatpak.listApps');
    final completer = Completer<List<FlatpakApplication>>();
    final results = <FlatpakApplication>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeInstalledApp(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakNotFoundException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) completer.complete(results);
          port.close();
      }
    });

    FlatpakBindings.readerListApps(
      _handle,
      port.sendPort.nativePort,
      includeRuntimes,
    );
    return completer.future;
  }

  Future<List<FlatpakRemote>> listRemotes() async {
    final port = ReceivePort('flatpak.listRemotes');
    final completer = Completer<List<FlatpakRemote>>();
    final results = <FlatpakRemote>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeFlatpakRemote(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakRemoteException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) completer.complete(results);
          port.close();
      }
    });

    FlatpakBindings.readerListRemotes(_handle, port.sendPort.nativePort);
    return completer.future;
  }

  Future<FlatpakRemote> getRemoteInfo(String remoteName) async {
    final port = ReceivePort('flatpak.remoteInfo');
    final completer = Completer<FlatpakRemote>();

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1 && !completer.isCompleted) {
            completer.complete(GlazeCodec.decodeFlatpakRemote(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakNotFoundException(err));
          }
          port.close();
        case 0xFF:
          port.close();
      }
    });

    FlatpakBindings.readerGetRemoteInfo(
      _handle,
      port.sendPort.nativePort,
      remoteName,
    );
    return completer.future;
  }

  Stream<FlatpakRef> listRemoteApps(
    String remoteName, {
    String arch = '',
    bool includeRuntimes = false,
  }) {
    final controller = StreamController<FlatpakRef>();
    final port = ReceivePort('flatpak.listRemoteApps');

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
      _handle,
      port.sendPort.nativePort,
      remoteName,
      arch,
      includeRuntimes,
    );
    return controller.stream;
  }

  Future<FlatpakApplication> getAppInfo(
    String appId, {
    String arch = '',
    String branch = '',
  }) async {
    final port = ReceivePort('flatpak.appInfo');
    final completer = Completer<FlatpakApplication>();

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1 && !completer.isCompleted) {
            completer.complete(GlazeCodec.decodeInstalledApp(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakNotFoundException(err));
          }
          port.close();
        case 0xFF:
          port.close();
      }
    });

    FlatpakBindings.readerGetAppInfo(
      _handle,
      port.sendPort.nativePort,
      appId,
      arch,
      branch,
    );
    return completer.future;
  }

  Future<List<FlatpakPermission>> getPermissions(String appId) async {
    final port = ReceivePort('flatpak.permissions');
    final completer = Completer<List<FlatpakPermission>>();
    final results = <FlatpakPermission>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakNotFoundException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) completer.complete(results);
          port.close();
      }
    });

    FlatpakBindings.readerGetPermissions(
      _handle,
      port.sendPort.nativePort,
      appId,
    );
    return completer.future;
  }

  Future<List<FlatpakRef>> checkForUpdates() async {
    final port = ReceivePort('flatpak.checkUpdates');
    final completer = Completer<List<FlatpakRef>>();
    final results = <FlatpakRef>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeFlatpakRef(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakRemoteException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) completer.complete(results);
          port.close();
      }
    });

    FlatpakBindings.readerCheckUpdates(_handle, port.sendPort.nativePort);
    return completer.future;
  }

  /// Fetch metadata (permissions) for a remote ref without installing it.
  Future<List<MetadataEntry>> fetchRemoteMetadata(
    String remote,
    String ref,
  ) async {
    final port = ReceivePort('flatpak.fetchMetadata');
    final completer = Completer<List<MetadataEntry>>();

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1 && !completer.isCompleted) {
            completer.complete(GlazeCodec.decodeRemoteMetadata(msg, 1));
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakNotFoundException(err));
          }
          port.close();
        case 0xFF:
          port.close();
      }
    });

    FlatpakBindings.readerFetchRemoteMetadata(
      _handle,
      port.sendPort.nativePort,
      remote,
      ref,
    );
    return completer.future;
  }

  void close() {
    FlatpakBindings.readerDestroy(_handle);
  }
}
