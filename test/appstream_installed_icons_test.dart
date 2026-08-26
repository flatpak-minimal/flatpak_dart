@TestOn('vm')
library;

import 'dart:io';

import 'package:flatpak_dart/src/application.dart';
import 'package:flatpak_dart/src/appstream/catalog.dart';
import 'package:flatpak_dart/src/exceptions.dart';
import 'package:flatpak_dart/src/installation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Stands in for the native-backed installation.
///
/// `noSuchMethod` covers the rest of the surface: anything [FlatpakAppStream]
/// reaches for that is not stubbed here throws instead of silently answering
/// null, so a test cannot pass by accident.
class _FakeInstallation implements FlatpakInstallation {
  _FakeInstallation({this.apps = const [], this.missing = const {}});

  final List<FlatpakApplication> apps;

  /// App ids that report as not installed.
  final Set<String> missing;

  int getAppInfoCalls = 0;
  int listApplicationsCalls = 0;

  @override
  String get name => 'user';

  @override
  Future<FlatpakApplication> getAppInfo(
    String appId, {
    String arch = '',
    String branch = '',
  }) async {
    getAppInfoCalls++;
    if (missing.contains(appId)) {
      throw FlatpakNotFoundException('$appId is not installed');
    }
    return apps.firstWhere(
      (a) => a.ref.name == appId,
      orElse: () => throw FlatpakNotFoundException('$appId is not installed'),
    );
  }

  @override
  Future<List<FlatpakApplication>> listApplications({
    bool includeRuntimes = false,
  }) async {
    listApplicationsCalls++;
    return apps;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected call: ${invocation.memberName}');
}

FlatpakApplication _app(String id, String deployDir) => FlatpakApplication(
  ref: FlatpakRef(kind: 'app', name: id, arch: 'x86_64', branch: 'stable'),
  origin: 'flathub',
  installedPath: deployDir,
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fp_icons_'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Creates a deploy dir for [id] carrying a 128x128 hicolor icon.
  String deployWithIcon(String id) {
    final dir = p.join(root.path, id);
    final icon = File(
      p.join(dir, 'files/share/icons/hicolor/128x128/apps/$id.png'),
    );
    icon.parent.createSync(recursive: true);
    icon.writeAsBytesSync(const [0]);
    return dir;
  }

  /// Creates a deploy dir for [id] with no icon in it at all.
  String deployWithoutIcon(String id) {
    final dir = p.join(root.path, id);
    Directory(p.join(dir, 'files/share')).createSync(recursive: true);
    return dir;
  }

  group('installedIconPath', () {
    test('resolves the icon for an installed app', () async {
      final dir = deployWithIcon('org.gnome.Chess');
      final appStream = FlatpakAppStream(
        _FakeInstallation(apps: [_app('org.gnome.Chess', dir)]),
        root.path,
      );

      final icon = await appStream.installedIconPath('org.gnome.Chess');
      expect(icon, isNotNull);
      expect(icon, endsWith('128x128/apps/org.gnome.Chess.png'));
    });

    // The reason this path exists: looking one app up must not walk every
    // installed app to find it.
    test('does not enumerate the installation', () async {
      final fake = _FakeInstallation(
        apps: [_app('org.gnome.Chess', deployWithIcon('org.gnome.Chess'))],
      );
      final appStream = FlatpakAppStream(fake, root.path);

      await appStream.installedIconPath('org.gnome.Chess');
      expect(fake.getAppInfoCalls, 1);
      expect(fake.listApplicationsCalls, 0);
    });

    // Not installed is an ordinary answer here, not an error to propagate:
    // callers render a placeholder.
    test('a missing app is null, not a thrown exception', () async {
      final appStream = FlatpakAppStream(
        _FakeInstallation(missing: {'org.not.Installed'}),
        root.path,
      );
      expect(await appStream.installedIconPath('org.not.Installed'), isNull);
    });

    test('an installed app that ships no icon is null', () async {
      final dir = deployWithoutIcon('org.bare.App');
      final appStream = FlatpakAppStream(
        _FakeInstallation(apps: [_app('org.bare.App', dir)]),
        root.path,
      );
      expect(await appStream.installedIconPath('org.bare.App'), isNull);
    });

    test('an app with an empty deploy path is null', () async {
      final appStream = FlatpakAppStream(
        _FakeInstallation(apps: [_app('org.odd.App', '')]),
        root.path,
      );
      expect(await appStream.installedIconPath('org.odd.App'), isNull);
    });
  });

  group('installedIconPaths', () {
    test('resolves several apps from one enumeration', () async {
      final fake = _FakeInstallation(
        apps: [
          _app('org.a.A', deployWithIcon('org.a.A')),
          _app('org.b.B', deployWithIcon('org.b.B')),
          _app('org.c.C', deployWithIcon('org.c.C')),
        ],
      );
      final appStream = FlatpakAppStream(fake, root.path);

      final icons = await appStream.installedIconPaths(['org.a.A', 'org.c.C']);
      expect(icons.keys, unorderedEquals(['org.a.A', 'org.c.C']));
      expect(icons['org.a.A'], contains('org.a.A'));
      // One walk for the whole batch, not one per app.
      expect(fake.listApplicationsCalls, 1);
    });

    test('apps that are not installed are absent from the result', () async {
      final fake = _FakeInstallation(
        apps: [_app('org.a.A', deployWithIcon('org.a.A'))],
      );
      final appStream = FlatpakAppStream(fake, root.path);

      final icons = await appStream.installedIconPaths([
        'org.a.A',
        'org.not.Here',
      ]);
      expect(icons.keys, ['org.a.A']);
    });

    test('apps with no icon are absent from the result', () async {
      final fake = _FakeInstallation(
        apps: [
          _app('org.a.A', deployWithIcon('org.a.A')),
          _app('org.bare.App', deployWithoutIcon('org.bare.App')),
        ],
      );
      final appStream = FlatpakAppStream(fake, root.path);

      final icons = await appStream.installedIconPaths([
        'org.a.A',
        'org.bare.App',
      ]);
      expect(icons.keys, ['org.a.A']);
    });

    test('an empty request does no work at all', () async {
      final fake = _FakeInstallation();
      final appStream = FlatpakAppStream(fake, root.path);

      expect(await appStream.installedIconPaths(const []), isEmpty);
      expect(fake.listApplicationsCalls, 0);
    });
  });

  group('installedIconPathFor', () {
    test('uses the app already in hand without any lookup', () async {
      final fake = _FakeInstallation();
      final appStream = FlatpakAppStream(fake, root.path);
      final app = _app('org.gnome.Chess', deployWithIcon('org.gnome.Chess'));

      expect(
        appStream.installedIconPathFor(app),
        endsWith('128x128/apps/org.gnome.Chess.png'),
      );
      expect(fake.getAppInfoCalls, 0);
      expect(fake.listApplicationsCalls, 0);
    });
  });
}
