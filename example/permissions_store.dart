// permissions_store.dart — read/write xdg-desktop-portal permissions.
// Run as: dart run example/permissions_store.dart [app_id]
// Requires a running session bus with xdg-desktop-portal.

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main(List<String> args) async {
  final appId = args.isNotEmpty ? args.first : 'org.gnome.Calculator';
  final client = FlatpakClient.user();
  final store = client.permissionsStore;

  // Current status of a few common permissions.
  final status = await store.check(appId, [
    'notifications',
    'camera',
    'location',
  ]);
  print('Permissions for $appId:');
  status.forEach((perm, s) => print('  ${perm.padRight(14)} ${s.name}'));

  // Grant notifications, then read it back.
  await store.setStatus(
    PermissionTable.notifications,
    'notifications',
    appId,
    PermissionStatus.granted,
  );
  final now = await store.get(
    PermissionTable.notifications,
    'notifications',
    appId,
  );
  print('\nAfter granting notifications: ${now.name}');

  // On uninstall you would wipe every stored permission for the app:
  // await store.removeAllForApp(appId);

  await client.close();
}
