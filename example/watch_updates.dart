// watch_updates.dart — monitor for install/uninstall changes.
// Run as: dart run example/watch_updates.dart
//
// Uses GFileMonitor (inotify) on the installation directory. Detects
// which apps were added or removed by diffing the app list on each change.

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.user();
  final monitor = client.watchUpdates();

  // Snapshot current state
  var knownApps = {
    for (final app in await client.listApplications()) app.ref.name: app,
  };

  print('Watching ${knownApps.length} app(s)... (Ctrl+C to stop)\n');

  await for (final _ in monitor.events) {
    final currentApps = {
      for (final app in await client.listApplications()) app.ref.name: app,
    };

    final added = currentApps.keys.where((k) => !knownApps.containsKey(k));
    final removed = knownApps.keys.where((k) => !currentApps.containsKey(k));

    for (final name in added) {
      final app = currentApps[name]!;
      print('[${DateTime.now()}] + installed: $name ${app.appDataVersion}');
    }
    for (final name in removed) {
      print('[${DateTime.now()}] - removed:   $name');
    }

    knownApps = currentApps;
  }

  await monitor.close();
  await client.close();
}
