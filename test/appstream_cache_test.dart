@TestOn('vm')
library;

import 'dart:io';

import 'package:flatpak_dart/src/appstream/catalog_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('catalogCacheKey', () {
    test('well-known installations keep their own names', () {
      expect(
        catalogCacheKey(installationName: 'user', remote: 'flathub'),
        startsWith('user_'),
      );
      expect(
        catalogCacheKey(installationName: 'system', remote: 'flathub'),
        startsWith('system_'),
      );
    });

    test('a path installation is hashed, not embedded', () {
      final key = catalogCacheKey(
        installationName: '/opt/custom',
        remote: 'flathub',
      );
      expect(key, startsWith('at_'));
      expect(key, isNot(contains('opt')));
    });

    // The reason the path is hashed rather than slugged: stripping
    // non-alphanumerics alone maps these two onto the same key, and one
    // installation would then serve the other's catalog.
    test('paths that slug identically still get distinct keys', () {
      expect(
        catalogCacheKey(installationName: '/opt/a-b', remote: 'flathub'),
        isNot(catalogCacheKey(installationName: '/opt/ab', remote: 'flathub')),
      );
    });

    test('arch and language partition the cache', () {
      final base = catalogCacheKey(installationName: 'user', remote: 'flathub');
      final arch = catalogCacheKey(
        installationName: 'user',
        remote: 'flathub',
        arch: 'aarch64',
      );
      final lang = catalogCacheKey(
        installationName: 'user',
        remote: 'flathub',
        language: 'de',
      );
      expect({base, arch, lang}, hasLength(3));
    });

    // Empty means "whatever the catalog defaults to", which is not the same
    // entry as an arch or language that happens to be spelled like the marker
    // for it — otherwise the two would silently share one database.
    test('defaults are their own entries, not aliases', () {
      final anyArch = catalogCacheKey(
        installationName: 'user',
        remote: 'flathub',
      );
      expect(
        anyArch,
        isNot(
          catalogCacheKey(
            installationName: 'user',
            remote: 'flathub',
            arch: 'default',
          ),
        ),
      );
      expect(
        anyArch,
        isNot(
          catalogCacheKey(
            installationName: 'user',
            remote: 'flathub',
            arch: 'anyarch',
          ),
        ),
      );
      expect(
        anyArch,
        isNot(
          catalogCacheKey(
            installationName: 'user',
            remote: 'flathub',
            language: 'srclang',
          ),
        ),
      );
    });

    test('remotes partition the cache', () {
      expect(
        catalogCacheKey(installationName: 'user', remote: 'flathub'),
        isNot(
          catalogCacheKey(installationName: 'user', remote: 'flathub-beta'),
        ),
      );
    });

    test('is stable across calls', () {
      expect(
        catalogCacheKey(installationName: 'user', remote: 'flathub'),
        catalogCacheKey(installationName: 'user', remote: 'flathub'),
      );
    });

    // The key becomes a filename, so nothing in it may escape the cache dir.
    test('produces a filename-safe key even from hostile input', () {
      final key = catalogCacheKey(
        installationName: 'user',
        remote: '../../etc/passwd',
        arch: 'a/b',
      );
      expect(key, isNot(contains('/')));
      expect(
        key,
        isNot(
          contains(
            '..'
            '/',
          ),
        ),
      );
      expect(p.basename(key), key);
    });
  });

  group('slugForCache', () {
    test('keeps safe characters', () {
      expect(slugForCache('flathub-beta_1.2'), 'flathub-beta_1.2');
    });

    test('replaces separators', () {
      expect(slugForCache('a/b'), 'a_b');
      expect(slugForCache('a b'), 'a_b');
    });
  });

  group('fnv1a64', () {
    test('differs for inputs that differ only in punctuation', () {
      expect(fnv1a64('/opt/a-b'), isNot(fnv1a64('/opt/ab')));
    });

    test('is deterministic', () {
      expect(fnv1a64('/opt/custom'), fnv1a64('/opt/custom'));
    });
  });

  group('catalogNeedsRebuild', () {
    late Directory dir;
    late String dbPath;
    late String sourcePath;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fp_cache_');
      dbPath = p.join(dir.path, 'catalog.sqlite');
      sourcePath = p.join(dir.path, 'appstream.xml');
      File(sourcePath).writeAsStringSync('<components/>');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    void buildDb() {
      File(dbPath).writeAsStringSync('pretend sqlite');
      stampCatalogSource(dbPath, sourcePath);
    }

    test('no database means rebuild', () {
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);
    });

    test('a freshly stamped database is current', () {
      buildDb();
      expect(catalogNeedsRebuild(dbPath, sourcePath), isFalse);
    });

    test('a database with no stamp means rebuild', () {
      File(dbPath).writeAsStringSync('pretend sqlite');
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);
    });

    test('a truncated stamp means rebuild', () {
      buildDb();
      catalogStampFile(dbPath).writeAsStringSync('only-one-line\n');
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);
    });

    test('an empty stamp means rebuild', () {
      buildDb();
      catalogStampFile(dbPath).writeAsStringSync('');
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);
    });

    test('a newer source means rebuild', () {
      buildDb();
      File(
        sourcePath,
      ).setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);
    });

    // The case a plain "is the source newer than the db?" test would miss.
    // Flatpak swaps the `active` symlink between deploy directories, so the
    // newly activated catalog can be *older* than the database built from the
    // one it replaced — and that database is still stale.
    test('an older source means rebuild too', () {
      buildDb();
      File(
        sourcePath,
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);
    });

    // Same mtime, different file: `active` now points somewhere else.
    test('a different source path at the same mtime means rebuild', () {
      buildDb();
      final other = p.join(dir.path, 'other.xml');
      File(other).writeAsStringSync('<components/>');
      File(other).setLastModifiedSync(File(sourcePath).lastModifiedSync());
      expect(catalogNeedsRebuild(dbPath, other), isTrue);
    });

    test('a vanished source means rebuild rather than throwing', () {
      buildDb();
      File(sourcePath).deleteSync();
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);
    });

    test('re-stamping after a source change makes it current again', () {
      buildDb();
      File(
        sourcePath,
      ).writeAsStringSync('<components><component/></components>');
      File(
        sourcePath,
      ).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
      expect(catalogNeedsRebuild(dbPath, sourcePath), isTrue);

      stampCatalogSource(dbPath, sourcePath);
      expect(catalogNeedsRebuild(dbPath, sourcePath), isFalse);
    });

    test('stamping a source that does not exist is survivable', () {
      File(dbPath).writeAsStringSync('pretend sqlite');
      stampCatalogSource(dbPath, p.join(dir.path, 'missing.xml'));
      // No stamp written, so the answer is the safe one.
      expect(
        catalogNeedsRebuild(dbPath, p.join(dir.path, 'missing.xml')),
        isTrue,
      );
    });

    // Reproduces flatpak's appstream2 deploy exactly: the catalog is an OSTree
    // checkout, so its mtime is normalised to the epoch and is identical
    // before and after an update, and it is reached through an `active`
    // symlink whose own path never changes. Both halves of a naive identity
    // are invariant, and the database would read as current forever.
    //
    // Observed on two machines: the uncompressed appstream.xml under active/
    // was dated 1970 on both an x86_64 host and an aarch64 Raspberry Pi.
    group('an OSTree-style active symlink', () {
      late String activeLink;
      late String source;

      setUp(() {
        for (final commit in ['commit-old', 'commit-new']) {
          final f = File(p.join(dir.path, commit, 'appstream.xml'));
          f.parent.createSync(recursive: true);
          f.writeAsStringSync('<components origin="$commit"/>');
          // OSTree normalises checked-out mtimes to the epoch.
          f.setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(0));
        }
        activeLink = p.join(dir.path, 'active');
        Link(activeLink).createSync(p.join(dir.path, 'commit-old'));
        source = p.join(activeLink, 'appstream.xml');
      });

      test('a database built from it is current while unchanged', () {
        File(dbPath).writeAsStringSync('pretend sqlite');
        stampCatalogSource(dbPath, source);
        expect(catalogNeedsRebuild(dbPath, source), isFalse);
      });

      test('repointing the symlink invalidates despite equal mtimes', () {
        File(dbPath).writeAsStringSync('pretend sqlite');
        stampCatalogSource(dbPath, source);
        expect(catalogNeedsRebuild(dbPath, source), isFalse);

        // flatpak swaps the deploy; mtime and the `active/...` path string are
        // both unchanged.
        Link(activeLink).updateSync(p.join(dir.path, 'commit-new'));
        expect(
          File(source).lastModifiedSync().millisecondsSinceEpoch,
          0,
          reason: 'the mtime must still be the epoch for this to be a test',
        );
        expect(catalogNeedsRebuild(dbPath, source), isTrue);
      });

      test('re-stamping after the swap makes it current again', () {
        File(dbPath).writeAsStringSync('pretend sqlite');
        stampCatalogSource(dbPath, source);
        Link(activeLink).updateSync(p.join(dir.path, 'commit-new'));
        expect(catalogNeedsRebuild(dbPath, source), isTrue);
        stampCatalogSource(dbPath, source);
        expect(catalogNeedsRebuild(dbPath, source), isFalse);
      });

      test('the stamp records the resolved commit, not the symlink', () {
        File(dbPath).writeAsStringSync('pretend sqlite');
        stampCatalogSource(dbPath, source);
        final stamp = catalogStampFile(dbPath).readAsStringSync();
        expect(stamp, contains('commit-old'));
        expect(stamp, isNot(contains('active')));
      });
    });

    test('the stamp sits beside the database', () {
      expect(catalogStampFile(dbPath).path, '$dbPath.source');
    });
  });
}
