// install_app.dart — install a Flatpak application with permissions + progress.
// Run as: dart run example/install_app.dart [app-id]
//
// Defaults to org.gnome.Calculator from flathub (user installation).

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

String _opChar(String op) => switch (op) {
  'install' => 'i',
  'update' => 'u',
  'uninstall' => 'r',
  _ => '?',
};

String _fmtSize(int n) => n >= 1 << 20
    ? '${(n / (1 << 20)).toStringAsFixed(1)} MB'
    : n >= 1 << 10
    ? '${(n / (1 << 10)).toStringAsFixed(1)} kB'
    : '$n B';

Future<void> main(List<String> args) async {
  final client = FlatpakClient.user();

  const remote = 'flathub';
  final appId = args.isNotEmpty ? args[0] : 'org.gnome.Calculator';
  final ref = 'app/$appId/$_arch/stable';

  print('Looking for matches\u2026\n');

  // Fetch and display permissions before installing
  try {
    final metadata = await client.fetchRemoteMetadata(remote, ref);
    final context = metadata.where((e) => e.section == 'Context').toList();
    if (context.isNotEmpty) {
      print('$appId permissions:');
      final perms = <String>[];
      for (final e in context) {
        // Values are semicolon-separated lists like "ipc;network;"
        final items = e.value.split(';').where((s) => s.isNotEmpty).toList();
        perms.addAll(items);
      }
      print('    ${perms.join('   ')}\n');
    }
  } catch (e) {
    // Non-fatal — proceed with install even if metadata fetch fails
    print('(could not fetch permissions: $e)\n');
  }

  // Table header
  print(
    '        ${"ID".padRight(40)} ${"Branch".padRight(12)} '
    '${"Op".padRight(4)} ${"Remote".padRight(12)} Download',
  );

  final tx = client.install(remote, ref);

  final ops = <String, int>{};
  var opNum = 0;
  final lines = <int, String>{};

  await for (final p in tx.progress) {
    if (!ops.containsKey(p.ref)) {
      opNum++;
      ops[p.ref] = opNum;
    }
    final num = ops[p.ref]!;

    final parts = p.ref.split('/');
    final id = parts.length >= 2 ? parts[1] : p.ref;
    final branch = parts.length >= 4 ? parts[3] : '';

    final done = p.status == 'Done';
    final mark = done ? '\u2713' : ' ';
    final dl = p.bytesTransferred > 0 ? _fmtSize(p.bytesTransferred) : '';

    final line =
        ' $num. [$mark] ${id.padRight(40)} ${branch.padRight(12)} '
        '${_opChar(p.op).padRight(4)} ${remote.padRight(12)} $dl';

    if (lines[num] != line) {
      lines[num] = line;
      for (var i = 1; i <= opNum; i++) {
        stdout.write('\r\x1B[K${lines[i] ?? ""}\n');
      }
      stdout.write('\x1B[${opNum}A');
    }
  }

  stdout.write('\n' * opNum);

  try {
    await tx.result;
    print('\nInstallation complete.');
  } on FlatpakTransactionException catch (e) {
    if (e.isAlreadyRunning) {
      print('\nAnother install is in progress. Try again later.');
    } else {
      print('\nInstallation failed: ${e.message}');
    }
  }

  await client.close();
}
