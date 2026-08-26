// launch_app.dart — launch an installed app, then stop it.
// Run as: dart run example/launch_app.dart [app_id]
// Defaults to org.gnome.Calculator.

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main(List<String> args) async {
  final appId = args.isNotEmpty ? args.first : 'org.gnome.Calculator';
  final client = FlatpakClient.user();

  print('Launching $appId ...');
  final instance = await client.launch(appId);
  print(
    'instance=${instance.instanceId} pid=${instance.pid} '
    'childPid=${instance.childPid}',
  );

  print('\nStopping $appId ...');
  await client.stop(appId);
  print('Stopped (SIGTERM sent; SIGKILL follows after a 1.5s grace period)');

  await Future<void>.delayed(const Duration(seconds: 2));

  await client.close();
}
