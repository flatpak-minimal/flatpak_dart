/// An installed Flatpak application or runtime.
class FlatpakApplication {
  final FlatpakRef ref;
  final String origin;
  final String latestCommit;
  final String installedPath;
  final int installedSize;
  final bool isCurrentArch;
  final bool endOfLife;
  final String endOfLifeRebase;
  final String appDataName;
  final String appDataSummary;
  final String appDataVersion;
  final String appDataIcon;

  const FlatpakApplication({
    required this.ref,
    required this.origin,
    this.latestCommit = '',
    this.installedPath = '',
    this.installedSize = 0,
    this.isCurrentArch = true,
    this.endOfLife = false,
    this.endOfLifeRebase = '',
    this.appDataName = '',
    this.appDataSummary = '',
    this.appDataVersion = '',
    this.appDataIcon = '',
  });

  @override
  String toString() =>
      'FlatpakApplication(${ref.name}  ${ref.arch}/${ref.branch}  '
      'origin=$origin  size=$installedSize)';
}

/// A Flatpak ref — application or runtime identifier.
class FlatpakRef {
  /// "app" or "runtime".
  final String kind;
  final String name;
  final String arch;
  final String branch;
  final String commit;
  final String collectionId;

  const FlatpakRef({
    required this.kind,
    required this.name,
    this.arch = '',
    this.branch = '',
    this.commit = '',
    this.collectionId = '',
  });

  @override
  String toString() => '$kind/$name/$arch/$branch';
}
