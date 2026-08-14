// Dart-side struct mirrors for glaze-decoded payloads.
// These mirror the C++ structs in native/include/flatpak_types.h.

import '../application.dart';
import '../remote.dart';

/// Decode a FlatpakRef from a JSON-like map (glaze binary → Dart map).
FlatpakRef decodeFlatpakRef(Map<String, dynamic> m) => FlatpakRef(
  kind: m['kind'] as String? ?? '',
  name: m['name'] as String? ?? '',
  arch: m['arch'] as String? ?? '',
  branch: m['branch'] as String? ?? '',
  commit: m['commit'] as String? ?? '',
  collectionId: m['collectionId'] as String? ?? '',
);

/// Decode an InstalledApp from a JSON-like map.
FlatpakApplication decodeInstalledApp(Map<String, dynamic> m) =>
    FlatpakApplication(
      ref: decodeFlatpakRef(m['ref'] as Map<String, dynamic>? ?? {}),
      origin: m['origin'] as String? ?? '',
      latestCommit: m['latestCommit'] as String? ?? '',
      installedPath: m['installedPath'] as String? ?? '',
      installedSize: m['installedSize'] as int? ?? 0,
      isCurrentArch: m['isCurrentArch'] as bool? ?? true,
      endOfLife: m['endOfLife'] as bool? ?? false,
      endOfLifeRebase: m['endOfLifeRebase'] as String? ?? '',
      appDataName: m['appDataName'] as String? ?? '',
      appDataSummary: m['appDataSummary'] as String? ?? '',
      appDataVersion: m['appDataVersion'] as String? ?? '',
      appDataIcon: m['appDataIcon'] as String? ?? '',
    );

/// Decode a FlatpakRemoteInfo from a JSON-like map.
FlatpakRemote decodeFlatpakRemote(Map<String, dynamic> m) => FlatpakRemote(
  name: m['name'] as String? ?? '',
  url: m['url'] as String? ?? '',
  title: m['title'] as String? ?? '',
  comment: m['comment'] as String? ?? '',
  description: m['description'] as String? ?? '',
  homepage: m['homepage'] as String? ?? '',
  defaultBranch: m['defaultBranch'] as String? ?? '',
  subset: RemoteSubset.fromApiValue(m['subset'] as String? ?? ''),
  collectionId: m['collectionId'] as String? ?? '',
  filter: m['filter'] as String? ?? '',
  remoteType: _decodeRemoteType(m['remoteType'] as int? ?? 0),
  disabled: m['disabled'] as bool? ?? false,
  gpgVerify: m['gpgVerify'] as bool? ?? true,
  noDeps: m['noDeps'] as bool? ?? false,
  priority: m['priority'] as int? ?? 1,
);

RemoteType _decodeRemoteType(int v) => switch (v) {
  1 => RemoteType.system,
  2 => RemoteType.static_,
  _ => RemoteType.user,
};
