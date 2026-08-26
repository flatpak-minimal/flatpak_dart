// Installed-app icon resolution from an app's deploy directory.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves an on-disk icon file for an installed application.
///
/// [deployDir] is the app's deploy directory (`installedPath`); [appId] is the
/// application id (e.g. `org.gnome.Chess`). Returns the absolute path of the
/// highest-resolution icon found, or `null` when the app ships none.
String? resolveInstalledIconPath(String deployDir, String appId) {
  if (deployDir.isEmpty) return null;

  const sizes = <String>[
    '512x512',
    '256x256',
    '128x128',
    '96x96',
    '64x64',
    '48x48',
    '32x32',
    '24x24',
    '16x16',
  ];
  const roots = <String>[
    'files/share/icons/hicolor',
    'export/share/icons/hicolor',
  ];

  for (final root in roots) {
    // Scalable outranks every raster size.
    final svg = p.join(deployDir, root, 'scalable', 'apps', '$appId.svg');
    if (File(svg).existsSync()) return svg;

    for (final size in sizes) {
      final png = p.join(deployDir, root, size, 'apps', '$appId.png');
      if (File(png).existsSync()) return png;
    }
  }

  const appInfoRoot = 'files/share/app-info/icons/flatpak';
  for (final size in const ['128x128', '64x64']) {
    final png = p.join(deployDir, appInfoRoot, size, '$appId.png');
    if (File(png).existsSync()) return png;
  }

  return null;
}
