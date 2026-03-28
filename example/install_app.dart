// install_app.dart — install a Flatpak application with progress.
// Run as: dart run example/install_app.dart
//
// Installs org.gnome.Calculator from flathub (user installation).
// Change the ref below to install a different app.

import 'dart:io';

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.user();

  const remote = 'flathub';
  const ref = 'org.gnome.Calculator';

  print('Installing $ref from $remote...\n');

  final tx = client.install(remote, ref);

  await for (final p in tx.progress) {
    // Clear line and reprint progress
    final bar = p.progressLabel;
    stdout.write('\r  $bar  [${p.status}]'.padRight(80));
  }

  try {
    await tx.result;
    print('\n\nInstalled successfully.');
  } on FlatpakTransactionException catch (e) {
    if (e.isAlreadyRunning) {
      print('\n\nAnother install is in progress. Try again later.');
    } else if (e.isCancelled) {
      print('\n\nInstallation cancelled.');
    } else {
      print('\n\nInstallation failed: ${e.message}');
    }
  }

  await client.close();
}
