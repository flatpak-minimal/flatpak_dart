@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flatpak_dart/src/ffi/codec.dart';
import 'package:test/test.dart';

// Golden wire-format buffers for the structs added alongside the system
// introspection and permissions readers, emitted by the C++ writer
// (glz::write_binary, native/include/glaze_meta.h) and captured verbatim.
//
// Nothing on the wire carries a field name: the schema *is* the field order in
// the glz::meta<T> specialization in native/include/flatpak_types.h. Reordering
// either side without the other produces a silent mis-decode — strings shifting
// into the wrong slots, or an int32 read out of a bool. These buffers are what
// catches that.
//
// BEVE-Lite layout: strings are uint64-LE length + UTF-8 bytes, int32 is 4
// bytes LE, bool is 1 byte. Byte 0 is the 0x01 payload discriminator the native
// side frames the struct with, so every decode starts at offset 1.
//
// If one of these fails, the C++ and Dart sides have diverged — fix the codec,
// do not re-bless the bytes.

final _goldenFpInstallationInfo = Uint8List.fromList(<int>[
  0x01, // frame discriminator
  // id = "default"
  0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x65,
  0x66, 0x61, 0x75, 0x6c, 0x74,
  // displayName = "Default system installation"
  0x1b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x44, 0x65,
  0x66, 0x61, 0x75, 0x6c, 0x74, 0x20, 0x73, 0x79, 0x73, 0x74,
  0x65, 0x6d, 0x20, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x6c, 0x6c,
  0x61, 0x74, 0x69, 0x6f, 0x6e,
  // path = "/var/lib/flatpak"
  0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2f, 0x76,
  0x61, 0x72, 0x2f, 0x6c, 0x69, 0x62, 0x2f, 0x66, 0x6c, 0x61,
  0x74, 0x70, 0x61, 0x6b,
  // isUser = false
  0x00,
  // priority = 7
  0x07, 0x00, 0x00, 0x00,
]);

final _goldenFpMetadataEntry = Uint8List.fromList(<int>[
  0x01, // frame discriminator
  // section = "Session Bus Policy"
  0x12, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x53, 0x65,
  0x73, 0x73, 0x69, 0x6f, 0x6e, 0x20, 0x42, 0x75, 0x73, 0x20,
  0x50, 0x6f, 0x6c, 0x69, 0x63, 0x79,
  // key = "org.freedesktop.Notifications"
  0x1d, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6f, 0x72,
  0x67, 0x2e, 0x66, 0x72, 0x65, 0x65, 0x64, 0x65, 0x73, 0x6b,
  0x74, 0x6f, 0x70, 0x2e, 0x4e, 0x6f, 0x74, 0x69, 0x66, 0x69,
  0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x73,
  // value = "talk"
  0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x74, 0x61,
  0x6c, 0x6b,
]);

void main() {
  group('FpInstallationInfo wire format', () {
    test('decodes the C++ golden buffer', () {
      final info = GlazeCodec.decodeInstallationInfo(
        _goldenFpInstallationInfo,
        1,
      );
      expect(info.id, 'default');
      expect(info.displayName, 'Default system installation');
      expect(info.path, '/var/lib/flatpak');
      expect(info.isUser, isFalse);
      expect(info.priority, 7);
    });

    test('golden buffer is exactly the payload the C++ writer emits', () {
      // 79 payload bytes + the 1-byte discriminator.
      expect(_goldenFpInstallationInfo.length, 80);
    });
  });

  group('FpMetadataEntry wire format', () {
    test('decodes the C++ golden buffer', () {
      final entry = GlazeCodec.decodeMetadataEntry(_goldenFpMetadataEntry, 1);
      expect(entry.section, 'Session Bus Policy');
      expect(entry.key, 'org.freedesktop.Notifications');
      expect(entry.value, 'talk');
    });

    test('golden buffer is exactly the payload the C++ writer emits', () {
      // 75 payload bytes + the 1-byte discriminator.
      expect(_goldenFpMetadataEntry.length, 76);
    });

    test('decoded entries feed derivePermissions', () {
      // The whole point of the metadata reader: what get_permissions() posts
      // is what the launch-permission derivation consumes.
      final entry = GlazeCodec.decodeMetadataEntry(_goldenFpMetadataEntry, 1);
      expect(derivePermissions([entry]), ['notifications']);
    });
  });

  group('LaunchWithPermissionsResult', () {
    const instance = FlatpakInstance(appId: 'org.x.Y', instanceId: '1');

    test('separates denials from undecided permissions', () {
      const result = LaunchWithPermissionsResult(
        instance: instance,
        permissions: {
          'camera': PermissionStatus.granted,
          'location': PermissionStatus.denied,
          'notifications': PermissionStatus.ask,
          'usb': PermissionStatus.notSet,
        },
      );
      expect(result.denied, ['location']);
      // ask and notSet are both "nobody answered", not "no".
      expect(result.unresolved, ['notifications', 'usb']);
    });

    test('all granted leaves both lists empty', () {
      const result = LaunchWithPermissionsResult(
        instance: instance,
        permissions: {'camera': PermissionStatus.granted},
      );
      expect(result.denied, isEmpty);
      expect(result.unresolved, isEmpty);
    });

    test('an app declaring nothing resolves to nothing', () {
      const result = LaunchWithPermissionsResult(
        instance: instance,
        permissions: {},
      );
      expect(result.denied, isEmpty);
      expect(result.unresolved, isEmpty);
      expect(result.instance.appId, 'org.x.Y');
    });
  });

  group('FlatpakInstallationInfo model', () {
    test('defaults are sensible', () {
      const info = FlatpakInstallationInfo(id: 'default');
      expect(info.displayName, '');
      expect(info.path, '');
      expect(info.isUser, isFalse);
      expect(info.priority, 0);
    });

    test('toString includes id, path and isUser', () {
      const info = FlatpakInstallationInfo(
        id: 'default',
        path: '/var/lib/flatpak',
        isUser: true,
      );
      expect(info.toString(), contains('default'));
      expect(info.toString(), contains('/var/lib/flatpak'));
      expect(info.toString(), contains('isUser=true'));
    });
  });
}
