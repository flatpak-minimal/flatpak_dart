// Whether an installed app can actually be launched here.
//
// Architecture support is necessary but not sufficient. The gate that stops a
// foreign-arch launch in practice is the runtime: installing an app does not
// install a runtime for its architecture, and libflatpak refuses the launch
// long before any emulation is attempted —
//
//     $ flatpak run --arch=aarch64 org.gnome.Calculator
//     error: runtime/org.gnome.Platform/aarch64/50 not installed
//
// Reporting *which* of the two is missing lets a caller offer the right thing:
// an architecture mismatch is terminal, a missing runtime is one download away
// (see FlatpakClient.ensureRuntime).

/// What stops an app from launching, if anything.
enum LaunchBlocker {
  /// Nothing found; the app should launch.
  none,

  /// Not installed at all, so there is nothing to inspect.
  notInstalled,

  /// Built for an architecture this machine cannot execute under the current
  /// [ArchPolicy]. Terminal — no download fixes it.
  architecture,

  /// The runtime it declares is not installed for its architecture.
  /// Recoverable: install the runtime.
  runtimeMissing,
}

/// The result of asking whether an installed app can be launched.
class AppRunnability {
  /// Application id that was checked.
  final String appId;

  /// Architecture of the installed app, empty when it is not installed.
  final String arch;

  /// Whether this machine can execute [arch] under the active policy.
  final bool archSupported;

  /// Runtime the app declares, e.g. `org.gnome.Platform/aarch64/50`.
  ///
  /// Null when the app is not installed, when its architecture already rules
  /// it out, or when its metadata declares no runtime — the last of which is
  /// malformed rather than blocking, so it is not treated as a blocker.
  final String? runtimeRef;

  /// Whether [runtimeRef] is installed. False whenever it is unknown.
  final bool runtimeInstalled;

  /// The first thing found to be wrong, or [LaunchBlocker.none].
  final LaunchBlocker blocker;

  const AppRunnability({
    required this.appId,
    required this.arch,
    required this.archSupported,
    required this.runtimeRef,
    required this.runtimeInstalled,
    required this.blocker,
  });

  /// Whether a launch is expected to succeed.
  ///
  /// "Expected", not guaranteed: for an emulated architecture this says the
  /// kernel can execute the binary and the runtime is present, which is as far
  /// as anything can be checked ahead of time. Whether qemu handles every
  /// syscall the app makes, and whether it gets working graphics, is only
  /// answerable by running it.
  bool get canLaunch => blocker == LaunchBlocker.none;

  /// Whether the obstacle can be cleared by installing something.
  bool get isRecoverable => blocker == LaunchBlocker.runtimeMissing;

  @override
  String toString() =>
      'AppRunnability($appId/$arch, canLaunch=$canLaunch, blocker=${blocker.name}'
      '${runtimeRef == null ? '' : ', runtime=$runtimeRef'})';
}

/// Builds an [AppRunnability] from what was learned about an app.
///
/// Separated from the I/O that gathers those facts so the precedence is
/// testable on its own, and stated in one place rather than implied by the
/// order of early returns at the call site:
///
/// 1. not installed — nothing else is knowable
/// 2. architecture — terminal, and its runtime is beside the point
/// 3. runtime missing — recoverable
///
/// A [runtimeRef] of null means either "not looked up" or "the app declares
/// none"; neither is a blocker, because refusing on metadata we could not read
/// would be inventing a verdict libflatpak is better placed to give.
AppRunnability resolveRunnability({
  required String appId,
  required String arch,
  required bool installed,
  required bool archSupported,
  String? runtimeRef,
  bool runtimeInstalled = false,
}) {
  if (!installed) {
    return AppRunnability(
      appId: appId,
      arch: arch,
      archSupported: archSupported,
      runtimeRef: null,
      runtimeInstalled: false,
      blocker: LaunchBlocker.notInstalled,
    );
  }
  if (!archSupported) {
    return AppRunnability(
      appId: appId,
      arch: arch,
      archSupported: false,
      runtimeRef: null,
      runtimeInstalled: false,
      blocker: LaunchBlocker.architecture,
    );
  }
  final missing = runtimeRef != null && !runtimeInstalled;
  return AppRunnability(
    appId: appId,
    arch: arch,
    archSupported: true,
    runtimeRef: runtimeRef,
    runtimeInstalled: runtimeInstalled,
    blocker: missing ? LaunchBlocker.runtimeMissing : LaunchBlocker.none,
  );
}
