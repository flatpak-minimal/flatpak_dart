// Flatpak-specific glue over the appstream_dart engine: locate a remote's
// downloaded catalog, trigger a refresh, resolve installed-app icons, and
// delegate parsing/querying to appstream_dart.

import 'dart:async';
import 'dart:io';

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
    final host = _hostFlatpakArch();
    if (host != null && arches.contains(host)) return host;
    return arches.first;
  }

  static String? _hostFlatpakArch() {
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
  }

  // ── Catalog refresh ──────────────────────────────────────────────────────

  /// Refresh [remote]'s AppStream catalog (native `update_appstream_sync`).
  /// Empty [arch] refreshes the default architecture.
  Future<void> refresh(String remote, {String arch = ''}) =>
      _installation.refreshAppstream(remote, arch: arch);

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
    final remotes = remote.isNotEmpty
        ? [remote]
        : (await _installation.listRemotes()).map((r) => r.name);

    for (final r in remotes) {
      final db = await _openCatalog(r, arch: arch, language: language);
      if (db == null) continue;
      try {
        final detail = await db.getComponentDetail(appId);
        if (detail != null) return detail;
      } finally {
        await db.close();
      }
    }
    return null;
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

    _ensureInitialized();

    final cacheDir = Directory(
      p.join(Directory.systemTemp.path, 'flatpak_dart_appstream'),
    )..createSync(recursive: true);
    final key =
        '${_installKey()}_${remote}_${arch.isEmpty ? 'default' : arch}'
        '_${language.isEmpty ? 'src' : language}';
    final dbPath = p.join(cacheDir.path, '$key.sqlite');

    if (_needsRebuild(dbPath, xmlOrGz)) {
      final xmlPath = await _materializeXml(
        xmlOrGz,
        p.join(cacheDir.path, '$key.xml'),
      );
      final dbFile = File(dbPath);
      if (dbFile.existsSync()) dbFile.deleteSync();
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
    }

    return CatalogDatabase.open(dbPath);
  }

  /// Ensure a plain XML file exists at [xmlDest], decompressing the source when
  /// it is gzip-compressed. Returns the path to the usable XML.
  Future<String> _materializeXml(String source, String xmlDest) async {
    if (!source.endsWith('.gz')) return source;
    final bytes = await File(source).readAsBytes();
    final decoded = gzip.decode(bytes);
    await File(xmlDest).writeAsBytes(decoded, flush: true);
    return xmlDest;
  }

  bool _needsRebuild(String dbPath, String sourcePath) {
    final db = File(dbPath);
    if (!db.existsSync()) return true;
    try {
      return File(sourcePath).lastModifiedSync().isAfter(db.lastModifiedSync());
    } catch (_) {
      return true;
    }
  }

  String _installKey() => _installation.name
      .replaceAll('/', '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');

  // ── Installed-app icons (pure Dart) ──────────────────────────────────────

  /// Absolute path to the best on-disk icon for the installed [app], or `null`.
  String? installedIconPathFor(FlatpakApplication app) =>
      resolveInstalledIconPath(app.installedPath, app.ref.name);

  /// Absolute path to the best on-disk icon for installed [appId], or `null`.
  /// Looks the app up in the installation to find its deploy directory.
  Future<String?> installedIconPath(String appId) async {
    final apps = await _installation.listApplications();
    for (final a in apps) {
      if (a.ref.name == appId) {
        return resolveInstalledIconPath(a.installedPath, appId);
      }
    }
    return null;
  }
}
