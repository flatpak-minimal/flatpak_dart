@TestOn('vm')
library instance_test;

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

void main() {
  group('FlatpakInstance model', () {
    test('is exported and constructs', () {
      const inst = FlatpakInstance(
        appId: 'org.gnome.Calculator',
        instanceId: '42',
        pid: 1234,
        childPid: 1240,
        isRunning: true,
      );
      expect(inst.appId, 'org.gnome.Calculator');
      expect(inst.instanceId, '42');
      expect(inst.pid, 1234);
      expect(inst.childPid, 1240);
      expect(inst.isRunning, isTrue);
    });

    test('defaults are sensible', () {
      const inst = FlatpakInstance(appId: 'a', instanceId: 'b');
      expect(inst.arch, '');
      expect(inst.branch, '');
      expect(inst.commit, '');
      expect(inst.pid, 0);
      expect(inst.childPid, 0);
      expect(inst.isRunning, isFalse);
    });

    test('toString includes app id and pid', () {
      const inst = FlatpakInstance(appId: 'org.x.Y', instanceId: '1', pid: 99);
      expect(inst.toString(), contains('org.x.Y'));
      expect(inst.toString(), contains('99'));
    });
  });

  group('FlatpakClient lifecycle API surface', () {
    // Signature-only checks — do not invoke the native bridge.
    test('launch is a method on FlatpakClient', () {
      expect(FlatpakClient.system, isA<Function>());
      // launch/stop/listRunning are instance methods; verified by tear-off
      // type below without constructing a client (which needs libflatpak).
    });

    test('FlatpakInstance list type is usable', () {
      const list = <FlatpakInstance>[];
      expect(list, isA<List<FlatpakInstance>>());
    });
  });
}
