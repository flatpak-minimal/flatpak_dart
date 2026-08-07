@TestOn('vm')
library portal_permission_store_test;

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
          DBusString('org.x'): _as(['yes']),
          DBusString('org.y'): _as(['ask']),
        }),
        DBusVariant(DBusString('')),
      ];
      final m = await portal.lookup('devices', 'camera');
      expect(m['org.x'], ['yes']);
      expect(m['org.y'], ['ask']);
    });

    test('lookup NotFound returns empty map', () async {
      fake.errors['Lookup'] = DBusMethodErrorResponse(
        'org.freedesktop.impl.portal.Error',
        [DBusString('No entry for table')],
      );
      expect(await portal.lookup('devices', 'camera'), isEmpty);
    });

    test('list decodes ids', () async {
      fake.replies['List'] = [
        _as(['camera', 'microphone']),
      ];
      expect(await portal.list('devices'), ['camera', 'microphone']);
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
          DBusString('org.x'): _as(['yes']),
        }),
        DBusVariant(DBusString('')),
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
