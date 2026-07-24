// launch_app.dart — launch an installed app, list running instances, then stop it.
// Run as: dart run example/launch_app.dart [app_id]
// Defaults to org.gnome.Calculator.

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main(List<String> args) async {
  final appId = args.isNotEmpty ? args.first : 'org.gnome.Calculator';
  final client = FlatpakClient.user();

  print('Launching $appId ...');
  await client.launch(appId);

  // Give the sandbox a moment to register its instance.
  await Future<void>.delayed(const Duration(seconds: 1));

  final running = await client.listRunning();
  print('${running.length} running instance(s):');
  for (final inst in running) {
    print('  ${inst.appId.padRight(36)} '
        'instance=${inst.instanceId} pid=${inst.pid} '
        'running=${inst.isRunning}');
  }

  final isUp = running.any((i) => i.appId == appId && i.isRunning);
  if (isUp) {
    print('\nStopping $appId ...');
    await client.stop(appId);
    print('Stopped.');
  } else {
    print('\n$appId did not report a running instance (nothing to stop).');
  }

  await client.close();
}
