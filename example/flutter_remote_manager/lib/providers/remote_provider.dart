// lib/providers/remote_provider.dart
//
// Central state for the remote manager app.
// All I/O goes through FlatpakClient from flatpak_dart.

import 'dart:async';

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flutter/foundation.dart';

/// Status for the package list stream.
enum PackageLoadState { idle, streaming, done, error }

class RemoteProvider extends ChangeNotifier {
  FlatpakClient? _client;

  // ── Remote list state ─────────────────────────────────────────────────
  List<FlatpakRemote> _remotes = [];
  bool _loadingRemotes = false;
  String? _remoteError;

  List<FlatpakRemote> get remotes => List.unmodifiable(_remotes);
  bool get loadingRemotes => _loadingRemotes;
  String? get remoteError => _remoteError;

  // ── Selected remote ────────────────────────────────────────────────────
  String? _selectedName;
  String? get selectedName => _selectedName;

  FlatpakRemote? get selected => _selectedName == null
      ? null
      : _remotes.where((r) => r.name == _selectedName).firstOrNull;

  // ── Package list state ────────────────────────────────────────────────
  final List<FlatpakRef> _packages = [];
  PackageLoadState _loadState = PackageLoadState.idle;
  String? _packageError;
  StreamSubscription<FlatpakRef>? _packageSub;
  String _packageFilter = '';

  List<FlatpakRef> get packages => _applyFilter(_packages);
  PackageLoadState get loadState => _loadState;
  String? get packageError => _packageError;
  int get totalLoaded => _packages.length;

  String get packageFilter => _packageFilter;
  set packageFilter(String v) {
    _packageFilter = v;
    notifyListeners();
  }

  // ── Initialisation ────────────────────────────────────────────────────

  Future<void> init() async {
    _client = FlatpakClient.user();
    await _refreshRemoteList();
    // Auto-select first remote (prefer enabled).
    final first =
        _remotes.where((r) => !r.disabled).firstOrNull ?? _remotes.firstOrNull;
    if (first != null) {
      await selectRemote(first.name);
    }
  }

  // ── Internal: just reload the remote list, no side effects ────────────

  Future<void> _refreshRemoteList() async {
    _loadingRemotes = true;
    _remoteError = null;
    notifyListeners();
    try {
      _client!.dropCaches();
      _remotes = await _client!.remotes.list();
    } catch (e) {
      _remoteError = e.toString();
    } finally {
      _loadingRemotes = false;
      notifyListeners();
    }
  }

  // ── Remote operations ─────────────────────────────────────────────────

  /// Change the active remote and begin streaming its packages.
  Future<void> selectRemote(String name, {bool loadPackages = true}) async {
    _selectedName = name;
    await _cancelPackageStream();
    _packages.clear();
    _packageFilter = '';

    final r = _remotes.where((r) => r.name == name).firstOrNull;
    if (!loadPackages || r == null || r.disabled) {
      _loadState = PackageLoadState.idle;
      notifyListeners();
      return;
    }

    await _loadPackages();
  }

  /// Add a remote.
  Future<void> addRemote(String name, FlatpakRemoteConfig config) async {
    await _client!.remotes.add(name, config);
    await _refreshRemoteList();
    await selectRemote(name);
  }

  /// Add a remote from a downloaded .flatpakrepo file path.
  Future<void> addRemoteFromFile(String name, String filePath) async {
    await _client!.remotes.addFromFile(name, filePath);
    await _refreshRemoteList();
    await selectRemote(name);
  }

  /// Remove a remote by name.
  Future<void> removeRemote(String name, {bool force = false}) async {
    await _client!.remotes.remove(name, force: force);
    if (_selectedName == name) {
      _selectedName = null;
      await _cancelPackageStream();
      _packages.clear();
      _loadState = PackageLoadState.idle;
    }
    await _refreshRemoteList();
    // Auto-select if current selection is gone
    if (_selectedName == null ||
        !_remotes.any((r) => r.name == _selectedName)) {
      _selectedName = _remotes.where((r) => !r.disabled).firstOrNull?.name;
      notifyListeners();
      if (_selectedName != null) await _loadPackages();
    }
  }

  /// Enable or disable a remote without removing it.
  Future<void> toggleDisabled(String name) async {
    final r = _remotes.where((r) => r.name == name).firstOrNull;
    if (r == null) return;

    if (r.disabled) {
      await _client!.remotes.enable(name);
    } else {
      await _client!.remotes.disable(name);
    }

    // Re-read remote list to get confirmed state from libflatpak
    await _refreshRemoteList();

    // Verify the state actually changed
    final updated = _remotes.where((r) => r.name == name).firstOrNull;
    if (updated == null) return;

    // Re-select to update package list based on confirmed state
    await selectRemote(name);
  }

  /// Remove all non-static remotes and re-add the four Flathub variants.
  Future<void> repopulateWithFlathub() async {
    final toRemove = _remotes.where((r) => !r.isStatic).toList();
    for (final r in toRemove) {
      try {
        await _client!.remotes.remove(r.name, force: true);
      } catch (_) {}
    }
    await _client!.remotes.add(
      'flathub',
      KnownRemotes.flathub,
      ifNotExists: true,
    );
    await _client!.remotes.add(
      'flathub-verified',
      KnownRemotes.flathubVerified,
      ifNotExists: true,
    );
    await _client!.remotes.add(
      'flathub-floss',
      KnownRemotes.flathubFloss,
      ifNotExists: true,
    );
    await _client!.remotes.add(
      'flathub-verified_floss',
      KnownRemotes.flathubVerifiedFloss,
      ifNotExists: true,
    );

    _selectedName = null;
    await _refreshRemoteList();
    await selectRemote('flathub');
  }

  // ── Package loading ───────────────────────────────────────────────────

  Future<void> _loadPackages() async {
    await _cancelPackageStream();
    _packages.clear();
    _packageError = null;
    _loadState = PackageLoadState.streaming;
    _packageFilter = '';
    notifyListeners();

    final remote = _selectedName;
    if (remote == null || _client == null) {
      _loadState = PackageLoadState.idle;
      notifyListeners();
      return;
    }

    try {
      _packageSub = _client!.remotes
          .listApps(remote, includeRuntimes: false)
          .listen(
            (ref) {
              if (_selectedName != remote) return;
              _packages.add(ref);
              if (_packages.length % 50 == 0) notifyListeners();
            },
            onDone: () {
              if (_selectedName != remote) return;
              _loadState = PackageLoadState.done;
              notifyListeners();
            },
            onError: (Object e) {
              if (_selectedName != remote) return;
              _packageError = e.toString();
              _loadState = PackageLoadState.error;
              notifyListeners();
            },
            cancelOnError: true,
          );
    } catch (e) {
      _packageError = e.toString();
      _loadState = PackageLoadState.error;
      notifyListeners();
    }
  }

  Future<void> _cancelPackageStream() async {
    await _packageSub?.cancel();
    _packageSub = null;
  }

  List<FlatpakRef> _applyFilter(List<FlatpakRef> all) {
    if (_packageFilter.isEmpty) return List.unmodifiable(all);
    final q = _packageFilter.toLowerCase();
    return all.where((r) => r.name.toLowerCase().contains(q)).toList();
  }

  // ── Refresh ───────────────────────────────────────────────────────────

  Future<void> refresh() async {
    await _refreshRemoteList();
    if (_selectedName != null) await _loadPackages();
  }

  @override
  void dispose() {
    _cancelPackageStream();
    _client?.close();
    super.dispose();
  }
}
