// list_running.dart — show currently running Flatpak app instances.
// Run as: dart run example/list_running.dart

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.user();
  final running = await client.listRunning();

  if (running.isEmpty) {
    print('No running instances.');
  } else {
    print('${running.length} running instance(s):');
    for (final i in running) {
      print(
        '  ${i.appId.padRight(36)} '
        'instance=${i.instanceId} pid=${i.pid} '
        'child=${i.childPid} running=${i.isRunning}',
      );
    }
  }

  await client.close();
}
