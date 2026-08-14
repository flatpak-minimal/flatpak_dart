// Mock bridge for unit testing without the native library.

import 'package:flatpak_dart/flatpak_dart.dart';

class MockFlatpakBridge {
  // ── Remote list stubbing ──────────────────────────────────────────────
  List<FlatpakRemote>? _stubbedRemotes;
  void stubListRemotes(List<FlatpakRemote> remotes) =>
      _stubbedRemotes = remotes;
  List<FlatpakRemote> get stubbedRemotes => _stubbedRemotes ?? [];

  // ── Remote info stubbing ──────────────────────────────────────────────
  FlatpakRemote? _stubbedRemoteInfo;
  void stubRemoteInfo(FlatpakRemote info) => _stubbedRemoteInfo = info;
  FlatpakRemote? get stubbedRemoteInfo => _stubbedRemoteInfo;

  // ── Add tracking ─────────────────────────────────────────────────────
  String? lastAddName;
  FlatpakRemoteConfig? lastAddConfig;
  bool? lastIfNotExists;
  String? lastAddFromFilePath;

  // ── Modify tracking ──────────────────────────────────────────────────
  String? lastModifyName;
  FlatpakRemoteConfig? lastModifyConfig;

  // ── Remove tracking ──────────────────────────────────────────────────
  String? removeCalledWith;
  bool? lastRemoveForce;
  bool _staticRemoveError = false;
  String? _staticRemoveErrorName;

  /// True once [stubStaticRemoveError] has armed a remove failure.
  bool get staticRemoveError => _staticRemoveError;

  /// Remote name that [stubStaticRemoveError] was armed with.
  String? get staticRemoveErrorName => _staticRemoveErrorName;

  void stubStaticRemoveError(String name) {
    _staticRemoveError = true;
    _staticRemoveErrorName = name;
  }

  // ── List remote apps stubbing ─────────────────────────────────────────
  final Map<String, List<FlatpakRef>> _stubbedRemoteApps = {};
  void stubListRemoteApps(String remote, List<FlatpakRef> refs) =>
      _stubbedRemoteApps[remote] = refs;
  List<FlatpakRef> stubbedListRemoteApps(String remote) =>
      _stubbedRemoteApps[remote] ?? [];
}

class MockTransactionBridge {
  void Function(String ref)? onExecute;
  void Function(List<dynamic>)? onSubmit;
  bool _blocked = false;

  /// True while a transaction is being held by [blockFirstTx].
  bool get blocked => _blocked;

  void blockFirstTx() => _blocked = true;
  void releaseTx() => _blocked = false;
}
