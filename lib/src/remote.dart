import 'dart:typed_data';

/// Type of a configured Flatpak remote.
enum RemoteType {
  /// Configured by the current user (~/.local/share/flatpak/repo/config)
  user,

  /// Configured system-wide (/var/lib/flatpak/repo/config) — requires polkit
  system,

  /// Pre-installed by the distro in /etc/flatpak/remotes.d/ or
  /// /usr/share/flatpak/remotes.d/ — read-only unless overridden in /etc
  static_,
}

/// Subset filter applied to a Flathub-compatible remote.
///
/// Mirrors the `--subset=` flag accepted by `flatpak remote-add` and
/// `flatpak remote-modify`. The values correspond to the app-filter
/// subsets that Flathub exposes at `https://dl.flathub.org/repo/`.
enum RemoteSubset {
  /// All apps (no filter) — the default Flathub experience.
  none,

  /// Apps maintained directly by their upstream developer.
  /// Equivalent to `--subset=verified`.
  verified,

  /// Fully open-source apps (FLOSS only).
  /// Equivalent to `--subset=floss`.
  floss,

  /// Open-source apps maintained by their upstream developer.
  /// Equivalent to `--subset=verified_floss`.
  verifiedFloss;

  /// The string passed to libflatpak / D-Bus. Empty for [none].
  String get apiValue => switch (this) {
    RemoteSubset.none => '',
    RemoteSubset.verified => 'verified',
    RemoteSubset.floss => 'floss',
    RemoteSubset.verifiedFloss => 'verified_floss',
  };

  static RemoteSubset fromApiValue(String v) => switch (v) {
    'verified' => RemoteSubset.verified,
    'floss' => RemoteSubset.floss,
    'verified_floss' => RemoteSubset.verifiedFloss,
    _ => RemoteSubset.none,
  };
}

/// A configured Flatpak remote as returned by [FlatpakRemoteManager.list]
/// and [FlatpakRemoteManager.info].
class FlatpakRemote {
  final String name;
  final String url;
  final String title;
  final String comment;
  final String description;
  final String homepage;
  final String defaultBranch;
  final RemoteSubset subset;

  /// OSTree collection ID (e.g. `org.flathub.Stable`).
  /// Used for P2P distribution and USB sideloading.
  /// Empty string if not set.
  final String collectionId;

  /// Path to an app-filter file that restricts visible refs.
  /// Empty string if not set.
  final String filter;
  final RemoteType remoteType;
  final bool disabled;
  final bool gpgVerify;

  /// Skip dependency resolution when installing from this remote.
  final bool noDeps;

  /// Higher priority = searched first. Default is 1.
  final int priority;

  const FlatpakRemote({
    required this.name,
    required this.url,
    required this.title,
    this.comment = '',
    this.description = '',
    this.homepage = '',
    this.defaultBranch = '',
    this.subset = RemoteSubset.none,
    this.collectionId = '',
    this.filter = '',
    this.remoteType = RemoteType.user,
    this.disabled = false,
    this.gpgVerify = true,
    this.noDeps = false,
    this.priority = 1,
  });

  /// Returns true if this is a pre-installed distro remote that cannot
  /// be deleted without root.
  bool get isStatic => remoteType == RemoteType.static_;

  @override
  String toString() =>
      'FlatpakRemote($name  $url'
      '${subset != RemoteSubset.none ? "  subset=${subset.apiValue}" : ""}'
      '${disabled ? "  [disabled]" : ""}'
      '${isStatic ? "  [static]" : ""})';
}

/// Parameters for adding or modifying a remote.
///
/// Use [FlatpakRemoteConfig.fromFlatpakrepoFile] to populate all fields
/// automatically from a downloaded `.flatpakrepo` file.
///
/// For modify operations, only non-null fields are applied.
class FlatpakRemoteConfig {
  /// Remote URL. Required for [FlatpakRemoteManager.add]; optional for
  /// [FlatpakRemoteManager.modify].
  final String? url;
  final String? title;
  final String? comment;
  final String? homepage;
  final String? defaultBranch;

  /// Path to a local `.gpg` or `.asc` file containing the signing key.
  final String? gpgKeyPath;

  /// Raw GPG key bytes (alternative to [gpgKeyPath]).
  final Uint8List? gpgKeyData;
  final RemoteSubset? subset;
  final String? collectionId;

  /// Path to a local app-filter file. Set to `''` to clear.
  final String? filter;
  final int? priority;
  final bool? gpgVerify;
  final bool? disabled;
  final bool? noDeps;

  const FlatpakRemoteConfig({
    this.url,
    this.title,
    this.comment,
    this.homepage,
    this.defaultBranch,
    this.gpgKeyPath,
    this.gpgKeyData,
    this.subset,
    this.collectionId,
    this.filter,
    this.priority,
    this.gpgVerify,
    this.disabled,
    this.noDeps,
  });

  /// Path to a `.flatpakrepo` keyfile, if this config was created via
  /// [fromFlatpakrepoFile]. Null otherwise.
  String? get flatpakrepoPath => null;

  /// Construct from a pre-downloaded `.flatpakrepo` keyfile.
  /// The C bridge will call libflatpak's `flatpak_repo_from_bytes()` to
  /// extract all fields; this constructor just carries the file path.
  factory FlatpakRemoteConfig.fromFlatpakrepoFile(String path) =>
      _FlatpakrepoFileConfig(path);
}

class _FlatpakrepoFileConfig extends FlatpakRemoteConfig {
  final String _path;

  const _FlatpakrepoFileConfig(this._path) : super();

  @override
  String? get flatpakrepoPath => _path;
}
