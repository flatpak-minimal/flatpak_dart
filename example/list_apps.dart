// list_apps.dart — list installed Flatpak applications.
// Run as: dart run example/list_apps.dart

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.system();

  final apps = await client.listApplications();
  print('${apps.length} applications installed:\n');

  for (final app in apps) {
    final eol = app.endOfLife ? '  [EOL]' : '';
    print('  ${app.ref.name.padRight(40)} '
        '${app.ref.arch}/${app.ref.branch}  '
        'origin=${app.origin}$eol');
    if (app.appDataName.isNotEmpty) {
      print('    ${app.appDataName} — ${app.appDataSummary}');
    }
  }

  await client.close();
}
