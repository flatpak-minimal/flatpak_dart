// lookupFunction wrappers for the flatpak_nc shared library.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../internal/library_loader.dart';

// Typedefs for C function signatures.
typedef _InitC = Void Function(Pointer<Void>);
typedef _InitDart = void Function(Pointer<Void>);

typedef _ReaderCreateC = Pointer<Void> Function(Pointer<Utf8>);
typedef _ReaderCreateDart = Pointer<Void> Function(Pointer<Utf8>);

typedef _ReaderDestroyC = Void Function(Pointer<Void>);
typedef _ReaderDestroyDart = void Function(Pointer<Void>);

typedef _ReaderListAppsC = Void Function(Pointer<Void>, Int64, Bool);
typedef _ReaderListAppsDart = void Function(Pointer<Void>, int, bool);

typedef _ReaderPortC = Void Function(Pointer<Void>, Int64);
typedef _ReaderPortDart = void Function(Pointer<Void>, int);

typedef _ReaderPortStringC = Void Function(Pointer<Void>, Int64, Pointer<Utf8>);
typedef _ReaderPortStringDart =
    void Function(Pointer<Void>, int, Pointer<Utf8>);

typedef _ReaderListRemoteAppsC =
    Void Function(Pointer<Void>, Int64, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef _ReaderListRemoteAppsDart =
    void Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>, bool);

typedef _ReaderGetAppInfoC =
    Void Function(
      Pointer<Void>,
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _ReaderGetAppInfoDart =
    void Function(
      Pointer<Void>,
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

typedef _ReaderFetchMetadataC =
    Void Function(Pointer<Void>, Int64, Pointer<Utf8>, Pointer<Utf8>);
typedef _ReaderFetchMetadataDart =
    void Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>);

// Worker typedefs
typedef _WorkerCreateC = Pointer<Void> Function(Pointer<Utf8>);
typedef _WorkerCreateDart = Pointer<Void> Function(Pointer<Utf8>);

typedef _TxCreateC = Pointer<Void> Function(Pointer<Void>, Int64);
typedef _TxCreateDart = Pointer<Void> Function(Pointer<Void>, int);

typedef _TxAddInstallC =
    Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _TxAddInstallDart =
    void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef _TxAddStringC = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _TxAddStringDart = void Function(Pointer<Void>, Pointer<Utf8>);

typedef _TxSubmitC = Void Function(Pointer<Void>);
typedef _TxSubmitDart = void Function(Pointer<Void>);

// Remote management typedefs
typedef _RemoteCreateC = Pointer<Void> Function(Int64);
typedef _RemoteCreateDart = Pointer<Void> Function(int);

typedef _RemoteAddC =
    Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Int64, Bool);
typedef _RemoteAddDart =
    void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, int, bool);

typedef _RemoteAddFromFileC =
    Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef _RemoteAddFromFileDart =
    void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, bool);

typedef _RemoteModifyC =
    Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Int64);
typedef _RemoteModifyDart =
    void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, int);

typedef _RemoteRemoveC = Void Function(Pointer<Void>, Pointer<Utf8>, Bool);
typedef _RemoteRemoveDart = void Function(Pointer<Void>, Pointer<Utf8>, bool);

typedef _RemoteUpdateC = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _RemoteUpdateDart = void Function(Pointer<Void>, Pointer<Utf8>);

// Monitor typedefs
typedef _MonitorCreateC = Pointer<Void> Function(Int64, Pointer<Utf8>);
typedef _MonitorCreateDart = Pointer<Void> Function(int, Pointer<Utf8>);

/// Lazy bindings to the flatpak_nc shared library.
abstract final class FlatpakBindings {
  static final DynamicLibrary _lib = _loadAndInit();

  static DynamicLibrary _loadAndInit() {
    final lib = LibraryLoader.load();
    // Initialize Dart DL API pointers so the C++ side can call
    // Dart_PostCObject_DL from any thread.
    final init = lib.lookupFunction<_InitC, _InitDart>('flatpak_bridge_init');
    init(NativeApi.initializeApiDLData);
    return lib;
  }

  // ── Reader ─────────────────────────────────────────────────────────────
  static final _readerCreate = _lib
      .lookupFunction<_ReaderCreateC, _ReaderCreateDart>(
        'flatpak_reader_create',
      );
  static final _readerDestroy = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_reader_destroy',
      );
  static final _readerListApps = _lib
      .lookupFunction<_ReaderListAppsC, _ReaderListAppsDart>(
        'flatpak_reader_list_apps',
      );
  static final _readerListRemotes = _lib
      .lookupFunction<_ReaderPortC, _ReaderPortDart>(
        'flatpak_reader_list_remotes',
      );
  static final _readerGetRemoteInfo = _lib
      .lookupFunction<_ReaderPortStringC, _ReaderPortStringDart>(
        'flatpak_reader_get_remote_info',
      );
  static final _readerListRemoteApps = _lib
      .lookupFunction<_ReaderListRemoteAppsC, _ReaderListRemoteAppsDart>(
        'flatpak_reader_list_remote_apps',
      );
  static final _readerGetAppInfo = _lib
      .lookupFunction<_ReaderGetAppInfoC, _ReaderGetAppInfoDart>(
        'flatpak_reader_get_app_info',
      );
  static final _readerGetPermissions = _lib
      .lookupFunction<_ReaderPortStringC, _ReaderPortStringDart>(
        'flatpak_reader_get_permissions',
      );
  static final _readerCheckUpdates = _lib
      .lookupFunction<_ReaderPortC, _ReaderPortDart>(
        'flatpak_reader_check_updates',
      );

  static Pointer<Void> readerCreate(String installation) {
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

  static final _readerDropCaches = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_reader_drop_caches',
      );

  static void readerDropCaches(Pointer<Void> handle) =>
      _readerDropCaches(handle);

  static final _readerFetchRemoteMetadata = _lib
      .lookupFunction<_ReaderFetchMetadataC, _ReaderFetchMetadataDart>(
        'flatpak_reader_fetch_remote_metadata',
      );

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

  // ── Worker ─────────────────────────────────────────────────────────────
  static final _workerCreate = _lib
      .lookupFunction<_WorkerCreateC, _WorkerCreateDart>(
        'flatpak_worker_create',
      );
  static final _workerDestroy = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_worker_destroy',
      );
  static final _workerCancelCurrent = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_worker_cancel_current',
      );

  static Pointer<Void> workerCreate(String installation) {
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
  static final _txCreate = _lib.lookupFunction<_TxCreateC, _TxCreateDart>(
    'flatpak_tx_create',
  );
  static final _txDestroy = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_tx_destroy',
      );
  static final _txAddInstall = _lib
      .lookupFunction<_TxAddInstallC, _TxAddInstallDart>(
        'flatpak_tx_add_install',
      );
  static final _txAddUpdate = _lib
      .lookupFunction<_TxAddStringC, _TxAddStringDart>('flatpak_tx_add_update');
  static final _txAddUninstall = _lib
      .lookupFunction<_TxAddStringC, _TxAddStringDart>(
        'flatpak_tx_add_uninstall',
      );
  static final _txAddInstallBundle = _lib
      .lookupFunction<_TxAddStringC, _TxAddStringDart>(
        'flatpak_tx_add_install_bundle',
      );
  static final _txSubmit = _lib.lookupFunction<_TxSubmitC, _TxSubmitDart>(
    'flatpak_tx_submit',
  );

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
  static final _userRemoteCreate = _lib
      .lookupFunction<_RemoteCreateC, _RemoteCreateDart>(
        'flatpak_user_remote_create',
      );
  static final _userRemoteDestroy = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_user_remote_destroy',
      );
  static final _userRemoteAdd = _lib
      .lookupFunction<_RemoteAddC, _RemoteAddDart>('flatpak_user_remote_add');
  static final _userRemoteAddFromFile = _lib
      .lookupFunction<_RemoteAddFromFileC, _RemoteAddFromFileDart>(
        'flatpak_user_remote_add_from_file',
      );
  static final _userRemoteModify = _lib
      .lookupFunction<_RemoteModifyC, _RemoteModifyDart>(
        'flatpak_user_remote_modify',
      );
  static final _userRemoteRemove = _lib
      .lookupFunction<_RemoteRemoveC, _RemoteRemoveDart>(
        'flatpak_user_remote_remove',
      );
  static final _userRemoteUpdate = _lib
      .lookupFunction<_RemoteUpdateC, _RemoteUpdateDart>(
        'flatpak_user_remote_update',
      );

  static Pointer<Void> userRemoteCreate(int port) => _userRemoteCreate(port);
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
  static final _systemRemoteCreate = _lib
      .lookupFunction<_RemoteCreateC, _RemoteCreateDart>(
        'flatpak_system_remote_create',
      );
  static final _systemRemoteDestroy = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_system_remote_destroy',
      );
  static final _systemRemoteAdd = _lib
      .lookupFunction<_RemoteAddC, _RemoteAddDart>('flatpak_system_remote_add');
  static final _systemRemoteAddFromFile = _lib
      .lookupFunction<_RemoteAddFromFileC, _RemoteAddFromFileDart>(
        'flatpak_system_remote_add_from_file',
      );
  static final _systemRemoteModify = _lib
      .lookupFunction<_RemoteModifyC, _RemoteModifyDart>(
        'flatpak_system_remote_modify',
      );
  static final _systemRemoteRemove = _lib
      .lookupFunction<_RemoteRemoveC, _RemoteRemoveDart>(
        'flatpak_system_remote_remove',
      );
  static final _systemRemoteUpdate = _lib
      .lookupFunction<_RemoteUpdateC, _RemoteUpdateDart>(
        'flatpak_system_remote_update',
      );

  static Pointer<Void> systemRemoteCreate(int port) =>
      _systemRemoteCreate(port);
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
  static final _monitorCreate = _lib
      .lookupFunction<_MonitorCreateC, _MonitorCreateDart>(
        'flatpak_monitor_create',
      );
  static final _monitorClose = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_monitor_close',
      );
  static final _monitorDestroy = _lib
      .lookupFunction<_ReaderDestroyC, _ReaderDestroyDart>(
        'flatpak_monitor_destroy',
      );

  static Pointer<Void> monitorCreate(int port, String installation) {
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
