// FlatpakInstallation — wraps the C++ InstallationReader handle.
// Reader is created once; each operation gets its own ReceivePort.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'application.dart';
import 'exceptions.dart';
import 'ffi/bindings.dart';
import 'ffi/codec.dart';
import 'installation_info.dart';
import 'instance.dart';
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
    bool waylandOnly = false,
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
      waylandOnly: waylandOnly,
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
        case 0x01:
          results.add(GlazeCodec.decodeMetadataEntry(msg, 1));
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

  /// Launch an installed application in its sandbox.
  /// Completes when the sandbox has been spawned (non-blocking on the app).
  /// Returns the [FlatpakInstance] libflatpak created for the launch, so
  /// callers get the instanceId and pid immediately instead of polling
  /// [listRunning].
  ///
  /// [FlatpakInstance.childPid] is resolved on a best-effort basis: libflatpak
  /// reports it as `0` on a freshly launched instance, so the native side waits
  /// briefly for bwrap to write it. It is `0` if the app exits before that or
  /// the wait times out; everything else on the instance is always populated.
  Future<FlatpakInstance> launch(
    String appId, {
    String arch = '',
    String branch = '',
    String commit = '',
  }) async {
    // libflatpak launches by exec'ing bwrap, which only exists on the host.
    // Inside a sandbox that fails with "failed to execute child process
    // bwrap", so delegate to the host through the Flatpak portal instead.
    // Needs --talk-name=org.freedesktop.Flatpak in the caller's finish-args.
    if (_isSandboxed) {
      return _launchOnHost(appId, arch: arch, branch: branch, commit: commit);
    }

    final port = ReceivePort('flatpak.launch');
    final completer = Completer<FlatpakInstance>();
    FlatpakInstance? result;

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            result = GlazeCodec.decodeInstance(msg, 1);
          }
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakNotFoundException(err));
          }
          port.close();
        case 0x03:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakLaunchException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) {
            final instance = result;
            if (instance != null) {
              completer.complete(instance);
            } else {
              completer.completeError(
                const FlatpakLaunchException('launch produced no instance'),
              );
            }
          }
          port.close();
      }
    });

    FlatpakBindings.readerLaunch(
      _handle,
      port.sendPort.nativePort,
      appId,
      arch,
      branch,
      commit,
    );
    return completer.future;
  }

  /// True when this process is itself running inside a Flatpak sandbox.
  static bool get _isSandboxed => File('/.flatpak-info').existsSync();

  /// How long a host-delegated `flatpak run` gets to fail before the launch is
  /// reported as successful. `flatpak run` stays in the foreground for the
  /// app's lifetime, so there is no success exit code to wait for.
  static const _hostLaunchSettle = Duration(milliseconds: 1500);

  static const _hostPsColumns = hostPsColumns;

  /// Run [command] on the host through the Flatpak portal.
  /// Requires `--talk-name=org.freedesktop.Flatpak` in the caller's finish-args.
  Future<ProcessResult> _runOnHost(List<String> command) async {
    try {
      return await Process.run('flatpak-spawn', ['--host', ...command]);
    } on ProcessException catch (e) {
      throw FlatpakLaunchException(
        'flatpak-spawn --host ${command.first} failed: ${e.message}',
      );
    }
  }

  /// Launch [appId] on the host via `flatpak-spawn --host flatpak run`.
  ///
  /// Returns the instance flatpak registered for the launch. When it has not
  /// appeared in `flatpak ps` yet the returned instance carries only what is
  /// known at spawn time and [FlatpakInstance.instanceId] is empty.
  Future<FlatpakInstance> _launchOnHost(
    String appId, {
    String arch = '',
    String branch = '',
    String commit = '',
  }) async {
    final args = <String>['--host', 'flatpak', 'run'];
    if (arch.isNotEmpty) args.add('--arch=$arch');
    if (branch.isNotEmpty) args.add('--branch=$branch');
    if (commit.isNotEmpty) args.add('--commit=$commit');
    args.add(appId);

    final Process proc;
    try {
      proc = await Process.start('flatpak-spawn', args);
    } on ProcessException catch (e) {
      throw FlatpakLaunchException(
        'flatpak-spawn --host failed for "$appId": ${e.message}',
      );
    }

    final stderrBuf = StringBuffer();
    final stderrDone = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stderrBuf.write);
    unawaited(proc.stdout.drain<void>());

    const stillRunning = -1;
    final exitCode = await proc.exitCode.timeout(
      _hostLaunchSettle,
      onTimeout: () => stillRunning,
    );
    if (exitCode > 0) {
      await stderrDone;
      final detail = stderrBuf.toString().trim();
      throw FlatpakLaunchException(
        'flatpak run "$appId" on the host exited $exitCode'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }

    for (final instance in await _listRunningOnHost()) {
      if (instance.appId == appId) return instance;
    }
    return FlatpakInstance(
      appId: appId,
      instanceId: '',
      arch: arch,
      branch: branch,
      commit: commit,
      pid: proc.pid,
      isRunning: exitCode == stillRunning,
    );
  }

  /// `flatpak ps` on the host, parsed into instances.
  Future<List<FlatpakInstance>> _listRunningOnHost() async {
    final result = await _runOnHost([
      'flatpak',
      'ps',
      '--columns=$_hostPsColumns',
    ]);
    if (result.exitCode != 0) {
      throw FlatpakLaunchException(
        'flatpak ps on the host exited ${result.exitCode}: '
        '${(result.stderr as String).trim()}',
      );
    }

    return parseHostPsOutput(result.stdout as String);
  }

  /// `flatpak kill` on the host.
  Future<void> _stopOnHost(String appId) async {
    final result = await _runOnHost(['flatpak', 'kill', appId]);
    if (result.exitCode == 0) return;
    final detail = (result.stderr as String).trim();
    if (detail.contains('not running') || detail.contains('No such instance')) {
      throw FlatpakNotFoundException('no running instance for "$appId"');
    }
    throw FlatpakStopException(
      'flatpak kill "$appId" on the host exited ${result.exitCode}'
      '${detail.isEmpty ? '' : ': $detail'}',
    );
  }

  /// Terminate every running instance of [appId] across the host — flatpak
  /// instances are not scoped to an installation, so instances launched from
  /// the other installation are matched too.
  /// Returns as soon as SIGTERM has been sent to every matched instance;
  /// SIGKILL escalation continues in the background.
  ///
  /// Throws [FlatpakNotFoundException] if no running instance was found, and
  /// [FlatpakStopException] if instances were found but none could be
  /// signalled — the app is still running in that case.
  Future<void> stop(String appId) async {
    // flatpak_instance_get_all() reads $XDG_RUNTIME_DIR/.flatpak, which inside
    // a sandbox holds only this process's own instance.
    if (_isSandboxed) return _stopOnHost(appId);

    final port = ReceivePort('flatpak.stop');
    final completer = Completer<void>();

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakNotFoundException(err));
          }
          port.close();
        case 0x03:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakStopException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) completer.complete();
          port.close();
      }
    });

    FlatpakBindings.readerStop(_handle, port.sendPort.nativePort, appId);
    return completer.future;
  }

  /// List running sandbox instances across the host.
  ///
  /// The native side only ever posts 0x01 payloads and the 0xFF sentinel here;
  /// the 0x02 branch below is a defensive guard so an unexpected error frame
  /// completes the future instead of leaving the caller hanging.
  Future<List<FlatpakInstance>> listRunning() async {
    if (_isSandboxed) return _listRunningOnHost();

    final port = ReceivePort('flatpak.listRunning');
    final completer = Completer<List<FlatpakInstance>>();
    final results = <FlatpakInstance>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeInstance(msg, 1));
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

    FlatpakBindings.readerListRunning(_handle, port.sendPort.nativePort);
    return completer.future;
  }

  /// Refresh the on-disk AppStream catalog for [remote] (empty [arch] = default).
  /// Wraps `flatpak_installation_update_appstream_sync`.
  Future<void> refreshAppstream(String remote, {String arch = ''}) async {
    final port = ReceivePort('flatpak.refreshAppstream');
    final completer = Completer<void>();

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakRemoteException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) completer.complete();
          port.close();
      }
    });

    FlatpakBindings.readerRefreshAppstream(
      _handle,
      port.sendPort.nativePort,
      remote,
      arch,
    );
    return completer.future;
  }

  Future<String> getVersion() => _readSingleString(
    FlatpakBindings.readerGetVersion,
    portName: 'flatpak.getVersion',
  );

  /// The host's default Flatpak architecture.
  Future<String> getDefaultArch() => _readSingleString(
    FlatpakBindings.readerGetDefaultArch,
    portName: 'flatpak.getDefaultArch',
  );

  /// Architectures Flatpak can run on this host, primary arch first.
  Future<List<String>> getSupportedArches() async {
    final port = ReceivePort('flatpak.getSupportedArches');
    final completer = Completer<List<String>>();
    final results = <String>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          results.add(GlazeCodec.decodeError(msg, 1));
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

    FlatpakBindings.readerGetSupportedArches(_handle, port.sendPort.nativePort);
    return completer.future;
  }

  /// Every configured Flatpak installation on this host (user + system installations).
  Future<List<FlatpakInstallationInfo>> listSystemInstallations() async {
    final port = ReceivePort('flatpak.listSystemInstallations');
    final completer = Completer<List<FlatpakInstallationInfo>>();
    final results = <FlatpakInstallationInfo>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          if (msg.length > 1) {
            results.add(GlazeCodec.decodeInstallationInfo(msg, 1));
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

    FlatpakBindings.readerListSystemInstallations(
      _handle,
      port.sendPort.nativePort,
    );
    return completer.future;
  }

  Future<String> getRuntimeRef(
    String appId, {
    String arch = '',
    String branch = '',
  }) => _readSingleString(
    (handle, port) =>
        FlatpakBindings.readerGetRuntimeRef(handle, port, appId, arch, branch),
    portName: 'flatpak.getRuntimeRef',
  );

  /// Whether [ref] (e.g. `runtime/org.foo.Platform/x86_64/1.0`) is installed.
  Future<bool> isRefInstalled(String ref) async {
    final result = await _readSingleString(
      (handle, port) => FlatpakBindings.readerIsRefInstalled(handle, port, ref),
      portName: 'flatpak.isRefInstalled',
    );
    return result == '1';
  }

  /// Extension refs declared in [appId]'s metadata that are required
  /// (no `no-autodownload=true`) but not currently installed.
  Future<List<String>> listMissingExtensions(
    String appId, {
    String arch = '',
    String branch = '',
  }) async {
    final port = ReceivePort('flatpak.listMissingExtensions');
    final completer = Completer<List<String>>();
    final results = <String>[];

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          results.add(GlazeCodec.decodeError(msg, 1));
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

    FlatpakBindings.readerListMissingExtensions(
      _handle,
      port.sendPort.nativePort,
      appId,
      arch,
      branch,
    );
    return completer.future;
  }

  Future<String> _readSingleString(
    void Function(Pointer<Void>, int) call, {
    required String portName,
  }) async {
    final port = ReceivePort(portName);
    final completer = Completer<String>();
    var result = '';

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x01:
          result = GlazeCodec.decodeError(msg, 1);
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          if (!completer.isCompleted) {
            completer.completeError(FlatpakRemoteException(err));
          }
          port.close();
        case 0xFF:
          if (!completer.isCompleted) completer.complete(result);
          port.close();
      }
    });

    call(_handle, port.sendPort.nativePort);
    return completer.future;
  }

  void close() {
    FlatpakBindings.readerDestroy(_handle);
  }
}

/// Column order requested from `flatpak ps` by the sandboxed [listRunning]
/// path. [parseHostPsOutput] is positional, so the two must stay in step.
const hostPsColumns = 'application,instance,arch,branch,commit,pid,child-pid';

/// Parses `flatpak ps --columns=[hostPsColumns]` output.
///
/// Columns are whitespace separated and none of the requested fields can
/// contain whitespace. Rows that do not match the expected shape — a header
/// row, or output from a flatpak whose column set differs — are skipped rather
/// than mis-bound to the wrong fields.
List<FlatpakInstance> parseHostPsOutput(String stdout) {
  const columnCount = 7;
  final instances = <FlatpakInstance>[];

  for (final line in const LineSplitter().convert(stdout)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final cols = trimmed.split(RegExp(r'\s+'));
    if (cols.length != columnCount) continue;
    final pid = int.tryParse(cols[5]);
    final childPid = int.tryParse(cols[6]);
    if (pid == null || childPid == null) continue;
    instances.add(
      FlatpakInstance(
        appId: cols[0],
        instanceId: cols[1],
        arch: cols[2],
        branch: cols[3],
        commit: cols[4],
        pid: pid,
        childPid: childPid,
        isRunning: true,
      ),
    );
  }
  return instances;
}
