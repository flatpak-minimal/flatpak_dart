// Flatpak-specific glue over the appstream_dart engine: locate a remote's
// downloaded catalog, trigger a refresh, resolve installed-app icons, and
// delegate parsing/querying to appstream_dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:appstream_dart/appstream.dart';
import 'package:path/path.dart' as p;

import '../application.dart';
import '../installation.dart';
import 'installed_icons.dart';

class FlatpakAppStream {
  FlatpakAppStream(this._installation, this.installationPath);

  /// Build for a named installation (`user` / `system` / absolute path).
  factory FlatpakAppStream.forName(FlatpakInstallation installation) =>
      FlatpakAppStream(installation, _resolveInstallPath(installation.name));

  final FlatpakInstallation _installation;

  /// Base directory of the flatpak installation whose `appstream/` subtree
  /// holds the downloaded per-remote catalogs.
  final String installationPath;

  /// Open catalog databases, keyed by cache key. Opening SQLite per lookup
  /// dominates the cost of resolving metadata for a list of apps.
  final _openDatabases = <String, CatalogDatabase>{};

  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    Appstream.initialize();
    _initialized = true;
  }

  static String _resolveInstallPath(String name) {
    switch (name) {
      case 'user':
        final xdg = Platform.environment['XDG_DATA_HOME'];
        final base = (xdg != null && xdg.isNotEmpty)
            ? xdg
            : p.join(Platform.environment['HOME'] ?? '', '.local', 'share');
        return p.join(base, 'flatpak');
      case 'system':
        return '/var/lib/flatpak';
      default:
        return name; // installation created via FlatpakClient.at(path)
    }
  }

  // ── Catalog location ─────────────────────────────────────────────────────

  /// Resolve the on-disk AppStream catalog file for [remote].
  ///
  /// Prefers the uncompressed `appstream.xml`, falling back to `appstream.xml.gz`.
  /// When [arch] is empty the first architecture directory present for the
  /// remote is used. Returns `null` when no catalog has been downloaded.
  String? catalogPath(String remote, {String arch = ''}) {
    final remoteDir = p.join(installationPath, 'appstream', remote);
    final chosenArch = arch.isNotEmpty ? arch : _firstArch(remoteDir);
    if (chosenArch == null) return null;

    final activeDir = p.join(remoteDir, chosenArch, 'active');
    for (final name in const ['appstream.xml', 'appstream.xml.gz']) {
      final f = p.join(activeDir, name);
      if (File(f).existsSync()) return f;
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
  Future<CatalogDatabase?> _openCatalog(
    String remote, {
    String arch = '',
    String language = '',
  }) async {
    final xmlOrGz = catalogPath(remote, arch: arch);
    if (xmlOrGz == null) return null;

    final key =
        '${_installKey()}_${_slug(remote)}_${arch.isEmpty ? 'default' : _slug(arch)}'
        '_${language.isEmpty ? 'src' : _slug(language)}';

    final cached = _openDatabases[key];
    if (cached != null && !_needsRebuild(_dbPathFor(key), xmlOrGz)) {
      return cached;
    }
    if (cached != null) {
      _openDatabases.remove(key);
      await cached.close();
    }

    _ensureInitialized();
    final dbPath = _dbPathFor(key);

    if (_needsRebuild(dbPath, xmlOrGz)) {
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
      _stampDbSource(dbPath, xmlOrGz);
    }

    final db = CatalogDatabase.open(dbPath);
    _openDatabases[key] = db;
    return db;
  }

  /// Closes every cached catalog database. Safe to call repeatedly.
  Future<void> close() async {
    final open = _openDatabases.values.toList();
    _openDatabases.clear();
    for (final db in open) {
      await db.close();
    }
  }

  // ── Cache directory ──────────────────────────────────────────────────────

  /// Per-user cache root, created 0700. A shared world-writable temp dir would
  /// let another local user pre-create these predictably named files and feed
  /// the parser a database of their choosing.
  static final Directory _cacheDir = _createCacheDir();

  static Directory _createCacheDir() {
    final xdg = Platform.environment['XDG_CACHE_HOME'];
    final home = Platform.environment['HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : (home != null && home.isNotEmpty
              ? p.join(home, '.cache')
              : Directory.systemTemp.path);
    final dir = Directory(p.join(base, 'flatpak_dart', 'appstream'));
    dir.createSync(recursive: true);
    if (!Platform.isWindows) {
      // createSync honours the umask, which may leave the directory group- or
      // world-readable.
      Process.runSync('chmod', ['700', dir.path]);
    }
    return dir;
  }

  String _dbPathFor(String key) => p.join(_cacheDir.path, '$key.sqlite');

  /// Records the source mtime the database was built from, so a catalog that
  /// moves *backwards* in time still invalidates. Flatpak swaps the `active`
  /// symlink between deploy directories, so the new catalog's mtime is not
  /// guaranteed to be newer than the database built from the old one.
  File _stampFileFor(String dbPath) => File('$dbPath.source');

  void _stampDbSource(String dbPath, String sourcePath) {
    try {
      final stamp =
          '${File(sourcePath).lastModifiedSync().toUtc().toIso8601String()}\n'
          '${File(sourcePath).absolute.path}\n';
      _stampFileFor(dbPath).writeAsStringSync(stamp, flush: true);
    } catch (_) {
      // A missing stamp only costs a rebuild.
    }
  }

  bool _needsRebuild(String dbPath, String sourcePath) {
    if (!File(dbPath).existsSync()) return true;
    try {
      final stamp = _stampFileFor(dbPath);
      if (!stamp.existsSync()) return true;
      final lines = const LineSplitter().convert(stamp.readAsStringSync());
      if (lines.length < 2) return true;
      final source = File(sourcePath);
      return lines[0] != source.lastModifiedSync().toUtc().toIso8601String() ||
          lines[1] != source.absolute.path;
    } catch (_) {
      return true;
    }
  }

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

  /// Stable, collision-free cache key for this installation. Stripping
  /// non-alphanumerics alone would map `/opt/a-b` and `/opt/ab` onto each other.
  String _installKey() {
    final name = _installation.name;
    if (name == 'user' || name == 'system') return name;
    return 'at_${_fnv1a64(name).toRadixString(16).padLeft(16, '0')}';
  }

  /// FNV-1a, 64-bit. Only needs to separate distinct installation paths, so a
  /// non-cryptographic hash avoids pulling in a dependency for a cache key.
  static int _fnv1a64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    return hash;
  }

  static String _slug(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  // ── Installed-app icons (pure Dart) ──────────────────────────────────────

  /// Absolute path to the best on-disk icon for the installed [app], or `null`.
  String? installedIconPathFor(FlatpakApplication app) =>
      resolveInstalledIconPath(app.installedPath, app.ref.name);

  /// Absolute path to the best on-disk icon for installed [appId], or `null`.
  ///
  /// Enumerates the installation to find the app's deploy directory. Resolving
  /// icons for more than one app should use [installedIconPaths], which walks
  /// the installation once; prefer [installedIconPathFor] when the
  /// [FlatpakApplication] is already in hand.
  Future<String?> installedIconPath(String appId) async {
    final paths = await installedIconPaths([appId]);
    return paths[appId];
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
