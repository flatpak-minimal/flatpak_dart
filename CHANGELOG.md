## 0.3.0

- Filter AppStream catalogs to architectures this machine can actually run.
  `ArchPolicy` selects how far to look: `native` (the host architecture alone),
  `compatible` (the default — the host plus what it runs natively, mirroring
  `flatpak_get_supported_arches()`), or `emulated`.

  Emulation is detected, not configured. `kernelExecutableArches()` reads
  binfmt_misc for registrations that are enabled, carry the `F` flag (without
  which the interpreter is unreachable inside the sandbox) and whose
  interpreter still exists. That alone is never enough to surface an
  architecture: a machine with `qemu-user-static` registers ~31 of them while a
  remote may publish apps for one, so `usableArches()` reports only
  architectures that are both runnable *and* have a downloaded catalog. The
  host architecture always outranks an emulated one.

  The policy applies to installed apps too. Flatpak installs an app for any
  architecture on request — `flatpak install --arch=aarch64` succeeds on an
  x86_64 host — and the result is installed but unrunnable, so
  `listApplications()` now hides it. Pass `allArches: true` for a UI that would
  rather label than hide, and use `canRunArch()` to do the labelling.

  Emulation support is cached, because a list view asks per row and a scan
  costs about a millisecond on a machine with `qemu-user-static` installed.
  There is no automatic invalidation: binfmt_misc does not bump its directory
  mtime when a registration is added, and disabling a handler in place changes
  neither that nor the entry count — which is exactly the case that matters. So
  the cache has a bounded staleness window and an explicit
  `refreshArchSupport()` for callers that know an emulator was installed,
  removed or toggled.

  `checkRunnable()` answers the whole question rather than just the
  architecture half. Architecture support is necessary but not sufficient: a
  foreign-arch launch is stopped by the missing runtime for that architecture,
  before emulation is ever reached, and installing an app does not bring one
  along. It reports which of the two is missing, so a caller can tell a
  terminal problem from one `ensureRuntime()` fixes. It costs two native calls
  and is deliberately not folded into `listApplications()`, which filters on
  architecture alone — pure and free.

  This also fixes catalog selection picking the alphabetically first
  architecture directory when the host's own was absent, which could serve
  x86_64 apps on an aarch64 machine.

- Add AppStream catalog support. `FlatpakClient.appStream` locates a remote's
  downloaded catalog, refreshes it through
  `flatpak_installation_update_appstream_sync()`, and resolves full component
  metadata — icons, screenshots, releases, categories — via `appstream_dart`.
  `installedIconPath()` resolves an installed app's on-disk icon with no
  catalog at all, from that one app's deploy directory rather than by
  enumerating the installation. The refresh is a network pull of the whole catalog, so it
  runs on its own serial thread rather than on the calling isolate, and
  concurrent lookups of one catalog share a single build.
- Add an xdg-desktop-portal PermissionStore client.
  `FlatpakClient.permissionsStore` reads and writes per-app permission
  decisions (devices, location, notifications, background), and
  `FlatpakClient.permissionFlow` drives launch-time prompts, persisting each
  answer. `launchWithPermissions()` combines the two and reports the resolved
  status of every permission alongside the launched instance.
- Add system introspection: `getVersion()`, `getDefaultArch()`,
  `getSupportedArches()`, `listSystemInstallations()`, `getSystemStorage()`,
  `ensureRuntime()` and `installExtensions()`. `getSystemStorage()` reports
  unreadable `df` output as `FlatpakRemoteException`, so callers catching
  `FlatpakException` see every failure mode of the call.
- Add `waylandOnly` to remote app listing, filtering to refs that request the
  wayland socket.
- Delegate app lifecycle to the host when running inside a Flatpak sandbox.
  `launch()`, `stop()` and `listRunning()` route through
  `flatpak-spawn --host` there, because bwrap and the instance directory are
  not reachable from inside a sandbox. Requires
  `--talk-name=org.freedesktop.Flatpak` in the caller's finish-args. App ids
  are passed after a `--` terminator so one cannot present itself as an option
  to a command running on the host. A delegated launch returns as soon as the
  app registers an instance, or as soon as the run fails — only a launch that
  does neither waits out the settle window.
- Honour an explicit `arch` when no branch is given. Resolving an installed app
  through `flatpak_installation_get_current_installed_app()` silently dropped
  the arch and returned the host-arch ref instead.
- Skip `subdirectories=true` extension points in `installExtensions()`. Their
  installable refs are `<point>.<suffix>`, enumerated from the remote, so the
  bare extension point resolved nowhere. `versions=` is now honoured alongside
  `version=`.
- Batch APIs for list-shaped work: `appStream.componentDetails()` resolves
  metadata for many apps reusing one open catalog, and
  `appStream.installedIconPaths()` resolves icons from a single enumeration.
  The single-app forms delegate to them.
- Cache AppStream catalogs under `XDG_CACHE_HOME/flatpak_dart` instead of a
  shared temp directory, keyed by a hash of the installation path. The
  directory is verified to be a non-symlink owned only by the current user at
  0700; when it cannot be (no `HOME`, or the path belongs to someone else) the
  cache falls back to a private `mkdtemp` directory rather than to a
  predictable one another local user could pre-create.
  `FlatpakClient.close()` releases the open catalog handles.
- Reap launched sandboxes from one multiplexed thread rather than one thread
  per running app.
- New dependencies: `appstream_dart` and `dbus`. `appstream_dart` builds
  against SQLite, so `sqlite-devel` / `libsqlite3-dev` joins the
  prerequisites.

## 0.2.0

- Add app lifecycle control. `FlatpakClient.launch()` starts an installed
  application in its sandbox and returns the `FlatpakInstance` libflatpak
  created for it, so callers get the instance id and pids without polling.
  `FlatpakClient.stop()` terminates every running instance of an app id, and
  `FlatpakClient.listRunning()` lists running sandbox instances. Note that
  flatpak instances are not scoped to an installation: `stop()` and
  `listRunning()` both work host-wide, matching instances launched from the
  user and system installations alike.
- Launches run `flatpak_installation_launch_full()` with
  `FLATPAK_LAUNCH_FLAGS_DO_NOT_REAP` on a dedicated serial thread, so spawning
  a sandbox never blocks the calling isolate. The launched process is reaped in
  the background rather than left as a zombie.
- `stop()` sends SIGTERM to the sandboxed app process and escalates to SIGKILL
  after a 1.5 second grace period. Signalling goes through a pidfd where the
  kernel supports it, which pins the exact process rather than a pid that may
  have been recycled; process identity is verified against
  `/proc/<pid>/stat` start time either way.
- Add `FlatpakStopException`, thrown when running instances were matched but
  none could be signalled. This is distinct from `FlatpakNotFoundException`,
  which means nothing matched at all — previously the two were conflated and a
  running app could be reported as not running.
- The build hook accepts a `skip_native_build` user-define, for build systems
  such as Yocto that cross-compile the native library out of band, and a
  `clear_ambient_flags` user-define that drops inherited `CFLAGS`/`CXXFLAGS`/
  `LDFLAGS` from a polluted host environment. The hook now uses Ninja when it
  is available and no longer pins clang, so the native library is built with
  the same toolchain as the target's libflatpak and their C++ runtimes match at
  load time.

## 0.1.2

- Widen the `hooks` and `code_assets` constraints to `>=0.20.1 <3.0.0` and
  `>=0.19.7 <2.0.0`. Pinning them to the 2.x and 1.x majors made the package
  unresolvable for any Flutter SDK that pins `meta 1.18.0`, because `hooks`
  2.x requires `meta ^1.19.0`. Both are used only by `hook/build.dart`, which
  is source compatible across the two API generations, so pub is free to pick
  whichever the surrounding SDK allows.
- Align the Flutter example's SDK constraint with the package's `>=3.10.0`.

## 0.1.1

- Fix the native library failing to load on a fresh install. The build hook
  emitted the library as a code asset, but the loader opened it by plain
  filename, which never consults the asset table. FFI bindings are now
  `@Native` declarations bound to the asset id, so `dart pub add flatpak_dart`
  works with no manual build and no `FLATPAK_NC_LIB`.
- Hand framed result buffers to the VM with `kExternalTypedData` instead of
  copying them with `kTypedData`. One-byte sentinels still copy, which is
  cheaper than a heap allocation plus finalizer.
- Correct the library and bridge header documentation, which described the
  message path as zero-copy before it was.
- Remove `FLATPAK_NC_LIB` and the library search paths. The build hook is now
  the only source of the library for `dart run` and `flutter run`.

## 0.1.0

- Initial release.
- Requires Dart SDK 3.10.0 or newer, and Linux with libflatpak installed.
- Typed Dart API for Flatpak management via libflatpak C API.
- Installation reader: list apps, list remotes, remote info, remote refs, app info, permissions, check updates, fetch remote metadata.
- Transaction bridge: install, update, uninstall, bundle install with progress streaming and cancellation via serial worker queue.
- Remote management: add, modify, remove, enable, disable, update summary, subset filtering.
- Update monitor: inotify-based change detection with state-diffing (no duplicate events).
- Known remotes catalog: Flathub (all subsets), Flathub Beta, Fedora, elementary, PureOS, Igalia, EndlessOS, GNOME Nightly, KDE Nightly.
- BEVE-Lite binary codec via glaze_meta.h (C++23, no external dependencies).
- CLI examples: list_apps, install_app, uninstall_app, update_all, watch_updates, manage_remotes.
- Flutter desktop example: two-pane remote manager with package browser and permissions dialog.