@TestOn('vm')
library;

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flatpak_dart/src/installation_paths.dart';
import 'package:test/test.dart';

void main() {
  group('installationPathFor', () {
    test('system resolves to the well-known root', () {
      expect(installationPathFor('system'), '/var/lib/flatpak');
    });

    test('user follows XDG_DATA_HOME when set', () {
      // Not settable from Dart, so assert the shape both branches produce
      // rather than the branch this process happens to take.
      expect(installationPathFor('user'), endsWith('/flatpak'));
      expect(installationPathFor('user'), startsWith('/'));
    });

    test('anything else is taken as an absolute path', () {
      expect(installationPathFor('/opt/custom'), '/opt/custom');
    });

    // The hash-free reason the two callers share this: /opt/a-b and /opt/ab
    // must not collapse onto one another.
    test('distinct paths stay distinct', () {
      expect(
        installationPathFor('/opt/a-b'),
        isNot(installationPathFor('/opt/ab')),
      );
    });
  });

  group('parseDfOutput', () {
    // Captured verbatim from `df -B1 --output=size,avail /var/lib/flatpak` on
    // GNU coreutils 9.x: a right-aligned header line, then figures in bytes.
    const real =
        '    1B-blocks        Avail\n'
        '1998694907904 730189029376\n';

    test('parses real df output', () {
      final info = parseDfOutput(real);
      expect(info.totalBytes, 1998694907904);
      expect(info.availableBytes, 730189029376);
      expect(info.usedBytes, 1998694907904 - 730189029376);
    });

    test('ignores trailing blank lines', () {
      final info = parseDfOutput('$real\n\n');
      expect(info.totalBytes, 1998694907904);
    });

    test('reports a zero-length filesystem rather than dividing by it', () {
      final info = parseDfOutput('size avail\n0 0\n');
      expect(info.totalBytes, 0);
      expect(info.availableBytes, 0);
      expect(info.usedBytes, 0);
    });

    // A df without GNU --output, or a locale rendering figures differently,
    // must surface as the library's own exception — not a bare FormatException
    // that a caller catching FlatpakException would miss.
    test('header only is a remote exception', () {
      expect(
        () => parseDfOutput('size avail\n'),
        throwsA(isA<FlatpakRemoteException>()),
      );
    });

    test('empty output is a remote exception', () {
      expect(() => parseDfOutput(''), throwsA(isA<FlatpakRemoteException>()));
    });

    test('a one-column row is a remote exception', () {
      expect(
        () => parseDfOutput('size avail\n12345\n'),
        throwsA(isA<FlatpakRemoteException>()),
      );
    });

    test(
      'non-numeric figures are a remote exception, not a FormatException',
      () {
        expect(
          () => parseDfOutput('size avail\n1,2G 3,4G\n'),
          throwsA(isA<FlatpakRemoteException>()),
        );
      },
    );

    test('the message names the context it was given', () {
      expect(
        () => parseDfOutput('', context: 'df /opt/custom'),
        throwsA(
          isA<FlatpakRemoteException>().having(
            (e) => e.message,
            'message',
            contains('/opt/custom'),
          ),
        ),
      );
    });
  });

  group('StorageInfo', () {
    test('usedBytes is total minus available', () {
      const info = StorageInfo(totalBytes: 100, availableBytes: 40);
      expect(info.usedBytes, 60);
    });

    test('toString carries both figures', () {
      const info = StorageInfo(totalBytes: 100, availableBytes: 40);
      expect(info.toString(), contains('100'));
      expect(info.toString(), contains('40'));
    });
  });
}
