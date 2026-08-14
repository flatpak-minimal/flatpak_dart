// uninstall_app.dart — uninstall a Flatpak application.
// Run as: FLATPAK_NC_LIB=build-release/libflatpak_nc.so dart run example/uninstall_app.dart <app-id>
//
// Example:
//   dart run example/uninstall_app.dart org.gnome.Calculator

import 'dart:io';

import 'package:flatpak_dart/flatpak_dart.dart';

String get _arch {
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  return switch (machine) {
    'x86_64' => 'x86_64',
    'aarch64' => 'aarch64',
    'arm64' => 'aarch64',
    _ => machine,
  };
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/uninstall_app.dart <app-id>');
    print('  e.g. org.gnome.Calculator');
    print('');
    print('Installed apps:');
    final client = FlatpakClient.user();
    for (final app in await client.listApplications()) {
      print('  ${app.ref}');
    }
    await client.close();
    exit(1);
  }

  final input = args[0];
  final client = FlatpakClient.user();

  // If a bare app ID was given, resolve to full ref with host arch.
  final ref = input.contains('/') ? input : 'app/$input/$_arch/stable';

  print('Uninstalling $ref...\n');

  final tx = client.uninstall(ref);

  final ops = <String, String>{}; // ref -> status
  var opNum = 0;

  await for (final p in tx.progress) {
    if (!ops.containsKey(p.ref)) {
      opNum++;
      ops[p.ref] = p.status;
      // Extract short ID from ref like "app/org.gnome.Calculator/x86_64/stable"
      final parts = p.ref.split('/');
      final id = parts.length >= 2 ? parts[1] : p.ref;
      final branch = parts.length >= 4 ? parts[3] : '';
      final opChar = p.op == 'uninstall' ? '-' : p.op[0];
      print(' $opNum. [$opChar] ${id.padRight(40)} $branch');
    }
  }

  try {
    await tx.result;
    print('\nUninstall complete.');
  } on FlatpakTransactionException catch (e) {
    print('\nUninstall failed: ${e.message}');
  }

  await client.close();
}
