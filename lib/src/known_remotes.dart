// known_remotes.dart
//
// Typed constants for well-known public Flatpak remotes.
// Source / reference: https://github.com/boredsquirrel/Flatpak-remotes
//
// URLs are the actual OSTree repo URLs, not the .flatpakrepo keyfile URLs.
// The .flatpakrepo files contain these URLs plus GPG keys and metadata.

import 'remote.dart';

abstract final class KnownRemotes {
  // ── Flathub stable ──────────────────────────────────────────────────────
  // All four Flathub variants share the same repo URL; the subset
  // filter is the only difference between them.

  /// The standard Flathub remote — all apps, no filter.
  static const flathub = FlatpakRemoteConfig(
    url: 'https://dl.flathub.org/repo/',
    title: 'Flathub',
    collectionId: 'org.flathub.Stable',
    gpgVerify: true,
  );

  /// Flathub verified subset — apps maintained by their upstream developers.
  static const flathubVerified = FlatpakRemoteConfig(
    url: 'https://dl.flathub.org/repo/',
    title: 'Flathub Verified',
    subset: RemoteSubset.verified,
    gpgVerify: true,
  );

  /// Flathub FLOSS subset — open-source apps only.
  static const flathubFloss = FlatpakRemoteConfig(
    url: 'https://dl.flathub.org/repo/',
    title: 'Flathub FLOSS',
    subset: RemoteSubset.floss,
    gpgVerify: true,
  );

  /// Flathub verified FLOSS subset — open-source + upstream-maintained.
  static const flathubVerifiedFloss = FlatpakRemoteConfig(
    url: 'https://dl.flathub.org/repo/',
    title: 'Flathub Verified FLOSS',
    subset: RemoteSubset.verifiedFloss,
    gpgVerify: true,
  );

  // ── Flathub beta ────────────────────────────────────────────────────────

  /// Flathub beta channel — pre-release apps.
  static const flathubBeta = FlatpakRemoteConfig(
    url: 'https://flathub.org/beta-repo/',
    title: 'Flathub Beta',
    gpgVerify: true,
  );

  // ── Distribution remotes ────────────────────────────────────────────────

  /// Fedora Flatpaks — apps built from RPMs with the Fedora runtime.
  static const fedora = FlatpakRemoteConfig(
    url: 'oci+https://registry.fedoraproject.org',
    title: 'Fedora',
    gpgVerify: true,
  );

  /// elementary AppCenter — curated apps for elementary OS.
  static const elementaryOs = FlatpakRemoteConfig(
    url: 'https://flatpak.elementary.io/repo/',
    title: 'elementary AppCenter',
    gpgVerify: true,
  );

  /// PureOS store — Purism apps.
  static const pureOs = FlatpakRemoteConfig(
    url: 'https://store.puri.sm/repo/stable/',
    title: 'PureOS',
    gpgVerify: true,
  );

  /// Igalia apps — Gobby, Linphone, WebKit SDK, Revolt.
  static const igalia = FlatpakRemoteConfig(
    url: 'https://software.igalia.com/flatpak-refs/',
    title: 'Igalia',
    gpgVerify: true,
  );

  // ── EndlessOS — GPG key must be fetched separately ──────────────────────

  /// EndlessOS apps remote (requires GPG key).
  static const endlessOsApps = FlatpakRemoteConfig(
    url: 'https://ostree.endlessm.com/ostree/eos-apps',
    title: 'EndlessOS Apps',
    gpgVerify: true,
  );

  /// EndlessOS SDK remote (requires same GPG key as [endlessOsApps]).
  static const endlessOsSdk = FlatpakRemoteConfig(
    url: 'https://ostree.endlessm.com/ostree/eos-sdk',
    title: 'EndlessOS SDK',
    gpgVerify: true,
  );

  // ── Nightly channels ────────────────────────────────────────────────────

  /// GNOME nightly — nightly builds of GNOME apps and the GNOME runtime.
  static const gnomeNightly = FlatpakRemoteConfig(
    url: 'https://nightly.gnome.org/repo/',
    title: 'GNOME Nightly',
    gpgVerify: true,
  );

  /// KDE nightly runtime — required by all KDE per-app nightly remotes.
  static const kdeRuntimeNightly = FlatpakRemoteConfig(
    url: 'https://cdn.kde.org/flatpak/kde-runtime-nightly/',
    title: 'KDE Runtime Nightly',
    gpgVerify: true,
  );

  /// KDE Dragon Player nightly.
  static const kdeDragonNightly = FlatpakRemoteConfig(
    url: 'https://cdn.kde.org/flatpak/dragon-nightly/',
    title: 'KDE Dragon Nightly',
    gpgVerify: true,
  );

  /// XWaylandVideoBridge nightly.
  static const xwaylandVideoBridgeNightly = FlatpakRemoteConfig(
    url: 'https://cdn.kde.org/flatpak/xwaylandvideobridge-nightly/',
    title: 'XWaylandVideoBridge Nightly',
    gpgVerify: true,
  );
}
