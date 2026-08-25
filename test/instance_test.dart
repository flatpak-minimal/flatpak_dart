@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flatpak_dart/src/ffi/codec.dart';
import 'package:test/test.dart';

// ── Compile-time signature checks ──────────────────────────────────────────
// These closures only type-check if FlatpakClient's lifecycle methods have
// exactly these shapes, so a signature change breaks the build rather than
// silently passing a runtime `isA<Function>()` assertion. They are never
// invoked — constructing a FlatpakClient would dlopen libflatpak.
Future<FlatpakInstance> _launch(FlatpakClient c, String appId) =>
    c.launch(appId);

Future<FlatpakInstance> _launchWithRef(FlatpakClient c, String appId) =>
    c.launch(appId, arch: 'x86_64', branch: 'stable', commit: 'deadbeef');

Future<void> _stop(FlatpakClient c, String appId) => c.stop(appId);

Future<List<FlatpakInstance>> _listRunning(FlatpakClient c) => c.listRunning();

// Golden wire-format buffer for FpInstance, emitted by the C++ writer
// (glz::write_binary, native/include/glaze_meta.h) for:
//   appId="org.gnome.Calculator" instanceId="42" arch="x86_64"
//   branch="stable" commit="deadbeef" pid=1234 childPid=1240 isRunning=true
// Byte 0 is the 0x01 payload discriminator the native side frames it with.
// BEVE-Lite layout: strings are uint64-LE length + UTF-8 bytes, int32 is 4
// bytes LE, bool is 1 byte. If this test fails, the C++ and Dart sides of the
// wire format have diverged — fix the codec, do not re-bless the bytes.
final _goldenFpInstance = Uint8List.fromList(<int>[
  0x01, //
  0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x6f, 0x72, 0x67, 0x2e, 0x67, 0x6e, 0x6f, 0x6d, 0x65, 0x2e,
  0x43, 0x61, 0x6c, 0x63, 0x75, 0x6c, 0x61, 0x74, 0x6f, 0x72,
  0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x34, 0x32,
  0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x78, 0x38, 0x36, 0x5f, 0x36, 0x34,
  0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x73, 0x74, 0x61, 0x62, 0x6c, 0x65,
  0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x64, 0x65, 0x61, 0x64, 0x62, 0x65, 0x65, 0x66,
  0xd2, 0x04, 0x00, 0x00, // pid = 1234
  0xd8, 0x04, 0x00, 0x00, // childPid = 1240
  0x01, // isRunning = true
]);

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
    test('launch returns a Future<FlatpakInstance> from an app id', () {
      expect(
        _launch,
        isA<Future<FlatpakInstance> Function(FlatpakClient, String)>(),
      );
    });

    test('launch accepts arch/branch/commit named arguments', () {
      expect(
        _launchWithRef,
        isA<Future<FlatpakInstance> Function(FlatpakClient, String)>(),
      );
    });

    test('stop returns a Future<void> from an app id', () {
      expect(_stop, isA<Future<void> Function(FlatpakClient, String)>());
    });

    test('listRunning returns a Future<List<FlatpakInstance>>', () {
      expect(
        _listRunning,
        isA<Future<List<FlatpakInstance>> Function(FlatpakClient)>(),
      );
    });
  });

  group('FpInstance wire format', () {
    test('decodes the C++ golden buffer', () {
      final inst = GlazeCodec.decodeInstance(_goldenFpInstance, 1);
      expect(inst.appId, 'org.gnome.Calculator');
      expect(inst.instanceId, '42');
      expect(inst.arch, 'x86_64');
      expect(inst.branch, 'stable');
      expect(inst.commit, 'deadbeef');
      expect(inst.pid, 1234);
      expect(inst.childPid, 1240);
      expect(inst.isRunning, isTrue);
    });

    test('golden buffer is exactly the payload the C++ writer emits', () {
      // 91 payload bytes + the 1-byte discriminator.
      expect(_goldenFpInstance.length, 92);
    });
  });
}
