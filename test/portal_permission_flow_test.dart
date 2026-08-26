@TestOn('vm')
library;

import 'package:dbus/dbus.dart';
import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

/// Minimal scripted PermissionStore transport (shared style with the store test).
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

FlatpakPermission _p(String section, String key, String value) =>
    FlatpakPermission(section: section, key: key, value: value);

void main() {
  group('derivePermissions', () {
    test('devices=all → audio + camera', () {
      final r = derivePermissions([_p('Context', 'devices', 'all;dri')]);
      expect(r, containsAll(['microphone', 'speakers', 'camera']));
    });

    test('sockets=pulseaudio → audio', () {
      final r = derivePermissions([
        _p('Context', 'sockets', 'pulseaudio;wayland'),
      ]);
      expect(r, containsAll(['microphone', 'speakers']));
      expect(r, isNot(contains('camera')));
    });

    test('session bus names map to permissions', () {
      final r = derivePermissions([
        _p('Session Bus Policy', 'org.freedesktop.Notifications', 'talk'),
        _p('Session Bus Policy', 'org.freedesktop.portal.Usb', 'talk'),
        _p('Session Bus Policy', 'org.freedesktop.portal.Location', 'talk'),
      ]);
      expect(r, containsAll(['notifications', 'usb', 'location']));
    });

    test('no duplicates across sources', () {
      final r = derivePermissions([
        _p('Context', 'devices', 'all'),
        _p('Context', 'sockets', 'pulseaudio'),
        _p('Session Bus Policy', 'org.freedesktop.portal.Camera', 'talk'),
      ]);
      expect(r.where((p) => p == 'camera').length, 1);
      expect(r.where((p) => p == 'microphone').length, 1);
    });

    test('empty metadata → no permissions', () {
      expect(derivePermissions([]), isEmpty);
    });
  });

  group('PermissionFlow', () {
    late FakeStore fake;
    late PermissionStorePortal store;

    setUp(() {
      fake = FakeStore();
      store = PermissionStorePortal.withCall(fake.call);
    });

    PermissionFlow flowFor(List<FlatpakPermission> meta) =>
        PermissionFlow(store, (_) async => meta);

    test(
      'unset permission prompts, then persists the granted decision',
      () async {
        final flow = flowFor([
          _p('Session Bus Policy', 'org.freedesktop.portal.Location', 'talk'),
        ]);
        fake.replies['GetPermission'] = [DBusArray.string(const [])]; // notSet

        final seen = <PermissionRequest>[];
        flow.requests.listen((req) {
          seen.add(req);
          flow.respond(req.id, true);
        });

        final result = await flow.ensureLaunchPermissions('org.x');
        expect(result['location'], PermissionStatus.granted);
        expect(seen.single.permission, 'location');

        final set = fake.calls.singleWhere((c) => c.member == 'SetPermission');
        expect(
          (set.values[4] as DBusArray).children
              .map((e) => (e as DBusString).value)
              .toList(),
          ['yes'],
        );
        await flow.close();
      },
    );

    test('denied response persists "no"', () async {
      final flow = flowFor([
        _p('Session Bus Policy', 'org.freedesktop.portal.Location', 'talk'),
      ]);
      fake.replies['GetPermission'] = [DBusArray.string(const [])];
      flow.requests.listen((req) => flow.respond(req.id, false));

      final result = await flow.ensureLaunchPermissions('org.x');
      expect(result['location'], PermissionStatus.denied);
      final set = fake.calls.singleWhere((c) => c.member == 'SetPermission');
      expect((set.values[4] as DBusArray).children.length, 1);
      expect(
        ((set.values[4] as DBusArray).children.first as DBusString).value,
        'no',
      );
      await flow.close();
    });

    test('already-set permission does not prompt', () async {
      final flow = flowFor([
        _p('Session Bus Policy', 'org.freedesktop.portal.Location', 'talk'),
      ]);
      fake.replies['GetPermission'] = [
        DBusArray.string(const ['yes']),
      ];
      var prompted = false;
      flow.requests.listen((_) => prompted = true);

      final result = await flow.ensureLaunchPermissions('org.x');
      expect(result['location'], PermissionStatus.granted);
      expect(prompted, isFalse);
      expect(fake.calls.any((c) => c.member == 'SetPermission'), isFalse);
      await flow.close();
    });
    test('no listener resolves to ask instead of hanging', () async {
      final flow = flowFor([
        _p('Session Bus Policy', 'org.freedesktop.portal.Location', 'talk'),
      ]);
      fake.replies['GetPermission'] = [DBusArray.string(const [])];

      final result = await flow
          .ensureLaunchPermissions('org.x')
          .timeout(const Duration(seconds: 5));
      expect(result['location'], PermissionStatus.ask);
      expect(fake.calls.any((c) => c.member == 'SetPermission'), isFalse);
      await flow.close();
    });

    test(
      'close cancels a pending prompt without persisting a decision',
      () async {
        final flow = flowFor([
          _p('Session Bus Policy', 'org.freedesktop.portal.Location', 'talk'),
        ]);
        fake.replies['GetPermission'] = [DBusArray.string(const [])];
        flow.requests.listen((_) {}); // listens, never responds

        final pending = flow.ensureLaunchPermissions('org.x');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await flow.close();

        final result = await pending.timeout(const Duration(seconds: 5));
        expect(result['location'], PermissionStatus.ask);
        expect(fake.calls.any((c) => c.member == 'SetPermission'), isFalse);
      },
    );
  });
}
