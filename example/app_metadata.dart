// app_metadata.dart — resolve an installed app's icon and AppStream metadata.
// Run as: dart run example/app_metadata.dart [app_id]
// Defaults to org.gnome.Calculator.

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main(List<String> args) async {
  final appId = args.isNotEmpty ? args.first : 'org.gnome.Calculator';
  final client = FlatpakClient.user();

  final icon = await client.appStream.installedIconPath(appId);
  print('Installed icon: ${icon ?? '(none found)'}');

  // Refresh then read the catalog metadata for flathub. Adjust the remote to
  // match your configuration; pass an empty remote to search every remote.
  try {
    await client.appStream.refresh('flathub');
  } on FlatpakException catch (e) {
    print('AppStream refresh skipped: ${e.message}');
  }

  final detail = await client.appStream.componentDetail(appId);
  if (detail == null) {
    print('No AppStream component found for $appId.');
  } else {
    print('Component: ${detail.component.name}');
    print('  categories:  ${detail.categories.length}');
    print('  icons:       ${detail.icons.length}');
    print('  screenshots: ${detail.screenshotImages.length}');
    print('  releases:    ${detail.releases.length}');
  }

  await client.close();
}
