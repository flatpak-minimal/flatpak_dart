// arch_policy.dart — which architectures' apps this machine can actually run.
// Run as: dart run example/arch_policy.dart

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  print('Host architecture : $hostFlatpakArch');
  print('Runs natively     : ${compatibleArches(hostFlatpakArch!).join(', ')}');

  // Architectures the kernel can execute through binfmt_misc. On a machine
  // with qemu-user-static this is often a long list — and mostly useless on
  // its own, because a remote publishes apps for very few of them.
  final emulated = kernelExecutableArches();
  print(
    'Kernel can emulate: '
    '${emulated.isEmpty ? '(none)' : (emulated.toList()..sort()).join(', ')}',
  );

  final client = FlatpakClient.user()..archPolicy = ArchPolicy.emulated;
  print('\nPer remote, with ArchPolicy.emulated:');
  for (final remote in await client.remotes.list()) {
    final downloaded = client.appStream.downloadedArches(remote.name);
    final usable = client.appStream.usableArches(remote.name);
    print('  ${remote.name}');
    print(
      '    catalogs downloaded : ${downloaded.isEmpty ? '(none)' : downloaded.join(', ')}',
    );
    print(
      '    actually usable     : ${usable.isEmpty ? '(none)' : usable.join(', ')}',
    );
  }

  // Note what that shows: an architecture appears under "usable" only when the
  // kernel can execute it AND a catalog for it has been downloaded. A qemu
  // registration with nothing to run never turns into apps in a list.

  // The same policy governs installed apps. A foreign-arch app can be
  // installed (`flatpak install --arch=...` does not refuse) but cannot run,
  // so it is hidden unless asked for.
  final all = await client.listApplications(allArches: true);
  final runnable = await client.listApplications();
  print('\nInstalled: ${all.length} total, ${runnable.length} runnable here');
  for (final app in all) {
    final mark = client.canRunArch(app.ref.arch) ? ' ' : '!';
    print('  $mark ${app.ref.name.padRight(28)} ${app.ref.arch}');
  }

  // Nothing about binfmt_misc can be watched cheaply, so after installing or
  // removing an emulator tell the client to look again:
  client.refreshArchSupport();

  await client.close();
}
