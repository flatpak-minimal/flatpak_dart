@TestOn('vm')
library;

import 'dart:io';

import 'package:flatpak_dart/src/appstream/catalog.dart';
import 'package:flatpak_dart/src/installation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FlatpakAppStream.catalogPath', () {
    late Directory base;
    late FlatpakAppStream appStream;

    setUp(() {
      base = Directory.systemTemp.createTempSync('fp_catalog_');
      // catalogPath is a pure filesystem lookup; the reader handle is lazy.
      appStream = FlatpakAppStream(FlatpakInstallation('user'), base.path);
    });
    tearDown(() => base.deleteSync(recursive: true));

    void writeCatalog(String remote, String arch, String file) {
      final f = File(
        p.join(base.path, 'appstream', remote, arch, 'active', file),
      );
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(const [0]);
    }

    // Two deploy layouts occur in the wild: flatpak's appstream2 deploy uses
    // an `active` symlink to the current commit, while the older appstream
    // deploy writes straight into the arch directory. Observed together on one
    // host — Flathub on the former, the Fedora remote on the latter.
    void writeFlatCatalog(String remote, String arch, String file) {
      final f = File(p.join(base.path, 'appstream', remote, arch, file));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(const [0]);
    }

    test('finds a catalog laid out without an active directory', () {
      writeFlatCatalog('fedora', 'x86_64', 'appstream.xml.gz');
      expect(
        appStream.catalogPath('fedora', arch: 'x86_64'),
        endsWith('appstream/fedora/x86_64/appstream.xml.gz'),
      );
    });

    test('finds a flat-layout catalog with no arch given', () {
      writeFlatCatalog('fedora', 'x86_64', 'appstream.xml.gz');
      expect(appStream.catalogPath('fedora'), isNotNull);
    });

    // active/ is the current deploy; a stale sibling left in the arch
    // directory must not win over it.
    test('prefers the active deploy over a flat sibling', () {
      writeFlatCatalog('flathub', 'x86_64', 'appstream.xml');
      writeCatalog('flathub', 'x86_64', 'appstream.xml');
      expect(
        appStream.catalogPath('flathub', arch: 'x86_64'),
        contains('/active/'),
      );
    });

    test('returns null when nothing is downloaded', () {
      expect(appStream.catalogPath('flathub'), isNull);
    });

    test('locates the catalog for an explicit arch', () {
      writeCatalog('flathub', 'x86_64', 'appstream.xml.gz');
      final got = appStream.catalogPath('flathub', arch: 'x86_64');
      expect(got, endsWith('flathub/x86_64/active/appstream.xml.gz'));
    });

    test('prefers uncompressed xml over gz', () {
      writeCatalog('flathub', 'x86_64', 'appstream.xml.gz');
      writeCatalog('flathub', 'x86_64', 'appstream.xml');
      final got = appStream.catalogPath('flathub', arch: 'x86_64');
      expect(got, endsWith('active/appstream.xml'));
    });

    test('auto-selects an arch when none is given', () {
      writeCatalog('flathub', 'aarch64', 'appstream.xml');
      final got = appStream.catalogPath('flathub');
      expect(got, isNotNull);
      expect(got, contains('aarch64'));
    });

    // With several arches downloaded, the host's own is the one that can
    // actually be installed — and it is not the alphabetically first.
    test('prefers the host arch over the first sorted one', () {
      for (final arch in const ['aarch64', 'i386', 'x86_64']) {
        writeCatalog('flathub', arch, 'appstream.xml');
      }
      final host = Process.runSync('uname', ['-m']).stdout.toString().trim();
      final expected =
          const {'arm64': 'aarch64', 'armv7l': 'arm', 'i686': 'i386'}[host] ??
          host;

      final got = appStream.catalogPath('flathub');
      expect(got, isNotNull);
      if (const ['aarch64', 'i386', 'x86_64'].contains(expected)) {
        expect(got, contains('/$expected/'));
      } else {
        // Host arch not among the downloaded ones: fall back to first sorted.
        expect(got, contains('/aarch64/'));
      }
    });

    test('falls back to the first sorted arch when the host has none', () {
      writeCatalog('flathub', 'mips64el', 'appstream.xml');
      writeCatalog('flathub', 'riscv64', 'appstream.xml');
      expect(appStream.catalogPath('flathub'), contains('/mips64el/'));
    });

    test('an explicit arch with no catalog is null, not another arch', () {
      writeCatalog('flathub', 'x86_64', 'appstream.xml');
      expect(appStream.catalogPath('flathub', arch: 'aarch64'), isNull);
    });

    test('an unknown remote is null', () {
      writeCatalog('flathub', 'x86_64', 'appstream.xml');
      expect(appStream.catalogPath('no-such-remote'), isNull);
    });

    test('a remote directory with no arch subdirectories is null', () {
      Directory(
        p.join(base.path, 'appstream', 'empty'),
      ).createSync(recursive: true);
      expect(appStream.catalogPath('empty'), isNull);
    });
  });
}
