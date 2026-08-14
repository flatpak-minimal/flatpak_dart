@TestOn('vm')
library;

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionProgress', () {
    test('progressLabel shows bytes-only when sizeKnown is false', () {
      const p = TransactionProgress(
        op: 'install',
        ref: 'app/org.gnome.Calculator/x86_64/stable',
        progressPercent: 0,
        bytesTransferred: 10 * 1024 * 1024,
        bytesTotal: 0,
        status: 'Downloading',
      );
      expect(p.sizeKnown, isFalse);
      expect(p.progressLabel, contains('%'));
      expect(p.progressLabel, contains('transferred'));
    });

    test('progressLabel shows percent when sizeKnown is true', () {
      const p = TransactionProgress(
        op: 'install',
        ref: 'app/org.gnome.Calculator/x86_64/stable',
        progressPercent: 45,
        bytesTransferred: 32 * 1024 * 1024,
        bytesTotal: 71 * 1024 * 1024,
        status: 'Downloading',
      );
      expect(p.sizeKnown, isTrue);
      expect(p.progressLabel, startsWith('45%'));
    });

    test('progressLabel formats GiB correctly', () {
      const p = TransactionProgress(
        op: 'install',
        ref: 'app/org.example.Large/x86_64/stable',
        progressPercent: 50,
        bytesTransferred: 2 * 1024 * 1024 * 1024,
        bytesTotal: 4 * 1024 * 1024 * 1024,
        status: 'Downloading',
      );
      expect(p.progressLabel, contains('GiB'));
    });

    test('progressLabel formats KiB for small values', () {
      const p = TransactionProgress(
        op: 'install',
        ref: 'app/org.example.Tiny/x86_64/stable',
        progressPercent: 0,
        bytesTransferred: 512 * 1024,
        bytesTotal: 0,
        status: 'Downloading',
      );
      expect(p.progressLabel, contains('KiB'));
    });

    test('toString includes op and ref name', () {
      const p = TransactionProgress(
        op: 'update',
        ref: 'app/org.gnome.Calculator/x86_64/stable',
        progressPercent: 80,
        bytesTransferred: 50 * 1024 * 1024,
        bytesTotal: 71 * 1024 * 1024,
        status: 'Downloading',
      );
      expect(p.toString(), contains('update'));
      expect(p.toString(), contains('Calculator'));
    });

    test('sizeKnown is false when bytesTotal is 0', () {
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

    test('sizeKnown is true when bytesTotal > 0', () {
      const p = TransactionProgress(
        op: 'install',
        ref: '',
        progressPercent: 0,
        bytesTransferred: 0,
        bytesTotal: 1,
        status: '',
      );
      expect(p.sizeKnown, isTrue);
    });
  });

  group('FlatpakTransactionException', () {
    test('isAlreadyRunning matches lock-contention message', () {
      const e = FlatpakTransactionException('error: already running', ref: '');
      expect(e.isAlreadyRunning, isTrue);
    });

    test('isAlreadyRunning matches FLATPAK_ERROR_ALREADY_RUNNING', () {
      const e = FlatpakTransactionException(
        'FLATPAK_ERROR_ALREADY_RUNNING',
        ref: '',
      );
      expect(e.isAlreadyRunning, isTrue);
    });

    test('isAlreadyRunning false for other messages', () {
      const e = FlatpakTransactionException('network error', ref: '');
      expect(e.isAlreadyRunning, isFalse);
    });

    test('isCancelled matches cancellation message', () {
      const e = FlatpakTransactionException('Operation was cancelled', ref: '');
      expect(e.isCancelled, isTrue);
    });

    test('isCancelled false for other messages', () {
      const e = FlatpakTransactionException('some other error', ref: '');
      expect(e.isCancelled, isFalse);
    });

    test('toString includes type name and message', () {
      const e = FlatpakTransactionException('test error', ref: 'app/x');
      expect(e.toString(), contains('FlatpakTransactionException'));
      expect(e.toString(), contains('test error'));
    });
  });

  group('FlatpakException hierarchy', () {
    test('FlatpakPermissionException is a FlatpakException', () {
      const e = FlatpakPermissionException('denied');
      expect(e, isA<FlatpakException>());
      expect(e.message, 'denied');
    });

    test('FlatpakServiceUnavailableException is a FlatpakException', () {
      const e = FlatpakServiceUnavailableException('no agent');
      expect(e, isA<FlatpakException>());
    });

    test('FlatpakNotFoundException is a FlatpakException', () {
      const e = FlatpakNotFoundException('not found');
      expect(e, isA<FlatpakException>());
    });

    test('FlatpakRemoteException is a FlatpakException', () {
      const e = FlatpakRemoteException('remote error');
      expect(e, isA<FlatpakException>());
    });
  });
}
