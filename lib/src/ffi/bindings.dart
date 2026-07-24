// Bindings to the flatpak_nc shared library.
//
// The library is declared as a native asset by hook/build.dart, which emits it
// under the asset id named in @DefaultAsset below. The VM resolves the symbols
// through that asset, so a consumer does not have to locate or build the
// library themselves.

@DefaultAsset('package:flatpak_dart/libflatpak_nc.so')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── Bridge initialization ───────────────────────────────────────────────────

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_bridge_init')
external void _bridgeInit(Pointer<Void> dartApiDlData);

// ── Reader ──────────────────────────────────────────────────────────────────

@Native<Pointer<Void> Function(Pointer<Utf8>)>(symbol: 'flatpak_reader_create')
external Pointer<Void> _readerCreate(Pointer<Utf8> installation);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_reader_destroy')
external void _readerDestroy(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>, Int64, Bool)>(
  symbol: 'flatpak_reader_list_apps',
)
external void _readerListApps(
  Pointer<Void> handle,
  int port,
  bool includeRuntimes,
);

@Native<Void Function(Pointer<Void>, Int64)>(
  symbol: 'flatpak_reader_list_remotes',
)
external void _readerListRemotes(Pointer<Void> handle, int port);

@Native<Void Function(Pointer<Void>, Int64, Pointer<Utf8>)>(
  symbol: 'flatpak_reader_get_remote_info',
)
external void _readerGetRemoteInfo(
  Pointer<Void> handle,
  int port,
  Pointer<Utf8> name,
);

@Native<
  Void Function(Pointer<Void>, Int64, Pointer<Utf8>, Pointer<Utf8>, Bool)
>(symbol: 'flatpak_reader_list_remote_apps')
external void _readerListRemoteApps(
  Pointer<Void> handle,
  int port,
  Pointer<Utf8> name,
  Pointer<Utf8> arch,
  bool includeRuntimes,
);

@Native<
  Void Function(
    Pointer<Void>,
    Int64,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>(symbol: 'flatpak_reader_get_app_info')
external void _readerGetAppInfo(
  Pointer<Void> handle,
  int port,
  Pointer<Utf8> appId,
  Pointer<Utf8> arch,
  Pointer<Utf8> branch,
);

@Native<Void Function(Pointer<Void>, Int64, Pointer<Utf8>)>(
  symbol: 'flatpak_reader_get_permissions',
)
external void _readerGetPermissions(
  Pointer<Void> handle,
  int port,
  Pointer<Utf8> appId,
);

@Native<Void Function(Pointer<Void>, Int64)>(
  symbol: 'flatpak_reader_check_updates',
)
external void _readerCheckUpdates(Pointer<Void> handle, int port);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_reader_drop_caches')
external void _readerDropCaches(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>, Int64, Pointer<Utf8>, Pointer<Utf8>)>(
  symbol: 'flatpak_reader_fetch_remote_metadata',
)
external void _readerFetchRemoteMetadata(
  Pointer<Void> handle,
  int port,
  Pointer<Utf8> remote,
  Pointer<Utf8> ref,
);

@Native<
  Void Function(
    Pointer<Void>,
    Int64,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>(symbol: 'flatpak_reader_launch')
external void _readerLaunch(
  Pointer<Void> handle,
  int port,
  Pointer<Utf8> appId,
  Pointer<Utf8> arch,
  Pointer<Utf8> branch,
  Pointer<Utf8> commit,
);

@Native<Void Function(Pointer<Void>, Int64, Pointer<Utf8>)>(
  symbol: 'flatpak_reader_stop',
)
external void _readerStop(Pointer<Void> handle, int port, Pointer<Utf8> appId);

@Native<Void Function(Pointer<Void>, Int64)>(
  symbol: 'flatpak_reader_list_running',
)
external void _readerListRunning(Pointer<Void> handle, int port);

// ── Worker ──────────────────────────────────────────────────────────────────

@Native<Pointer<Void> Function(Pointer<Utf8>)>(symbol: 'flatpak_worker_create')
external Pointer<Void> _workerCreate(Pointer<Utf8> installation);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_worker_destroy')
external void _workerDestroy(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_worker_cancel_current')
external void _workerCancelCurrent(Pointer<Void> handle);

// ── Transaction ─────────────────────────────────────────────────────────────

@Native<Pointer<Void> Function(Pointer<Void>, Int64)>(
  symbol: 'flatpak_tx_create',
)
external Pointer<Void> _txCreate(Pointer<Void> worker, int port);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_tx_destroy')
external void _txDestroy(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>(
  symbol: 'flatpak_tx_add_install',
)
external void _txAddInstall(
  Pointer<Void> handle,
  Pointer<Utf8> remote,
  Pointer<Utf8> ref,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: 'flatpak_tx_add_update',
)
external void _txAddUpdate(Pointer<Void> handle, Pointer<Utf8> ref);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: 'flatpak_tx_add_uninstall',
)
external void _txAddUninstall(Pointer<Void> handle, Pointer<Utf8> ref);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: 'flatpak_tx_add_install_bundle',
)
external void _txAddInstallBundle(Pointer<Void> handle, Pointer<Utf8> path);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_tx_submit')
external void _txSubmit(Pointer<Void> handle);

// ── User remote management ──────────────────────────────────────────────────

@Native<Pointer<Void> Function(Int64)>(symbol: 'flatpak_user_remote_create')
external Pointer<Void> _userRemoteCreate(int port);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_user_remote_destroy')
external void _userRemoteDestroy(Pointer<Void> handle);

@Native<
  Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Int64, Bool)
>(symbol: 'flatpak_user_remote_add')
external void _userRemoteAdd(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  Pointer<Uint8> config,
  int length,
  bool ifNotExists,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Bool)>(
  symbol: 'flatpak_user_remote_add_from_file',
)
external void _userRemoteAddFromFile(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  Pointer<Utf8> path,
  bool ifNotExists,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Int64)>(
  symbol: 'flatpak_user_remote_modify',
)
external void _userRemoteModify(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  Pointer<Uint8> changes,
  int length,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>, Bool)>(
  symbol: 'flatpak_user_remote_remove',
)
external void _userRemoteRemove(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  bool force,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: 'flatpak_user_remote_update',
)
external void _userRemoteUpdate(Pointer<Void> handle, Pointer<Utf8> name);

// ── System remote management ────────────────────────────────────────────────

@Native<Pointer<Void> Function(Int64)>(symbol: 'flatpak_system_remote_create')
external Pointer<Void> _systemRemoteCreate(int port);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_system_remote_destroy')
external void _systemRemoteDestroy(Pointer<Void> handle);

@Native<
  Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Int64, Bool)
>(symbol: 'flatpak_system_remote_add')
external void _systemRemoteAdd(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  Pointer<Uint8> config,
  int length,
  bool ifNotExists,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Bool)>(
  symbol: 'flatpak_system_remote_add_from_file',
)
external void _systemRemoteAddFromFile(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  Pointer<Utf8> path,
  bool ifNotExists,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Int64)>(
  symbol: 'flatpak_system_remote_modify',
)
external void _systemRemoteModify(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  Pointer<Uint8> changes,
  int length,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>, Bool)>(
  symbol: 'flatpak_system_remote_remove',
)
external void _systemRemoteRemove(
  Pointer<Void> handle,
  Pointer<Utf8> name,
  bool force,
);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: 'flatpak_system_remote_update',
)
external void _systemRemoteUpdate(Pointer<Void> handle, Pointer<Utf8> name);

// ── Monitor ─────────────────────────────────────────────────────────────────

@Native<Pointer<Void> Function(Int64, Pointer<Utf8>)>(
  symbol: 'flatpak_monitor_create',
)
external Pointer<Void> _monitorCreate(int port, Pointer<Utf8> installation);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_monitor_close')
external void _monitorClose(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>)>(symbol: 'flatpak_monitor_destroy')
external void _monitorDestroy(Pointer<Void> handle);

/// Bindings to the flatpak_nc shared library.
abstract final class FlatpakBindings {
  /// Wires up the Dart DL API so the C++ side can call Dart_PostCObject_DL
  /// from any thread. Runs once, on first access.
  ///
  /// Symbol resolution used to funnel through a lazily initialized
  /// DynamicLibrary whose initializer called this, which made the ordering
  /// implicit. @Native symbols resolve independently, so the ordering is
  /// enforced here instead: every handle originates from one of the create
  /// functions below, and each of those initializes first.
  static final bool _initialized = () {
    _bridgeInit(NativeApi.initializeApiDLData);
    return true;
  }();

  static void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('flatpak_bridge_init did not complete');
    }
  }

  // ── Reader ─────────────────────────────────────────────────────────────
  static Pointer<Void> readerCreate(String installation) {
    _ensureInitialized();
    final inst = installation.toNativeUtf8();
    try {
      return _readerCreate(inst);
    } finally {
      calloc.free(inst);
    }
  }

  static void readerDestroy(Pointer<Void> handle) => _readerDestroy(handle);

  static void readerListApps(
    Pointer<Void> handle,
    int port,
    bool includeRuntimes,
  ) => _readerListApps(handle, port, includeRuntimes);

  static void readerListRemotes(Pointer<Void> handle, int port) =>
      _readerListRemotes(handle, port);

  static void readerGetRemoteInfo(Pointer<Void> handle, int port, String name) {
    final n = name.toNativeUtf8();
    try {
      _readerGetRemoteInfo(handle, port, n);
    } finally {
      calloc.free(n);
    }
  }

  static void readerListRemoteApps(
    Pointer<Void> handle,
    int port,
    String name,
    String arch,
    bool includeRuntimes,
  ) {
    final n = name.toNativeUtf8();
    final a = arch.toNativeUtf8();
    try {
      _readerListRemoteApps(handle, port, n, a, includeRuntimes);
    } finally {
      calloc.free(n);
      calloc.free(a);
    }
  }

  static void readerGetAppInfo(
    Pointer<Void> handle,
    int port,
    String appId,
    String arch,
    String branch,
  ) {
    final id = appId.toNativeUtf8();
    final a = arch.toNativeUtf8();
    final b = branch.toNativeUtf8();
    try {
      _readerGetAppInfo(handle, port, id, a, b);
    } finally {
      calloc.free(id);
      calloc.free(a);
      calloc.free(b);
    }
  }

  static void readerGetPermissions(
    Pointer<Void> handle,
    int port,
    String appId,
  ) {
    final id = appId.toNativeUtf8();
    try {
      _readerGetPermissions(handle, port, id);
    } finally {
      calloc.free(id);
    }
  }

  static void readerCheckUpdates(Pointer<Void> handle, int port) =>
      _readerCheckUpdates(handle, port);

  static void readerDropCaches(Pointer<Void> handle) =>
      _readerDropCaches(handle);

  static void readerFetchRemoteMetadata(
    Pointer<Void> handle,
    int port,
    String remote,
    String ref,
  ) {
    final r = remote.toNativeUtf8();
    final f = ref.toNativeUtf8();
    try {
      _readerFetchRemoteMetadata(handle, port, r, f);
    } finally {
      calloc.free(r);
      calloc.free(f);
    }
  }

  static void readerLaunch(
    Pointer<Void> handle,
    int port,
    String appId,
    String arch,
    String branch,
    String commit,
  ) {
    final id = appId.toNativeUtf8();
    final a = arch.toNativeUtf8();
    final b = branch.toNativeUtf8();
    final c = commit.toNativeUtf8();
    try {
      _readerLaunch(handle, port, id, a, b, c);
    } finally {
      calloc.free(id);
      calloc.free(a);
      calloc.free(b);
      calloc.free(c);
    }
  }

  static void readerStop(Pointer<Void> handle, int port, String appId) {
    final id = appId.toNativeUtf8();
    try {
      _readerStop(handle, port, id);
    } finally {
      calloc.free(id);
    }
  }

  static void readerListRunning(Pointer<Void> handle, int port) =>
      _readerListRunning(handle, port);

  // ── Worker ─────────────────────────────────────────────────────────────
  static Pointer<Void> workerCreate(String installation) {
    _ensureInitialized();
    final inst = installation.toNativeUtf8();
    try {
      return _workerCreate(inst);
    } finally {
      calloc.free(inst);
    }
  }

  static void workerDestroy(Pointer<Void> handle) => _workerDestroy(handle);
  static void workerCancelCurrent(Pointer<Void> handle) =>
      _workerCancelCurrent(handle);

  // ── Transaction ────────────────────────────────────────────────────────
  static Pointer<Void> txCreate(Pointer<Void> worker, int port) =>
      _txCreate(worker, port);
  static void txDestroy(Pointer<Void> handle) => _txDestroy(handle);

  static void txAddInstall(Pointer<Void> handle, String remote, String ref) {
    final r = remote.toNativeUtf8();
    final f = ref.toNativeUtf8();
    try {
      _txAddInstall(handle, r, f);
    } finally {
      calloc.free(r);
      calloc.free(f);
    }
  }

  static void txAddUpdate(Pointer<Void> handle, String ref) {
    final f = ref.toNativeUtf8();
    try {
      _txAddUpdate(handle, f);
    } finally {
      calloc.free(f);
    }
  }

  static void txAddUninstall(Pointer<Void> handle, String ref) {
    final f = ref.toNativeUtf8();
    try {
      _txAddUninstall(handle, f);
    } finally {
      calloc.free(f);
    }
  }

  static void txAddInstallBundle(Pointer<Void> handle, String path) {
    final p = path.toNativeUtf8();
    try {
      _txAddInstallBundle(handle, p);
    } finally {
      calloc.free(p);
    }
  }

  static void txSubmit(Pointer<Void> handle) => _txSubmit(handle);

  // ── User remote management ─────────────────────────────────────────────
  static Pointer<Void> userRemoteCreate(int port) {
    _ensureInitialized();
    return _userRemoteCreate(port);
  }

  static void userRemoteDestroy(Pointer<Void> handle) =>
      _userRemoteDestroy(handle);

  static void userRemoteAdd(
    Pointer<Void> handle,
    String name,
    Uint8List config,
    bool ifNotExists,
  ) {
    final n = name.toNativeUtf8();
    final buf = calloc<Uint8>(config.length);
    buf.asTypedList(config.length).setAll(0, config);
    try {
      _userRemoteAdd(handle, n, buf, config.length, ifNotExists);
    } finally {
      calloc.free(n);
      calloc.free(buf);
    }
  }

  static void userRemoteAddFromFile(
    Pointer<Void> handle,
    String name,
    String path,
    bool ifNotExists,
  ) {
    final n = name.toNativeUtf8();
    final p = path.toNativeUtf8();
    try {
      _userRemoteAddFromFile(handle, n, p, ifNotExists);
    } finally {
      calloc.free(n);
      calloc.free(p);
    }
  }

  static void userRemoteModify(
    Pointer<Void> handle,
    String name,
    Uint8List changes,
  ) {
    final n = name.toNativeUtf8();
    final buf = calloc<Uint8>(changes.length);
    buf.asTypedList(changes.length).setAll(0, changes);
    try {
      _userRemoteModify(handle, n, buf, changes.length);
    } finally {
      calloc.free(n);
      calloc.free(buf);
    }
  }

  static void userRemoteRemove(Pointer<Void> handle, String name, bool force) {
    final n = name.toNativeUtf8();
    try {
      _userRemoteRemove(handle, n, force);
    } finally {
      calloc.free(n);
    }
  }

  static void userRemoteUpdate(Pointer<Void> handle, String name) {
    final n = name.toNativeUtf8();
    try {
      _userRemoteUpdate(handle, n);
    } finally {
      calloc.free(n);
    }
  }

  // ── System remote management ───────────────────────────────────────────
  static Pointer<Void> systemRemoteCreate(int port) {
    _ensureInitialized();
    return _systemRemoteCreate(port);
  }

  static void systemRemoteDestroy(Pointer<Void> handle) =>
      _systemRemoteDestroy(handle);

  static void systemRemoteAdd(
    Pointer<Void> handle,
    String name,
    Uint8List config,
    bool ifNotExists,
  ) {
    final n = name.toNativeUtf8();
    final buf = calloc<Uint8>(config.length);
    buf.asTypedList(config.length).setAll(0, config);
    try {
      _systemRemoteAdd(handle, n, buf, config.length, ifNotExists);
    } finally {
      calloc.free(n);
      calloc.free(buf);
    }
  }

  static void systemRemoteAddFromFile(
    Pointer<Void> handle,
    String name,
    String path,
    bool ifNotExists,
  ) {
    final n = name.toNativeUtf8();
    final p = path.toNativeUtf8();
    try {
      _systemRemoteAddFromFile(handle, n, p, ifNotExists);
    } finally {
      calloc.free(n);
      calloc.free(p);
    }
  }

  static void systemRemoteModify(
    Pointer<Void> handle,
    String name,
    Uint8List changes,
  ) {
    final n = name.toNativeUtf8();
    final buf = calloc<Uint8>(changes.length);
    buf.asTypedList(changes.length).setAll(0, changes);
    try {
      _systemRemoteModify(handle, n, buf, changes.length);
    } finally {
      calloc.free(n);
      calloc.free(buf);
    }
  }

  static void systemRemoteRemove(
    Pointer<Void> handle,
    String name,
    bool force,
  ) {
    final n = name.toNativeUtf8();
    try {
      _systemRemoteRemove(handle, n, force);
    } finally {
      calloc.free(n);
    }
  }

  static void systemRemoteUpdate(Pointer<Void> handle, String name) {
    final n = name.toNativeUtf8();
    try {
      _systemRemoteUpdate(handle, n);
    } finally {
      calloc.free(n);
    }
  }

  // ── Monitor ────────────────────────────────────────────────────────────
  static Pointer<Void> monitorCreate(int port, String installation) {
    _ensureInitialized();
    final inst = installation.toNativeUtf8();
    try {
      return _monitorCreate(port, inst);
    } finally {
      calloc.free(inst);
    }
  }

  static void monitorClose(Pointer<Void> handle) => _monitorClose(handle);
  static void monitorDestroy(Pointer<Void> handle) => _monitorDestroy(handle);
}
