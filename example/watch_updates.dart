// watch_updates.dart — monitor for update availability using FlatpakMonitor.
// Run as: dart run example/watch_updates.dart
//
// Uses inotify on the installation directory. Works from any host process;
// no Flatpak sandbox required.

import 'dart:io';

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.system();
  final monitor = client.watchUpdates();

  print('Watching for updates... (Ctrl+C to stop)\n');

  await for (final _ in monitor.events) {
    final updates = await client.checkForUpdates();
    if (updates.isEmpty) {
      print('[${DateTime.now()}] Change detected, but no updates pending.');
    } else {
      print('[${DateTime.now()}] ${updates.length} update(s) available:');
      for (final ref in updates) {
        print('  ${ref.name}/${ref.arch}/${ref.branch}');
      }
    }
  }

  await monitor.close();
  await client.close();
}
