// Permission request/response flow for app launch.
//
// Derives the permissions an app will ask for from its sandbox metadata
// (Context devices/sockets + Session Bus Policy names), checks them against the
// PermissionStore, and surfaces a request for each unset permission so the UI
// can prompt the user. Responses are persisted back to the store.

import 'dart:async';

import '../permissions.dart';
import 'permission_store.dart';

/// A permission an app needs that has not yet been decided, awaiting a
/// [PermissionFlow.respond] call.
class PermissionRequest {
  final String id;
  final String appId;

  /// The requested permission, e.g. `camera`, `microphone`, `notifications`.
  final String permission;

  /// PermissionStore table + resource id this decision is stored under.
  final String table;
  final String resourceId;

  const PermissionRequest({
    required this.id,
    required this.appId,
    required this.permission,
    required this.table,
    required this.resourceId,
  });

  @override
  String toString() => 'PermissionRequest($appId needs $permission)';
}

/// Maps an app's sandbox metadata to the launch permissions it implies.
/// Mirrors the reference plugin's `RequestAppLaunchPermission` derivation.
List<String> derivePermissions(List<FlatpakPermission> metadata) {
  final requested = <String>[];
  void add(String p) {
    if (!requested.contains(p)) requested.add(p);
  }

  List<String> listValue(String section, String key) {
    for (final e in metadata) {
      if (e.section == section && e.key == key) {
        return e.value.split(';').where((s) => s.isNotEmpty).toList();
      }
    }
    return const [];
  }

  // [Context] devices=all → audio + camera.
  if (listValue('Context', 'devices').contains('all')) {
    add('microphone');
    add('speakers');
    add('camera');
  }

  // [Context] sockets=pulseaudio → audio.
  if (listValue('Context', 'sockets').contains('pulseaudio')) {
    add('microphone');
    add('speakers');
  }

  // [Session Bus Policy] well-known portal/service names.
  for (final e in metadata) {
    if (e.section != 'Session Bus Policy') continue;
    switch (e.key) {
      case 'org.freedesktop.Notifications':
        add('notifications');
      case 'org.freedesktop.portal.Usb':
        add('usb');
      case 'org.freedesktop.portal.Location':
        add('location');
      case 'org.freedesktop.portal.Camera':
        add('camera');
    }
  }

  return requested;
}

/// Drives launch-time permission prompts over a [PermissionStorePortal].
class PermissionFlow {
  PermissionFlow(this._store, this._metadataOf);

  final PermissionStorePortal _store;
  final Future<List<FlatpakPermission>> Function(String appId) _metadataOf;

  final _controller = StreamController<PermissionRequest>.broadcast();
  final _pending = <String, Completer<bool>>{};
  int _seq = 0;

  /// Requests emitted when a launch needs a permission that is not yet set.
  /// Listen, show UI, then call [respond].
  Stream<PermissionRequest> get requests => _controller.stream;

  /// Permissions [appId] will request, derived from its sandbox metadata.
  Future<List<String>> requestedPermissions(String appId) async =>
      derivePermissions(await _metadataOf(appId));

  /// Answer a pending [PermissionRequest] by id.
  void respond(String requestId, bool granted) {
    _pending.remove(requestId)?.complete(granted);
  }

  /// Resolve every launch permission for [appId]: already-decided permissions
  /// are read from the store; unset ones emit a [PermissionRequest] and block
  /// until answered, then the decision is persisted. Returns the final status
  /// of each requested permission.
  ///
  /// Requires a listener on [requests] that calls [respond]; otherwise unset
  /// permissions never resolve.
  Future<Map<String, PermissionStatus>> ensureLaunchPermissions(
    String appId,
  ) async {
    final result = <String, PermissionStatus>{};
    for (final permission in await requestedPermissions(appId)) {
      final target = permissionTarget(permission, appId);
      var status = await _store.get(target.table, target.id, appId);
      if (status == PermissionStatus.notSet) {
        final granted = await _prompt(appId, permission, target);
        status = granted ? PermissionStatus.granted : PermissionStatus.denied;
        await _store.setStatus(target.table, target.id, appId, status);
      }
      result[permission] = status;
    }
    return result;
  }

  Future<bool> _prompt(
    String appId,
    String permission,
    ({String table, String id}) target,
  ) {
    final id = '$appId:$permission:${_seq++}';
    final completer = Completer<bool>();
    _pending[id] = completer;
    _controller.add(
      PermissionRequest(
        id: id,
        appId: appId,
        permission: permission,
        table: target.table,
        resourceId: target.id,
      ),
    );
    return completer.future;
  }

  Future<void> close() async {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _pending.clear();
    await _controller.close();
  }
}
