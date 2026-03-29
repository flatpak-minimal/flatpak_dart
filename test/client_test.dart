@TestOn('vm')
library client_test;

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

void main() {
  group('FlatpakClient API surface', () {
    // These tests verify the public API exists and has correct signatures.
    // They do NOT call the native bridge (that requires libflatpak).

    test('FlatpakClient.system factory exists', () {
      // Just verify the type — don't call it (requires native lib)
      expect(FlatpakClient.system, isA<Function>());
    });

    test('FlatpakClient.user factory exists', () {
      expect(FlatpakClient.user, isA<Function>());
    });

    test('FlatpakClient.at factory exists', () {
      expect(FlatpakClient.at, isA<Function>());
    });
  });

  group('Barrel export completeness', () {
    test('FlatpakApplication is exported', () {
      const app = FlatpakApplication(
        ref: FlatpakRef(kind: 'app', name: 'test'),
        origin: 'flathub',
      );
      expect(app.ref.name, 'test');
    });

    test('FlatpakRef is exported', () {
      const ref = FlatpakRef(kind: 'app', name: 'org.test.App');
      expect(ref.kind, 'app');
    });

    test('FlatpakRemote is exported', () {
      const r = FlatpakRemote(
        name: 'test',
        url: 'https://example.com',
        title: 'Test',
      );
      expect(r.name, 'test');
    });

    test('RemoteSubset is exported', () {
      expect(RemoteSubset.verified.apiValue, 'verified');
    });

    test('RemoteType is exported', () {
      expect(RemoteType.static_, isNotNull);
    });

    test('FlatpakRemoteConfig is exported', () {
      const cfg = FlatpakRemoteConfig(url: 'https://example.com');
      expect(cfg.url, 'https://example.com');
    });

    test('KnownRemotes is exported', () {
      expect(KnownRemotes.flathub.url, isNotEmpty);
    });

    test('FlatpakPermission is exported', () {
      const p = FlatpakPermission(section: 'test', key: 'key', value: 'val');
      expect(p.section, 'test');
    });

    test('TransactionProgress is exported', () {
      const p = TransactionProgress(
        op: 'install',
        ref: '',
        progressPercent: 0,
        bytesTransferred: 0,
        bytesTotal: 0,
        status: '',
      );
      expect(p.sizeKnown, isFalse);
    });

    test('UpdateAvailableEvent is exported', () {
      const e = UpdateAvailableEvent();
      expect(e, isA<UpdateAvailableEvent>());
    });

    test('Exception types are exported', () {
      expect(const FlatpakPermissionException('x'), isA<FlatpakException>());
      expect(
        const FlatpakServiceUnavailableException('x'),
        isA<FlatpakException>(),
      );
      expect(
        const FlatpakTransactionException('x', ref: ''),
        isA<FlatpakException>(),
      );
      expect(const FlatpakNotFoundException('x'), isA<FlatpakException>());
      expect(const FlatpakRemoteException('x'), isA<FlatpakException>());
    });
  });
}
