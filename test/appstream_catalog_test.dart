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
  });
}
