// xdg-desktop-portal PermissionStore client (pure Dart, no native code).
//
// Wraps org.freedesktop.impl.portal.PermissionStore at
// /org/freedesktop/impl/portal/PermissionStore — the backing store the portals
// use to persist per-app permission decisions (devices, location,
// notifications, background).

import 'package:dbus/dbus.dart';

const _service = 'org.freedesktop.impl.portal.PermissionStore';
const _path = '/org/freedesktop/impl/portal/PermissionStore';
const _iface = 'org.freedesktop.impl.portal.PermissionStore';

/// Stored permission value for an app on a resource.
enum PermissionStatus {
  granted, // "yes"
  denied, // "no"
  ask, // "ask"
  notSet; // no entry exists

  /// Maps a raw PermissionStore string to a status ("yes"/"no"/"ask").
  static PermissionStatus fromValue(String? value) => switch (value) {
    'yes' => granted,
    'no' => denied,
    'ask' => ask,
    _ => notSet,
  };

  /// First entry of a PermissionStore permission list decides the status.
  static PermissionStatus fromPermissions(List<String> permissions) =>
      permissions.isEmpty ? notSet : fromValue(permissions.first);

  /// The PermissionStore string for this status, or null for [notSet].
  String? get value => switch (this) {
    granted => 'yes',
    denied => 'no',
    ask => 'ask',
    notSet => null,
  };
}

/// Well-known PermissionStore tables.
abstract final class PermissionTable {
  static const devices = 'devices';
  static const location = 'location';
  static const notifications = 'notifications';
  static const background = 'background';
}

/// Resolves the (table, id) a launch [permission] of [app] is stored under.
/// Mirrors the reference plugin's permission→table mapping.
({String table, String id}) permissionTarget(String permission, String app) =>
    switch (permission) {
      'location' => (table: PermissionTable.location, id: 'location'),
      'notifications' => (
        table: PermissionTable.notifications,
        id: 'notifications',
      ),
      'background' => (table: PermissionTable.background, id: app),
      _ => (table: PermissionTable.devices, id: permission),
    };

/// Injectable method caller — production wraps [DBusRemoteObject.callMethod];
/// tests supply a fake. Returns the reply's out-arguments.
typedef PermissionStoreCall =
    Future<List<DBusValue>> Function(
      String member,
      List<DBusValue> values, {
      required DBusSignature replySignature,
    });

/// Client for the session-bus PermissionStore.
class PermissionStorePortal {
  PermissionStorePortal({DBusClient? client})
    : _ownsClient = client == null,
      _client = client ?? DBusClient.session(),
      _call = null {
    _object = DBusRemoteObject(
      _client!,
      name: _service,
      path: DBusObjectPath(_path),
    );
  }

  /// Test seam: drive the portal with a fake method caller.
  PermissionStorePortal.withCall(PermissionStoreCall call)
    : _call = call,
      _client = null,
      _ownsClient = false;

  final DBusClient? _client;
  final bool _ownsClient;
  final PermissionStoreCall? _call;
  DBusRemoteObject? _object;

  Future<List<DBusValue>> _invoke(
    String member,
    List<DBusValue> values,
    DBusSignature reply,
  ) async {
    final call = _call;
    if (call != null) return call(member, values, replySignature: reply);
    final r = await _object!.callMethod(
      _iface,
      member,
      values,
      replySignature: reply,
    );
    return r.values;
  }

  // ── Per-app permission on a resource ────────────────────────────────────

  /// GetPermission(table, id, app) → status.
  Future<PermissionStatus> get(String table, String id, String app) async {
    try {
      final out = await _invoke('GetPermission', [
        DBusString(table),
        DBusString(id),
        DBusString(app),
      ], DBusSignature('as'));
      return PermissionStatus.fromPermissions(_strings(out.first));
    } on DBusMethodResponseException catch (e) {
      if (_isNotFound(e)) return PermissionStatus.notSet;
      rethrow;
    }
  }

  /// SetPermission(table, create, id, app, permissions).
  Future<void> set(
    String table,
    String id,
    String app,
    List<String> permissions, {
    bool create = true,
  }) => _invoke('SetPermission', [
    DBusString(table),
    DBusBoolean(create),
    DBusString(id),
    DBusString(app),
    DBusArray.string(permissions),
  ], DBusSignature(''));

  /// SetPermission convenience taking a [PermissionStatus].
  Future<void> setStatus(
    String table,
    String id,
    String app,
    PermissionStatus status, {
    bool create = true,
  }) {
    final v = status.value;
    return set(table, id, app, v == null ? const [] : [v], create: create);
  }

  /// DeletePermission(table, id, app). No-op if the entry does not exist.
  Future<void> delete(String table, String id, String app) async {
    try {
      await _invoke('DeletePermission', [
        DBusString(table),
        DBusString(id),
        DBusString(app),
      ], DBusSignature(''));
    } on DBusMethodResponseException catch (e) {
      if (_isNotFound(e)) return;
      rethrow;
    }
  }

  // ── Whole-resource operations ───────────────────────────────────────────

  /// Lookup(table, id) → {app: permissions}. Empty if not found.
  Future<Map<String, List<String>>> lookup(String table, String id) async {
    try {
      final out = await _invoke('Lookup', [
        DBusString(table),
        DBusString(id),
      ], DBusSignature('a{sas}v'));
      final dict = out.first as DBusDict;
      return dict.children.map(
        (k, v) => MapEntry((k as DBusString).value, _strings(v)),
      );
    } on DBusMethodResponseException catch (e) {
      if (_isNotFound(e)) return {};
      rethrow;
    }
  }

  /// List(table) → resource ids with any permissions set. Empty if not found.
  Future<List<String>> list(String table) async {
    try {
      final out = await _invoke('List', [
        DBusString(table),
      ], DBusSignature('as'));
      return _strings(out.first);
    } on DBusMethodResponseException catch (e) {
      if (_isNotFound(e)) return [];
      rethrow;
    }
  }

  /// Set(table, create, id, appPermissions, data) — write a whole resource.
  Future<void> setResource(
    String table,
    String id,
    Map<String, List<String>> appPermissions, {
    String data = '',
    bool create = true,
  }) => _invoke('Set', [
    DBusString(table),
    DBusBoolean(create),
    DBusString(id),
    DBusDict(DBusSignature('s'), DBusSignature('as'), {
      for (final e in appPermissions.entries)
        DBusString(e.key): DBusArray.string(e.value),
    }),
    DBusVariant(DBusString(data)),
  ], DBusSignature(''));

  /// Delete(table, id) — remove a resource and all its app permissions.
  Future<void> deleteResource(String table, String id) async {
    try {
      await _invoke('Delete', [
        DBusString(table),
        DBusString(id),
      ], DBusSignature(''));
    } on DBusMethodResponseException catch (e) {
      if (_isNotFound(e)) return;
      rethrow;
    }
  }

  /// SetValue(table, create, id, data) — store opaque resource data.
  Future<void> setValue(
    String table,
    String id,
    String data, {
    bool create = true,
  }) => _invoke('SetValue', [
    DBusString(table),
    DBusBoolean(create),
    DBusString(id),
    DBusVariant(DBusString(data)),
  ], DBusSignature(''));

  // ── High-level helpers ──────────────────────────────────────────────────

  /// Resolve the status of each launch [permissions] entry for [app].
  ///
  /// Distinct resources are looked up concurrently, and permissions sharing a
  /// resource (every device permission shares the `devices` table) reuse a
  /// single round trip.
  Future<Map<String, PermissionStatus>> check(
    String app,
    List<String> permissions,
  ) async {
    final targets = {
      for (final permission in permissions)
        permission: permissionTarget(permission, app),
    };
    final resources = {
      for (final t in targets.values) '${t.table}\u0000${t.id}': t,
    };

    final looked = await Future.wait([
      for (final t in resources.values) lookup(t.table, t.id),
    ]);
    final byResource = Map.fromIterables(resources.keys, looked);

    return {
      for (final e in targets.entries)
        e.key: PermissionStatus.fromPermissions(
          byResource['${e.value.table}\u0000${e.value.id}']?[app] ?? const [],
        ),
    };
  }

  /// Remove every stored permission for [app] across all tables — call this on
  /// uninstall so a reinstalled app starts from a clean slate.
  Future<void> removeAllForApp(String app) async {
    final targets = <({String table, String id})>[
      (table: PermissionTable.notifications, id: 'notifications'),
      (table: PermissionTable.location, id: 'location'),
      (table: PermissionTable.background, id: app),
      for (final id in await list(PermissionTable.devices))
        (table: PermissionTable.devices, id: id),
    ];
    await Future.wait([
      for (final target in targets) delete(target.table, target.id, app),
    ]);
  }

  Future<void> close() async {
    if (_ownsClient) await _client!.close();
  }

  static List<String> _strings(DBusValue array) => (array as DBusArray).children
      .map((c) => (c as DBusString).value)
      .toList();
}

/// Whether [e] means "no such entry" rather than "the call failed".
///
/// The error *name* is the real signal, and xdg-desktop-portal's permission
/// store always sends it: `Lookup`, `GetPermission` and `Delete` on a missing
/// resource each answer `org.freedesktop.portal.Error.NotFound` with the
/// message `No entry for <id>` (verified against xdg-permission-store; `List`
/// on an unknown table does not error at all, it returns an empty array).
///
/// The message check is only a fallback for a backend that reports the
/// condition without the well-known name. It is deliberately narrow: matching
/// something as generic as "not found" would quietly turn a real failure — a
/// corrupt database, a backend that cannot open its store — into "no
/// permission is set", and the caller would then prompt or write as if the
/// slate were clean.
///
/// `UnknownMethod` is not not-found either: a portal that lacks the method can
/// never answer, and an empty result would read as a permanent miss.
bool _isNotFound(DBusMethodResponseException e) {
  if (e.errorName == 'org.freedesktop.portal.Error.NotFound') return true;
  final values = e.response.values;
  final msg = values.isNotEmpty && values.first is DBusString
      ? (values.first as DBusString).value
      : '';
  return msg.startsWith('No entry for');
}
