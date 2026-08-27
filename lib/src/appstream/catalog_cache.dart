// Cache-key derivation and staleness detection for parsed AppStream catalogs.
//
// Pure functions of their arguments — no open databases, no cache root — so the
// rule that decides whether a catalog gets re-parsed can be tested directly.
// Getting it wrong is silent: the wrong answer is a stale catalog served as if
// it were current.

import 'dart:convert';
import 'dart:io';

/// Cache key identifying one parsed catalog.
///
/// [installationName] is `user`, `system`, or the absolute path an installation
/// was opened at. Empty [arch]/[language] mean "whatever the catalog defaults
/// to", which is a distinct cache entry from any named one.
///
/// The "unspecified" markers are spelled so that no named value can produce
/// them: a named arch always carries the `arch.` prefix, so an arch literally
/// called `default` cannot land on the same entry as "the default arch". The
/// same holds for `src` and a language actually named `src`.
String catalogCacheKey({
  required String installationName,
  required String remote,
  String arch = '',
  String language = '',
}) {
  final install = _installKey(installationName);
  final archPart = arch.isEmpty ? 'anyarch' : 'arch.${slugForCache(arch)}';
  final langPart = language.isEmpty
      ? 'srclang'
      : 'lang.${slugForCache(language)}';
  return '${install}_${slugForCache(remote)}_${archPart}_$langPart';
}

/// Stable, collision-free key fragment for an installation. Stripping
/// non-alphanumerics alone would map `/opt/a-b` and `/opt/ab` onto each other.
String _installKey(String name) {
  if (name == 'user' || name == 'system') return name;
  return 'at_${fnv1a64(name).toRadixString(16).padLeft(16, '0')}';
}

/// FNV-1a, 64-bit. Only needs to separate distinct installation paths, so a
/// non-cryptographic hash avoids pulling in a dependency for a cache key.
int fnv1a64(String value) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  return hash;
}

/// Reduces [value] to characters that are safe in a filename.
String slugForCache(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/// Sidecar recording which source a database at [dbPath] was built from.
File catalogStampFile(String dbPath) => File('$dbPath.source');

/// Records the source identity the database at [dbPath] was built from.
///
/// The mtime is stored rather than compared: a catalog that moves *backwards*
/// in time has to invalidate too. Flatpak swaps the `active` symlink between
/// deploy directories, so a newly activated catalog's mtime is not guaranteed
/// to be newer than the database built from the one it replaced.
///
/// The path is stored **resolved**, and that is what makes the mtime
/// survivable. Flatpak's `appstream2` deploy checks the catalog out of OSTree,
/// which normalises mtimes to the epoch: on two machines the uncompressed
/// `appstream.xml` under `active/` was dated 1970 while only the sibling
/// `.gz` carried a real time. With an unresolved path both halves of the
/// identity would then be invariant — same 1970, same `.../active/...` string
/// — and the catalog would read as current forever, however often it was
/// refreshed. The resolved path carries the OSTree commit, which changes
/// exactly when the deploy does.
void stampCatalogSource(String dbPath, String sourcePath) {
  try {
    final source = File(sourcePath);
    final stamp =
        '${source.lastModifiedSync().toUtc().toIso8601String()}\n'
        '${_sourceIdentity(source)}\n';
    catalogStampFile(dbPath).writeAsStringSync(stamp, flush: true);
  } catch (_) {
    // A missing stamp only costs a rebuild.
  }
}

/// Path identifying the file a catalog was built from, with symlinks resolved
/// so an `active` symlink repointed at a new deploy reads as a different
/// source. Falls back to the unresolved path when resolution fails, which only
/// costs a rebuild.
String _sourceIdentity(File source) {
  try {
    return source.resolveSymbolicLinksSync();
  } catch (_) {
    return source.absolute.path;
  }
}

/// Whether the database at [dbPath] has to be rebuilt from [sourcePath].
///
/// True whenever the answer is not a confident "no": no database, no stamp, a
/// truncated stamp, a source that has changed mtime or identity, or any error
/// reading either. Rebuilding needlessly costs time; skipping a needed rebuild
/// serves stale data.
bool catalogNeedsRebuild(String dbPath, String sourcePath) {
  if (!File(dbPath).existsSync()) return true;
  try {
    final stamp = catalogStampFile(dbPath);
    if (!stamp.existsSync()) return true;
    final lines = const LineSplitter().convert(stamp.readAsStringSync());
    if (lines.length < 2) return true;
    final source = File(sourcePath);
    return lines[0] != source.lastModifiedSync().toUtc().toIso8601String() ||
        lines[1] != _sourceIdentity(source);
  } catch (_) {
    return true;
  }
}
