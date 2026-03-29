@TestOn('vm')
library installation_test;

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

void main() {
  group('FlatpakRef', () {
    test('toString formats as kind/name/arch/branch', () {
      const ref = FlatpakRef(
        kind: 'app',
        name: 'org.gnome.Calculator',
        arch: 'x86_64',
        branch: 'stable',
      );
      expect(ref.toString(), 'app/org.gnome.Calculator/x86_64/stable');
    });
  });

  group('FlatpakApplication', () {
    test('toString includes key fields', () {
      const app = FlatpakApplication(
        ref: FlatpakRef(
          kind: 'app',
          name: 'org.gnome.Calculator',
          arch: 'x86_64',
          branch: 'stable',
        ),
        origin: 'flathub',
        installedSize: 52428800,
      );
      expect(app.toString(), contains('org.gnome.Calculator'));
      expect(app.toString(), contains('flathub'));
    });
  });

  group('RemoteSubset', () {
    test('apiValue returns correct strings', () {
      expect(RemoteSubset.none.apiValue, '');
      expect(RemoteSubset.verified.apiValue, 'verified');
      expect(RemoteSubset.floss.apiValue, 'floss');
      expect(RemoteSubset.verifiedFloss.apiValue, 'verified_floss');
    });

    test('fromApiValue roundtrips', () {
      for (final s in RemoteSubset.values) {
        expect(RemoteSubset.fromApiValue(s.apiValue), s);
      }
    });

    test('fromApiValue returns none for unknown', () {
      expect(RemoteSubset.fromApiValue('bogus'), RemoteSubset.none);
    });
  });

  group('FlatpakRemote', () {
    test('isStatic returns true for static_ type', () {
      const r = FlatpakRemote(
        name: 'fedora',
        url: 'oci+https://registry.fedoraproject.org',
        title: 'Fedora',
        remoteType: RemoteType.static_,
      );
      expect(r.isStatic, isTrue);
    });

    test('isStatic returns false for user type', () {
      const r = FlatpakRemote(
        name: 'flathub',
        url: 'https://dl.flathub.org/repo/flathub.flatpakrepo',
        title: 'Flathub',
        remoteType: RemoteType.user,
      );
      expect(r.isStatic, isFalse);
    });

    test('toString includes subset when set', () {
      const r = FlatpakRemote(
        name: 'flathub-floss',
        url: 'https://dl.flathub.org/repo/flathub.flatpakrepo',
        title: 'Flathub FLOSS',
        subset: RemoteSubset.floss,
      );
      expect(r.toString(), contains('subset=floss'));
    });
  });

  group('FlatpakRemoteConfig', () {
    test('fromFlatpakrepoFile creates correct type', () {
      final cfg =
          FlatpakRemoteConfig.fromFlatpakrepoFile('/tmp/test.flatpakrepo');
      // The config should be usable (not throw)
      expect(cfg.url, isNull);
    });
  });

  group('FlatpakPermission', () {
    test('toString formats correctly', () {
      const p = FlatpakPermission(
        section: 'filesystems',
        key: 'host',
        value: 'read-write',
      );
      expect(p.toString(), 'FlatpakPermission(filesystems.host=read-write)');
    });
  });
}
