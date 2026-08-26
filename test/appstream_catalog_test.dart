@TestOn('vm')
library;

import 'dart:io';

import 'package:flatpak_dart/src/appstream/catalog.dart';
import 'package:flatpak_dart/src/arch.dart';
import 'package:flatpak_dart/src/installation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // The tests run on whatever machine CI gives them, so they assert against
  // the host's own architecture rather than hard-coding one.
  final hostArch = hostFlatpakArch!;

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

    test('auto-selects the host arch when none is given', () {
      writeCatalog('flathub', hostArch, 'appstream.xml');
      expect(appStream.catalogPath('flathub'), contains('/$hostArch/'));
    });

    // With several downloaded, the host's own wins — and it is not the
    // alphabetically first.
    test('prefers the host arch over the first sorted one', () {
      for (final arch in {'aarch64', 'i386', 'x86_64', hostArch}) {
        writeCatalog('flathub', arch, 'appstream.xml');
      }
      expect(appStream.catalogPath('flathub'), contains('/$hostArch/'));
    });

    // The whole point of the filter. A catalog for an architecture this
    // machine cannot execute is not a fallback — offering it would list apps
    // that cannot be installed, let alone run.
    test('a foreign-arch catalog is not offered', () {
      writeCatalog('flathub', 'mips64el', 'appstream.xml');
      writeCatalog('flathub', 's390x', 'appstream.xml');
      expect(appStream.catalogPath('flathub'), isNull);
    });

    test('native policy refuses even a compatible arch', () {
      final native = FlatpakAppStream(
        FlatpakInstallation('user'),
        base.path,
        archPolicy: ArchPolicy.native,
      );
      // i386 runs natively on x86_64, so `compatible` accepts it...
      writeCatalog('flathub', 'i386', 'appstream.xml');
      if (hostArch == 'x86_64') {
        expect(appStream.catalogPath('flathub'), contains('/i386/'));
        expect(native.catalogPath('flathub'), isNull);
      }
    });

    // The positive case of the whole feature: an architecture is offered only
    // when the kernel can execute it *and* a catalog for it exists. Detection
    // is injected so this does not depend on the test machine having qemu.
    test(
      'emulated offers a foreign arch that is both runnable and present',
      () {
        writeCatalog('flathub', 'aarch64', 'appstream.xml');
        final emulated = FlatpakAppStream(
          FlatpakInstallation('user'),
          base.path,
          archPolicy: ArchPolicy.emulated,
          executableArches: const {'aarch64'},
        );
        expect(emulated.usableArches('flathub'), ['aarch64']);
        expect(emulated.catalogPath('flathub'), contains('/aarch64/'));
      },
    );

    test('emulated still refuses an arch the kernel cannot execute', () {
      writeCatalog('flathub', 'aarch64', 'appstream.xml');
      final noQemu = FlatpakAppStream(
        FlatpakInstallation('user'),
        base.path,
        archPolicy: ArchPolicy.emulated,
        executableArches: const {},
      );
      expect(noQemu.usableArches('flathub'), isEmpty);
      expect(noQemu.catalogPath('flathub'), isNull);
    });

    // Native always wins: an emulated build must never be chosen over one the
    // machine runs directly.
    test('a native catalog outranks an emulated one', () {
      writeCatalog('flathub', hostArch, 'appstream.xml');
      writeCatalog('flathub', 'aarch64', 'appstream.xml');
      final emulated = FlatpakAppStream(
        FlatpakInstallation('user'),
        base.path,
        archPolicy: ArchPolicy.emulated,
        executableArches: const {'aarch64'},
      );
      expect(emulated.usableArches('flathub').first, hostArch);
      expect(emulated.catalogPath('flathub'), contains('/$hostArch/'));
    });

    test('usableArches reports only what is both allowed and downloaded', () {
      writeCatalog('flathub', hostArch, 'appstream.xml');
      writeCatalog('flathub', 's390x', 'appstream.xml');
      expect(appStream.usableArches('flathub'), [hostArch]);
      expect(
        appStream.downloadedArches('flathub'),
        containsAll([hostArch, 's390x']),
      );
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
