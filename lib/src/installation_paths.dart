// Where a named Flatpak installation lives on disk, and how much room is left
// on the filesystem holding it.
//
// The path resolution is shared rather than duplicated: the AppStream cache
// needs it to find `appstream/<remote>/…`, and storage reporting needs it to
// pick a filesystem. Two copies of the XDG_DATA_HOME → ~/.local/share →
// /var/lib/flatpak ladder would drift.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'exceptions.dart';
import 'storage_info.dart';

/// Base directory of the installation called [name].
///
/// `user` and `system` are the two libflatpak well-known names; anything else
/// is an absolute path, as passed to `FlatpakClient.at()`.
String installationPathFor(String name) {
  switch (name) {
    case 'user':
      final xdg = Platform.environment['XDG_DATA_HOME'];
      final base = (xdg != null && xdg.isNotEmpty)
          ? xdg
          : p.join(Platform.environment['HOME'] ?? '', '.local', 'share');
      return p.join(base, 'flatpak');
    case 'system':
      return '/var/lib/flatpak';
    default:
      return name;
  }
}

/// Parses `df -B1 --output=size,avail <path>` output.
///
/// The first line is `df`'s header and the second carries the figures, both in
/// bytes because of `-B1`. Anything that does not have that shape — a `df`
/// without GNU `--output`, or a locale that renders the numbers differently —
/// raises [FlatpakRemoteException] rather than a bare [FormatException], so a
/// caller can catch one exception type for the whole call.
StorageInfo parseDfOutput(String stdout, {String context = 'df'}) {
  final lines = const LineSplitter()
      .convert(stdout)
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) {
    throw FlatpakRemoteException('unexpected $context output: $stdout');
  }
  final parts = lines.last.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) {
    throw FlatpakRemoteException('unexpected $context row: ${lines.last}');
  }
  final total = int.tryParse(parts[0]);
  final available = int.tryParse(parts[1]);
  if (total == null || available == null) {
    throw FlatpakRemoteException('non-numeric $context figures: ${lines.last}');
  }
  return StorageInfo(totalBytes: total, availableBytes: available);
}
