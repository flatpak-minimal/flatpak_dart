@TestOn('vm')
library;

import 'dart:io';

import 'package:flatpak_dart/src/appstream/installed_icons.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolveInstalledIconPath', () {
    late Directory deploy;

    setUp(() => deploy = Directory.systemTemp.createTempSync('fp_icon_'));
    tearDown(() => deploy.deleteSync(recursive: true));

    void touch(String relative) {
      final f = File(p.join(deploy.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(const [0]);
    }

    test('returns null for empty deploy dir', () {
      expect(resolveInstalledIconPath('', 'org.gnome.Chess'), isNull);
    });

    test('returns null when no icon exists', () {
      expect(resolveInstalledIconPath(deploy.path, 'org.gnome.Chess'), isNull);
    });

    test('finds a hicolor png', () {
      touch('files/share/icons/hicolor/128x128/apps/org.gnome.Chess.png');
      final got = resolveInstalledIconPath(deploy.path, 'org.gnome.Chess');
      expect(got, endsWith('128x128/apps/org.gnome.Chess.png'));
    });

    test('prefers the largest available size', () {
      touch('files/share/icons/hicolor/48x48/apps/org.gnome.Chess.png');
      touch('files/share/icons/hicolor/256x256/apps/org.gnome.Chess.png');
      final got = resolveInstalledIconPath(deploy.path, 'org.gnome.Chess');
      expect(got, contains('256x256'));
    });

    test('finds a scalable svg', () {
      touch('files/share/icons/hicolor/scalable/apps/org.gnome.Chess.svg');
      final got = resolveInstalledIconPath(deploy.path, 'org.gnome.Chess');
      expect(got, endsWith('scalable/apps/org.gnome.Chess.svg'));
    });

    test('prefers a scalable svg over any raster size', () {
      touch('files/share/icons/hicolor/16x16/apps/org.gnome.Chess.png');
      touch('files/share/icons/hicolor/scalable/apps/org.gnome.Chess.svg');
      final got = resolveInstalledIconPath(deploy.path, 'org.gnome.Chess');
      expect(got, endsWith('scalable/apps/org.gnome.Chess.svg'));
    });

    test('falls back to the app-info icon cache', () {
      touch('files/share/app-info/icons/flatpak/128x128/org.gnome.Chess.png');
      final got = resolveInstalledIconPath(deploy.path, 'org.gnome.Chess');
      expect(
        got,
        endsWith('app-info/icons/flatpak/128x128/org.gnome.Chess.png'),
      );
    });
  });
}
