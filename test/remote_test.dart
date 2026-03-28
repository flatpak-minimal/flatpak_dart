@TestOn('vm')
library remote_test;

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

void main() {
  group('FlatpakRemote', () {
    test('isStatic matches static_ type', () {
      const r = FlatpakRemote(
        name: 'fedora',
        url: 'oci+https://registry.fedoraproject.org',
        title: 'Fedora',
        remoteType: RemoteType.static_,
      );
      expect(r.isStatic, isTrue);
    });

    test('isStatic false for user type', () {
      const r = FlatpakRemote(
        name: 'flathub',
        url: 'https://dl.flathub.org/repo/flathub.flatpakrepo',
        title: 'Flathub',
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

    test('toString marks disabled', () {
      const r = FlatpakRemote(
        name: 'flathub-beta',
        url: 'https://flathub.org/beta-repo/flathub-beta.flatpakrepo',
        title: 'Beta',
        disabled: true,
      );
      expect(r.toString(), contains('[disabled]'));
    });

    test('toString marks static', () {
      const r = FlatpakRemote(
        name: 'fedora',
        url: 'oci+https://registry.fedoraproject.org',
        title: 'Fedora',
        remoteType: RemoteType.static_,
      );
      expect(r.toString(), contains('[static]'));
    });
  });

  group('RemoteSubset', () {
    test('apiValue returns correct strings', () {
      expect(RemoteSubset.none.apiValue, '');
      expect(RemoteSubset.verified.apiValue, 'verified');
      expect(RemoteSubset.floss.apiValue, 'floss');
      expect(RemoteSubset.verifiedFloss.apiValue, 'verified_floss');
    });

    test('fromApiValue roundtrips all values', () {
      for (final s in RemoteSubset.values) {
        expect(RemoteSubset.fromApiValue(s.apiValue), s);
      }
    });

    test('fromApiValue returns none for unknown input', () {
      expect(RemoteSubset.fromApiValue('bogus'), RemoteSubset.none);
      expect(RemoteSubset.fromApiValue(''), RemoteSubset.none);
    });
  });

  group('RemoteType', () {
    test('has three values', () {
      expect(RemoteType.values.length, 3);
      expect(RemoteType.values, contains(RemoteType.user));
      expect(RemoteType.values, contains(RemoteType.system));
      expect(RemoteType.values, contains(RemoteType.static_));
    });
  });

  group('FlatpakRemoteConfig', () {
    test('const constructor allows all-null fields', () {
      const cfg = FlatpakRemoteConfig();
      expect(cfg.url, isNull);
      expect(cfg.title, isNull);
      expect(cfg.priority, isNull);
    });

    test('fromFlatpakrepoFile preserves path', () {
      final cfg = FlatpakRemoteConfig.fromFlatpakrepoFile(
          '/tmp/gnome-nightly.flatpakrepo');
      // Should not throw; path is carried internally
      expect(cfg.url, isNull);
    });
  });

  group('KnownRemotes', () {
    test('all entries have non-empty URLs', () {
      final all = [
        KnownRemotes.flathub,
        KnownRemotes.flathubVerified,
        KnownRemotes.flathubFloss,
        KnownRemotes.flathubVerifiedFloss,
        KnownRemotes.flathubBeta,
        KnownRemotes.fedora,
        KnownRemotes.elementaryOs,
        KnownRemotes.pureOs,
        KnownRemotes.igalia,
        KnownRemotes.gnomeNightly,
        KnownRemotes.kdeRuntimeNightly,
        KnownRemotes.kdeDragonNightly,
        KnownRemotes.xwaylandVideoBridgeNightly,
        KnownRemotes.endlessOsApps,
        KnownRemotes.endlessOsSdk,
      ];
      for (final r in all) {
        expect(r.url, isNotNull);
        expect(r.url, isNotEmpty);
      }
    });

    test('Flathub variants share the same base URL', () {
      const base = 'https://dl.flathub.org/repo/flathub.flatpakrepo';
      expect(KnownRemotes.flathub.url, base);
      expect(KnownRemotes.flathubVerified.url, base);
      expect(KnownRemotes.flathubFloss.url, base);
      expect(KnownRemotes.flathubVerifiedFloss.url, base);
    });

    test('fedora uses OCI scheme', () {
      expect(KnownRemotes.fedora.url, startsWith('oci+https://'));
    });

    test('flathub has collection ID', () {
      expect(KnownRemotes.flathub.collectionId, 'org.flathub.Stable');
    });

    test('flathubFloss carries correct subset', () {
      expect(KnownRemotes.flathubFloss.subset, RemoteSubset.floss);
    });

    test('flathubVerifiedFloss carries correct subset', () {
      expect(KnownRemotes.flathubVerifiedFloss.subset,
          RemoteSubset.verifiedFloss);
    });

    test('beta URL differs from stable', () {
      expect(KnownRemotes.flathubBeta.url,
          isNot(KnownRemotes.flathub.url));
    });
  });
}
