// launch_with_permissions.dart — derive an app's requested permissions,
// prompt for any that are unset, then launch it.
// Run as: dart run example/launch_with_permissions.dart [app_id]

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main(List<String> args) async {
  final appId = args.isNotEmpty ? args.first : 'org.gnome.Calculator';
  final client = FlatpakClient.user();

  // A real UI would show a dialog; here we auto-approve each prompt.
  client.permissionFlow.requests.listen((req) {
    print('  prompt: ${req.appId} wants ${req.permission} → granting');
    client.permissionFlow.respond(req.id, true);
  });

  final requested = await client.permissionFlow.requestedPermissions(appId);
  print(
    '$appId requests: ${requested.isEmpty ? '(none)' : requested.join(', ')}',
  );

  await client.launchWithPermissions(appId);
  print('Launched $appId');

  await client.close();
}
