// example/example.dart — minimal usage of flatpak_dart.
//
// Build the native library first:
//   ./scripts/build_release.sh
//
// Run with:
//   FLATPAK_NC_LIB=build-release/libflatpak_nc.so dart run example/example.dart
//
// See also: list_apps.dart, install_app.dart, manage_remotes.dart,
//           watch_updates.dart for more complete examples.

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.user();

  // List installed applications
  final apps = await client.listApplications();
  print('${apps.length} app(s) installed:\n');
  for (final app in apps) {
    print('  ${app.ref.name.padRight(40)} ${app.appDataVersion}');
  }

  // List configured remotes
  print('');
  final remotes = await client.remotes.list();
  print('${remotes.length} remote(s):\n');
  for (final r in remotes) {
    print('  ${r.name.padRight(24)} ${r.url}');
  }

  await client.close();
}
