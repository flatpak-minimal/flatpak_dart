@TestOn('vm')
library;

import 'package:dbus/dbus.dart';
import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

/// Records calls and returns scripted replies / errors.
class FakeStore {
  final calls = <({String member, List<DBusValue> values})>[];
  final Map<String, List<DBusValue>> replies = {};
  final Map<String, DBusMethodErrorResponse> errors = {};

  Future<List<DBusValue>> call(
    String member,
    List<DBusValue> values, {
    required DBusSignature replySignature,
  }) async {
    calls.add((member: member, values: values));
    final err = errors[member];
    if (err != null) throw DBusMethodResponseException(err);
    return replies[member] ?? const [];
  }
}

DBusArray _as(List<String> v) => DBusArray.string(v);

void main() {
  group('PermissionStatus', () {
    test('maps raw values', () {
      expect(PermissionStatus.fromValue('yes'), PermissionStatus.granted);
      expect(PermissionStatus.fromValue('no'), PermissionStatus.denied);
      expect(PermissionStatus.fromValue('ask'), PermissionStatus.ask);
      expect(PermissionStatus.fromValue('xyz'), PermissionStatus.notSet);
      expect(PermissionStatus.fromValue(null), PermissionStatus.notSet);
    });

    test('first permission decides status', () {
      expect(PermissionStatus.fromPermissions([]), PermissionStatus.notSet);
      expect(
        PermissionStatus.fromPermissions(['yes']),
        PermissionStatus.granted,
      );
    });

    test('value round-trips', () {
      expect(PermissionStatus.granted.value, 'yes');
      expect(PermissionStatus.notSet.value, isNull);
    });
  });

  group('permissionTarget', () {
    test('maps well-known permissions', () {
      expect(permissionTarget('location', 'a').table, PermissionTable.location);
      expect(permissionTarget('notifications', 'a').id, 'notifications');
      expect(permissionTarget('background', 'org.x').id, 'org.x');
      final cam = permissionTarget('camera', 'a');
      expect(cam.table, PermissionTable.devices);
      expect(cam.id, 'camera');
    });
  });

  group('PermissionStorePortal', () {
    late FakeStore fake;
    late PermissionStorePortal portal;

    setUp(() {
      fake = FakeStore();
      portal = PermissionStorePortal.withCall(fake.call);
    });

    test('get decodes a granted permission', () async {
      fake.replies['GetPermission'] = [
        _as(['yes']),
      ];
      expect(
        await portal.get('devices', 'camera', 'org.x'),
        PermissionStatus.granted,
      );
      final c = fake.calls.single;
      expect(c.member, 'GetPermission');
      expect((c.values[0] as DBusString).value, 'devices');
      expect((c.values[2] as DBusString).value, 'org.x');
    });

    test('get treats NotFound as notSet', () async {
      fake.errors['GetPermission'] = DBusMethodErrorResponse(
        'org.freedesktop.portal.Error.NotFound',
      );
      expect(
        await portal.get('devices', 'camera', 'org.x'),
        PermissionStatus.notSet,
      );
    });

    test('set sends create flag and permission list', () async {
      await portal.set('devices', 'camera', 'org.x', ['yes']);
      final c = fake.calls.single;
      expect(c.member, 'SetPermission');
      expect((c.values[1] as DBusBoolean).value, isTrue);
      expect(
        (c.values[4] as DBusArray).children
            .map((e) => (e as DBusString).value)
            .toList(),
        ['yes'],
      );
    });

    test('setStatus notSet sends an empty list', () async {
      await portal.setStatus(
        'devices',
        'camera',
        'org.x',
        PermissionStatus.notSet,
      );
      final c = fake.calls.single;
      expect((c.values[4] as DBusArray).children, isEmpty);
    });

    test('lookup decodes a{sas}', () async {
      fake.replies['Lookup'] = [
        DBusDict(DBusSignature('s'), DBusSignature('as'), {
          const DBusString('org.x'): _as(['yes']),
          const DBusString('org.y'): _as(['ask']),
        }),
        const DBusVariant(DBusString('')),
      ];
      final m = await portal.lookup('devices', 'camera');
      expect(m['org.x'], ['yes']);
      expect(m['org.y'], ['ask']);
    });

    test('lookup NotFound returns empty map', () async {
      fake.errors['Lookup'] = DBusMethodErrorResponse(
        'org.freedesktop.impl.portal.Error',
        [const DBusString('No entry for table')],
      );
      expect(await portal.lookup('devices', 'camera'), isEmpty);
    });

    test('list decodes ids', () async {
      fake.replies['List'] = [
        _as(['camera', 'microphone']),
      ];
      expect(await portal.list('devices'), ['camera', 'microphone']);
    });

    // Verified against xdg-permission-store: a missing resource answers
    // org.freedesktop.portal.Error.NotFound with "No entry for <id>".
    test('the real portal not-found shape reads as notSet', () async {
      fake.errors['GetPermission'] = DBusMethodErrorResponse(
        'org.freedesktop.portal.Error.NotFound',
        [const DBusString('No entry for no.such.resource')],
      );
      expect(
        await portal.get('devices', 'no.such.resource', 'org.x'),
        PermissionStatus.notSet,
      );
    });

    // A backend that fails for a real reason must not be read as "nothing is
    // stored" — that would prompt, or write, over a slate that is not clean.
    test('a generic failure mentioning "not found" still propagates', () async {
      fake.errors['GetPermission'] = DBusMethodErrorResponse(
        'org.freedesktop.DBus.Error.Failed',
        [const DBusString('permission database not found or corrupt')],
      );
      await expectLater(
        portal.get('devices', 'camera', 'org.x'),
        throwsA(isA<DBusMethodResponseException>()),
      );
    });

    test('UnknownMethod propagates instead of reading as notSet', () async {
      fake.errors['GetPermission'] = DBusMethodErrorResponse(
        'org.freedesktop.DBus.Error.UnknownMethod',
        [const DBusString('No such method')],
      );
      await expectLater(
        portal.get('devices', 'camera', 'org.x'),
        throwsA(isA<DBusMethodResponseException>()),
      );
    });

    test('delete swallows NotFound', () async {
      fake.errors['DeletePermission'] = DBusMethodErrorResponse(
        'org.freedesktop.portal.Error.NotFound',
      );
      await portal.delete('devices', 'camera', 'org.x'); // no throw
      expect(fake.calls.single.member, 'DeletePermission');
    });

    test('check resolves each permission via lookup', () async {
      fake.replies['Lookup'] = [
        DBusDict(DBusSignature('s'), DBusSignature('as'), {
          const DBusString('org.x'): _as(['yes']),
        }),
        const DBusVariant(DBusString('')),
      ];
      final r = await portal.check('org.x', ['camera', 'location']);
      expect(r['camera'], PermissionStatus.granted);
      expect(r['location'], PermissionStatus.granted);
      // camera → devices/camera, location → location/location
      expect(
        fake.calls.map((c) => (c.values[0] as DBusString).value).toList(),
        ['devices', 'location'],
      );
    });

    test('setResource writes the whole app→permissions map', () async {
      await portal.setResource('devices', 'camera', {
        'org.x': ['yes'],
        'org.y': ['no'],
      }, data: 'note');
      final c = fake.calls.single;
      expect(c.member, 'Set');
      expect((c.values[0] as DBusString).value, 'devices');
      expect((c.values[1] as DBusBoolean).value, isTrue);
      expect((c.values[2] as DBusString).value, 'camera');
      final dict = c.values[3] as DBusDict;
      expect(dict.children, hasLength(2));
      expect(
        ((dict.children[const DBusString('org.x')]) as DBusArray).children.map(
          (e) => (e as DBusString).value,
        ),
        ['yes'],
      );
      expect(((c.values[4] as DBusVariant).value as DBusString).value, 'note');
    });

    test('setResource passes create=false through', () async {
      await portal.setResource('devices', 'camera', const {}, create: false);
      expect((fake.calls.single.values[1] as DBusBoolean).value, isFalse);
    });

    test('setValue stores opaque resource data', () async {
      await portal.setValue('devices', 'camera', 'blob');
      final c = fake.calls.single;
      expect(c.member, 'SetValue');
      expect((c.values[2] as DBusString).value, 'camera');
      expect(((c.values[3] as DBusVariant).value as DBusString).value, 'blob');
    });

    test('deleteResource removes a whole resource', () async {
      await portal.deleteResource('devices', 'camera');
      final c = fake.calls.single;
      expect(c.member, 'Delete');
      expect((c.values[1] as DBusString).value, 'camera');
    });

    test('deleteResource swallows NotFound', () async {
      fake.errors['Delete'] = DBusMethodErrorResponse(
        'org.freedesktop.portal.Error.NotFound',
        [const DBusString('No entry for camera')],
      );
      await portal.deleteResource('devices', 'camera'); // no throw
    });

    test('deleteResource propagates a real failure', () async {
      fake.errors['Delete'] = DBusMethodErrorResponse(
        'org.freedesktop.DBus.Error.AccessDenied',
      );
      await expectLater(
        portal.deleteResource('devices', 'camera'),
        throwsA(isA<DBusMethodResponseException>()),
      );
    });

    test('list NotFound returns empty rather than throwing', () async {
      fake.errors['List'] = DBusMethodErrorResponse(
        'org.freedesktop.portal.Error.NotFound',
        [const DBusString('No entry for devices')],
      );
      expect(await portal.list('devices'), isEmpty);
    });

    // Every device permission lives in one table, so resolving several must
    // not cost one round trip each.
    test('check reuses one lookup per resource', () async {
      fake.replies['Lookup'] = [
        DBusDict(DBusSignature('s'), DBusSignature('as'), {
          const DBusString('org.x'): _as(['yes']),
        }),
        const DBusVariant(DBusString('')),
      ];
      await portal.check('org.x', ['camera', 'microphone', 'speakers']);
      // camera/microphone/speakers all map to devices/<perm>, so three
      // distinct resources — but each is looked up exactly once.
      expect(fake.calls.where((c) => c.member == 'Lookup'), hasLength(3));
    });

    test('check reports an app with no stored entry as notSet', () async {
      fake.replies['Lookup'] = [
        DBusDict(DBusSignature('s'), DBusSignature('as'), {
          const DBusString('org.other'): _as(['yes']),
        }),
        const DBusVariant(DBusString('')),
      ];
      final r = await portal.check('org.x', ['camera']);
      expect(r['camera'], PermissionStatus.notSet);
    });

    test('removeAllForApp deletes fixed tables plus device ids', () async {
      fake.replies['List'] = [
        _as(['camera', 'microphone']),
      ];
      await portal.removeAllForApp('org.x');
      final deletes = fake.calls.where((c) => c.member == 'DeletePermission');
      // notifications, location, background, + 2 devices = 5
      expect(deletes.length, 5);
      expect(deletes.map((c) => (c.values[0] as DBusString).value).toSet(), {
        'notifications',
        'location',
        'background',
        'devices',
      });
    });
  });
}
