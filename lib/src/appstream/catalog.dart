// Flatpak-specific glue over the appstream_dart engine: locate a remote's
// downloaded catalog, trigger a refresh, resolve installed-app icons, and
// delegate parsing/querying to appstream_dart.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:appstream_dart/appstream.dart';
import 'package:path/path.dart' as p;

import '../application.dart';
import '../exceptions.dart';
import '../installation.dart';
import '../installation_paths.dart';
import 'catalog_cache.dart';
import 'installed_icons.dart';

class FlatpakAppStream {
  FlatpakAppStream(this._installation, this.installationPath);

  /// Build for a named installation (`user` / `system` / absolute path).
  factory FlatpakAppStream.forName(FlatpakInstallation installation) =>
      FlatpakAppStream(installation, installationPathFor(installation.name));

  final FlatpakInstallation _installation;

  /// Base directory of the flatpak installation whose `appstream/` subtree
  /// holds the downloaded per-remote catalogs.
  final String installationPath;

  /// Open catalog databases, keyed by cache key. Opening SQLite per lookup
  /// dominates the cost of resolving metadata for a list of apps.
  ///
  /// Holds the in-flight open rather than the resolved handle so that
  /// concurrent lookups for the same catalog join one build instead of racing
  /// each other into the same database file — a caller resolving metadata for
  /// a grid of apps with `Future.wait` would otherwise have one task delete
  /// the file another is still parsing into.
  final _openDatabases = <String, Future<CatalogDatabase>>{};

  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    Appstream.initialize();
    _initialized = true;
  }

  // ── Catalog location ─────────────────────────────────────────────────────

  /// Resolve the on-disk AppStream catalog file for [remote].
  ///
  /// Two layouts occur in the wild and both are searched, `active/` first:
  /// flatpak's `appstream2` deploy puts the catalog under an `active` symlink
  /// pointing at the current commit, while the older `appstream` deploy writes
  /// it straight into the architecture directory. A host can have one remote of
  /// each — Flathub on the new layout, a distribution remote on the old one —
  /// so looking only under `active/` reports a downloaded catalog as missing.
  ///
  /// Prefers the uncompressed `appstream.xml`, falling back to `appstream.xml.gz`.
  /// When [arch] is empty the first architecture directory present for the
  /// remote is used. Returns `null` when no catalog has been downloaded.
  String? catalogPath(String remote, {String arch = ''}) {
    final remoteDir = p.join(installationPath, 'appstream', remote);
    final chosenArch = arch.isNotEmpty ? arch : _firstArch(remoteDir);
    if (chosenArch == null) return null;

    final archDir = p.join(remoteDir, chosenArch);
    for (final dir in [p.join(archDir, 'active'), archDir]) {
      for (final name in const ['appstream.xml', 'appstream.xml.gz']) {
        final f = p.join(dir, name);
        if (File(f).existsSync()) return f;
      }
    }
    return null;
  }

  static String? _firstArch(String remoteDir) {
    final dir = Directory(remoteDir);
    if (!dir.existsSync()) return null;
    final arches =
        dir
            .listSync()
            .whereType<Directory>()
            .map((d) => p.basename(d.path))
            .toList()
          ..sort();
    if (arches.isEmpty) return null;
    // Prefer the host architecture when present.
    final host = _hostFlatpakArch;
    if (host != null && arches.contains(host)) return host;
    return arches.first;
  }

  /// Host arch in flatpak's naming. Resolved once — it cannot change within a
  /// process, and `uname` is a blocking subprocess spawn.
  static final String? _hostFlatpakArch = () {
    try {
      final m = Process.runSync('uname', ['-m']).stdout.toString().trim();
      return switch (m) {
        'x86_64' => 'x86_64',
        'aarch64' || 'arm64' => 'aarch64',
        'i686' || 'i386' => 'i386',
        'armv7l' => 'arm',
        _ => m.isEmpty ? null : m,
      };
    } catch (_) {
      return null;
    }
  }();

  // ── Catalog refresh ──────────────────────────────────────────────────────

  /// Refresh [remote]'s AppStream catalog (native `update_appstream_sync`).
  /// Empty [arch] refreshes the default architecture.
  Future<void> refresh(String remote, {String arch = ''}) async {
    await _installation.refreshAppstream(remote, arch: arch);
    // The catalog on disk just changed; drop cached handles so the next
    // lookup re-parses instead of querying the superseded database.
    await close();
  }

  // ── Component metadata (delegated to appstream_dart) ─────────────────────

  /// Full metadata for [appId] — icons, screenshots, releases, categories,
  /// keywords, languages, urls — from the remote catalog.
  ///
  /// When [remote] is empty every configured remote's catalog is searched.
  /// Returns `null` if no catalog lists [appId]. [language] selects the
  /// translation locale (empty = source strings).
  Future<ComponentDetail?> componentDetail(
    String appId, {
    String remote = '',
    String arch = '',
    String language = '',
  }) async {
    for (final r in await _remoteNames(remote)) {
      final db = await _openCatalog(r, arch: arch, language: language);
      if (db == null) continue;
      final detail = await db.getComponentDetail(appId);
      if (detail != null) return detail;
    }
    return null;
  }

  /// Metadata for several apps in one pass, keyed by app id. Reuses each
  /// catalog across the whole batch instead of reopening it per app.
  Future<Map<String, ComponentDetail>> componentDetails(
    Iterable<String> appIds, {
    String remote = '',
    String arch = '',
    String language = '',
  }) async {
    final pending = appIds.toSet();
    final out = <String, ComponentDetail>{};

    for (final r in await _remoteNames(remote)) {
      if (pending.isEmpty) break;
      final db = await _openCatalog(r, arch: arch, language: language);
      if (db == null) continue;
      for (final appId in pending.toList()) {
        final detail = await db.getComponentDetail(appId);
        if (detail != null) {
          out[appId] = detail;
          pending.remove(appId);
        }
      }
    }
    return out;
  }

  Future<List<String>> _remoteNames(String remote) async {
    if (remote.isNotEmpty) return [remote];
    final remotes = await _installation.listRemotes();
    return [for (final r in remotes) r.name];
  }

  /// Opens (parsing/caching as needed) the SQLite catalog for [remote].
  /// Returns `null` when [remote] has no downloaded catalog.
  ///
  /// Deliberately not `async`: everything up to and including the memo write
  /// runs in one synchronous turn, so a second caller for the same key cannot
  /// interleave between the cache miss and the entry being installed.
  Future<CatalogDatabase?> _openCatalog(
    String remote, {
    String arch = '',
    String language = '',
  }) {
    final xmlOrGz = catalogPath(remote, arch: arch);
    if (xmlOrGz == null) return Future.value(null);

    final key = catalogCacheKey(
      installationName: _installation.name,
      remote: remote,
      arch: arch,
      language: language,
    );
    final dbPath = _dbPathFor(key);

    final cached = _openDatabases[key];
    if (cached != null && !catalogNeedsRebuild(dbPath, xmlOrGz)) return cached;

    final opening = _buildAndOpen(
      remote: remote,
      key: key,
      dbPath: dbPath,
      xmlOrGz: xmlOrGz,
      language: language,
      superseded: cached,
    );
    _openDatabases[key] = opening;
    // A failed build must not stay memoised, or every later lookup replays the
    // same error. Guarded by identity so a newer entry is never evicted.
    unawaited(
      opening.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_openDatabases[key], opening)) {
            _openDatabases.remove(key);
          }
        },
      ),
    );
    return opening;
  }

  Future<CatalogDatabase> _buildAndOpen({
    required String remote,
    required String key,
    required String dbPath,
    required String xmlOrGz,
    required String language,
    required Future<CatalogDatabase>? superseded,
  }) async {
    if (superseded != null) {
      try {
        await (await superseded).close();
      } catch (_) {
        // The handle we are replacing failed to open or close; either way it
        // must not block the rebuild.
      }
    }

    _ensureInitialized();

    if (catalogNeedsRebuild(dbPath, xmlOrGz)) {
      final xmlPath = await _materializeXml(
        xmlOrGz,
        p.join(_cacheDir.path, '$key.xml'),
      );
      final dbFile = File(dbPath);
      if (dbFile.existsSync()) dbFile.deleteSync();
      try {
        await for (final event in Appstream.parseToSqlite(
          xmlPath: xmlPath,
          dbPath: dbPath,
          language: language,
        )) {
          if (event is ParseFailed) {
            throw StateError(
              'AppStream parse failed for $remote: ${event.message}',
            );
          }
          if (event is ParseDone) break;
        }
      } finally {
        // The decompressed intermediate is only an input to the parse; a
        // Flathub catalog is tens of MB uncompressed.
        if (xmlPath != xmlOrGz) {
          final tmp = File(xmlPath);
          if (tmp.existsSync()) tmp.deleteSync();
        }
      }
      stampCatalogSource(dbPath, xmlOrGz);
    }

    return CatalogDatabase.open(dbPath);
  }

  /// Closes every cached catalog database. Safe to call repeatedly.
  ///
  /// Does not wait for in-flight lookups: a [componentDetail] call that is
  /// already holding a handle will see it closed underneath it, so close (and
  /// [refresh], which closes) only when no lookup is outstanding.
  Future<void> close() async {
    final open = _openDatabases.values.toList();
    _openDatabases.clear();
    for (final pending in open) {
      try {
        await (await pending).close();
      } catch (_) {
        // An open that never completed has nothing to close.
      }
    }
  }

  // ── Cache directory ──────────────────────────────────────────────────────

  /// Per-user cache root, verified 0700 and owner-only. A shared world-writable
  /// temp dir would let another local user pre-create these predictably named
  /// files and feed the parser a database of their choosing — so every path
  /// that cannot be verified degrades to a private mkdtemp directory rather
  /// than to a predictable one.
  static final Directory _cacheDir = _createCacheDir();

  static Directory _createCacheDir() {
    final xdg = Platform.environment['XDG_CACHE_HOME'];
    final home = Platform.environment['HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : (home != null && home.isNotEmpty ? p.join(home, '.cache') : null);

    // With no per-user cache root to anchor to (daemons, systemd units,
    // minimal containers), a fixed name under the shared temp dir is exactly
    // the pre-creation target this cache must not offer. mkdtemp is 0700 and
    // unguessable by construction; the cost is one catalog rebuild per process.
    if (base != null) {
      try {
        final dir = Directory(p.join(base, 'flatpak_dart', 'appstream'));
        dir.createSync(recursive: true);
        if (_isPrivateDirectory(dir)) return dir;
      } catch (_) {
        // Unwritable, or something in the chain is not a directory.
      }
    }
    return Directory.systemTemp.createTempSync('flatpak_dart_appstream_');
  }

  /// Whether [dir] is a real directory — not a symlink someone else planted —
  /// that only its owner can read, write, or traverse.
  static bool _isPrivateDirectory(Directory dir) {
    if (Platform.isWindows) return true;
    if (FileSystemEntity.isLinkSync(dir.path)) return false;
    // createSync honours the umask, which may leave the directory group- or
    // world-readable, and a directory we inherited may be looser still. chmod
    // fails with EPERM when the directory belongs to another user, which is
    // the case that matters most here — so its exit code is the ownership
    // check, and the mode is read back rather than assumed.
    final ProcessResult chmod;
    try {
      chmod = Process.runSync('chmod', ['700', dir.path]);
    } on ProcessException {
      return false;
    }
    if (chmod.exitCode != 0) return false;
    final stat = dir.statSync();
    return stat.type == FileSystemEntityType.directory &&
        (stat.mode & 0x1FF) == 0x1C0; // 0700
  }

  String _dbPathFor(String key) => p.join(_cacheDir.path, '$key.sqlite');

  /// Ensure a plain XML file exists at [xmlDest], decompressing the source when
  /// it is gzip-compressed. Returns the path to the usable XML.
  Future<String> _materializeXml(String source, String xmlDest) async {
    if (!source.endsWith('.gz')) return source;
    // gzip.decode is synchronous and the catalog is tens of MB; decode off the
    // calling isolate so a UI thread is not blocked for the duration.
    await Isolate.run(() {
      final decoded = gzip.decode(File(source).readAsBytesSync());
      File(xmlDest).writeAsBytesSync(decoded, flush: true);
    });
    return xmlDest;
  }

  // ── Installed-app icons (pure Dart) ──────────────────────────────────────

  /// Absolute path to the best on-disk icon for the installed [app], or `null`.
  String? installedIconPathFor(FlatpakApplication app) =>
      resolveInstalledIconPath(app.installedPath, app.ref.name);

  /// Absolute path to the best on-disk icon for installed [appId], or `null`
  /// when it is not installed or ships no icon.
  ///
  /// Resolves the one app's deploy directory directly rather than enumerating
  /// the installation to find it. For several apps use [installedIconPaths],
  /// which walks the installation once; prefer [installedIconPathFor] when the
  /// [FlatpakApplication] is already in hand.
  Future<String?> installedIconPath(String appId) async {
    final FlatpakApplication app;
    try {
      app = await _installation.getAppInfo(appId);
    } on FlatpakNotFoundException {
      return null;
    }
    return resolveInstalledIconPath(app.installedPath, appId);
  }

  /// Icon paths for [appIds], keyed by app id, from a single enumeration.
  /// Apps that are not installed or ship no icon are absent from the result.
  Future<Map<String, String>> installedIconPaths(
    Iterable<String> appIds,
  ) async {
    final wanted = appIds.toSet();
    if (wanted.isEmpty) return const {};

    final out = <String, String>{};
    for (final app in await _installation.listApplications()) {
      final id = app.ref.name;
      if (!wanted.contains(id) || out.containsKey(id)) continue;
      final icon = resolveInstalledIconPath(app.installedPath, id);
      if (icon != null) out[id] = icon;
    }
    return out;
  }
}
