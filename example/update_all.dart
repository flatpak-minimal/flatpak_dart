// update_all.dart — check for and apply all available updates.
// Run as: dart run example/update_all.dart

import 'dart:io';

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.user();

  // Check what needs updating
  final updates = await client.checkForUpdates();
  if (updates.isEmpty) {
    print('Everything is up to date.');
    await client.close();
    return;
  }

  print('${updates.length} update(s) available:');
  for (final ref in updates) {
    print('  ${ref.name}/${ref.arch}/${ref.branch}');
  }

  // Apply all updates in a single transaction
  print('\nUpdating all...\n');

  final tx = client.update(); // empty ref = update everything
  await for (final p in tx.progress) {
    stdout.write('\r  ${p.progressLabel}  [${p.status}]'.padRight(80));
  }

  try {
    await tx.result;
    print('\n\nAll updates applied.');
  } on FlatpakTransactionException catch (e) {
    print('\n\nUpdate failed: ${e.message}');
  }

  await client.close();
}
