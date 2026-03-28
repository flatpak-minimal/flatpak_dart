// lib/providers/remote_provider.dart
//
// Central state for the remote manager app.
// All I/O goes through FlatpakClient from flatpak_dart.
//
// Lifecycle:
//   1. init()  — opens FlatpakClient + loads remote list
//   2. selectRemote(name) — changes active remote, cancels prev stream, starts new
//   3. add / remove / repopulate — mutation, then reload

import 'dart:async';

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flutter/foundation.dart';

/// Status for the package list stream.
enum PackageLoadState { idle, streaming, done, error }

class RemoteProvider extends ChangeNotifier {
  FlatpakClient? _client;

  // ── Remote list state ─────────────────────────────────────────────────
  List<FlatpakRemote> _remotes   = [];
  bool                _loadingRemotes = false;
  String?             _remoteError;

  List<FlatpakRemote> get remotes       => List.unmodifiable(_remotes);
  bool                get loadingRemotes => _loadingRemotes;
  String?             get remoteError   => _remoteError;

  // ── Selected remote ────────────────────────────────────────────────────
  String? _selectedName;
  String? get selectedName => _selectedName;

  FlatpakRemote? get selected =>
      _selectedName == null
          ? null
          : _remotes.where((r) => r.name == _selectedName).firstOrNull;

  // ── Package list state ────────────────────────────────────────────────
  final List<FlatpakRef> _packages    = [];
  PackageLoadState       _loadState   = PackageLoadState.idle;
  String?                _packageError;
  StreamSubscription<FlatpakRef>? _packageSub;
  String                 _packageFilter = '';

  List<FlatpakRef> get packages     => _applyFilter(_packages);
  PackageLoadState get loadState    => _loadState;
  String?          get packageError => _packageError;
  int              get totalLoaded  => _packages.length;

  String get packageFilter => _packageFilter;
  set packageFilter(String v) {
    _packageFilter = v;
    notifyListeners();
  }

  // ── Initialisation ────────────────────────────────────────────────────

  Future<void> init() async {
    // Use user installation so no polkit prompt is needed.
    _client = await FlatpakClient.user();
    await _loadRemotes();
  }

  // ── Remote operations ─────────────────────────────────────────────────

  Future<void> _loadRemotes() async {
    _loadingRemotes = true;
    _remoteError    = null;
    notifyListeners();
    try {
      _remotes = await _client!.remotes.list();
      // Auto-select first non-disabled remote on first load.
      if (_selectedName == null) {
        final first = _remotes.where((r) => !r.disabled).firstOrNull;
        if (first != null) await selectRemote(first.name, loadPackages: true);
      }
    } catch (e) {
      _remoteError = e.toString();
    } finally {
      _loadingRemotes = false;
      notifyListeners();
    }
  }

  /// Change the active remote and begin streaming its packages.
  Future<void> selectRemote(String name, {bool loadPackages = true}) async {
    _selectedName = name;
    notifyListeners();
    if (loadPackages) await _loadPackages();
  }

  /// Add a remote. Accepts any [FlatpakRemoteConfig], including [KnownRemotes].
  Future<void> addRemote(String name, FlatpakRemoteConfig config) async {
    await _client!.remotes.add(name, config);
    await _loadRemotes();
    // Auto-select the newly added remote.
    await selectRemote(name, loadPackages: true);
  }

  /// Add a remote from a downloaded .flatpakrepo file path.
  Future<void> addRemoteFromFile(String name, String filePath) async {
    await _client!.remotes.addFromFile(name, filePath);
    await _loadRemotes();
    await selectRemote(name, loadPackages: true);
  }

  /// Remove a remote by name.
  Future<void> removeRemote(String name, {bool force = false}) async {
    await _client!.remotes.remove(name, force: force);
    if (_selectedName == name) {
      _selectedName = null;
      _cancelPackageStream();
    }
    await _loadRemotes();
  }

  /// Enable or disable a remote without removing it.
  Future<void> toggleDisabled(String name) async {
    final r = _remotes.where((r) => r.name == name).firstOrNull;
    if (r == null) return;
    r.disabled
        ? await _client!.remotes.enable(name)
        : await _client!.remotes.disable(name);
    await _loadRemotes();
  }

  /// Remove all non-static remotes and re-add the four Flathub variants
  /// plus Fedora.  Intended as the "repopulate" / factory-reset action.
  Future<void> repopulateWithFlathub() async {
    // Remove all user-writable remotes.
    final toRemove = _remotes.where((r) => !r.isStatic).toList();
    for (final r in toRemove) {
      await _client!.remotes.remove(r.name, force: true);
    }
    // Add the standard set.
    await _client!.remotes.add('flathub',              KnownRemotes.flathub,
        ifNotExists: true);
    await _client!.remotes.add('flathub-verified',     KnownRemotes.flathubVerified,
        ifNotExists: true);
    await _client!.remotes.add('flathub-floss',        KnownRemotes.flathubFloss,
        ifNotExists: true);
    await _client!.remotes.add('flathub-verified_floss',
        KnownRemotes.flathubVerifiedFloss, ifNotExists: true);

    await _loadRemotes();
    await selectRemote('flathub', loadPackages: true);
  }

  // ── Package loading ───────────────────────────────────────────────────

  Future<void> _loadPackages() async {
    _cancelPackageStream();
    _packages.clear();
    _packageError = null;
    _loadState    = PackageLoadState.streaming;
    notifyListeners();

    final remote = _selectedName;
    if (remote == null) {
      _loadState = PackageLoadState.idle;
      notifyListeners();
      return;
    }

    try {
      _packageSub = _client!.remotes
          .listApps(remote, includeRuntimes: false)
          .listen(
        (ref) {
          if (_selectedName != remote) return; // stale stream
          _packages.add(ref);
          // Batch notify every 50 refs to avoid flooding the UI.
          if (_packages.length % 50 == 0) notifyListeners();
        },
        onDone: () {
          _loadState = PackageLoadState.done;
          notifyListeners();
        },
        onError: (Object e) {
          _packageError = e.toString();
          _loadState    = PackageLoadState.error;
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _packageError = e.toString();
      _loadState    = PackageLoadState.error;
      notifyListeners();
    }
  }

  void _cancelPackageStream() {
    _packageSub?.cancel();
    _packageSub = null;
  }

  List<FlatpakRef> _applyFilter(List<FlatpakRef> all) {
    if (_packageFilter.isEmpty) return List.unmodifiable(all);
    final q = _packageFilter.toLowerCase();
    return all.where((r) => r.name.toLowerCase().contains(q)).toList();
  }

  // ── Refresh ───────────────────────────────────────────────────────────

  Future<void> refresh() async {
    await _loadRemotes();
    if (_selectedName != null) await _loadPackages();
  }

  @override
  void dispose() {
    _cancelPackageStream();
    _client?.close();
    super.dispose();
  }
}