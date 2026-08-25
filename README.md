# flatpak_dart

Typed Dart API for managing Flatpak applications on Linux. Drives
**libflatpak** directly via a C++23 FFI bridge — no D-Bus client library,
no subprocess spawning, no text parsing.

## Features

| Feature | API |
|---------|-----|
| List installed apps | `client.listApplications()` |
| App details | `client.info(appId)` |
| Install / update / uninstall | `client.install()`, `.update()`, `.uninstall()` |
| Transaction progress | `tx.progress` stream (percentage, bytes, status) |
| Batch transactions | `client.transaction()..addInstall()..addUpdate()` |
| Remote CRUD | `client.remotes.add()`, `.modify()`, `.remove()` |
| Remote browsing | `client.remotes.listApps(name)` stream |
| Subset filtering | `client.remotes.modifySubset(name, RemoteSubset.verified)` |
| Pre-install permissions | `client.fetchRemoteMetadata(remote, ref)` |
| Update monitoring | `client.watchUpdates()` (inotify, state-diffed) |
| Installed app icons | `client.appStream.installedIconPath(appId)` |
| AppStream metadata | `client.appStream.componentDetail(appId)` (icons, screenshots, releases) |
| Catalog refresh | `client.appStream.refresh(remote)` |
| Portal permissions | `client.permissionsStore.check(appId, perms)`, `.set()`, `.removeAllForApp()` |
| Launch permission prompts | `client.launchWithPermissions(appId)`, `client.permissionFlow.requests` |
| Known remotes catalog | `KnownRemotes.flathub`, `.fedora`, `.gnomeNightly`, etc. |

## Architecture

```
Dart isolate
  |  FFI call (< 1 us)
  v
C++23 bridge (libflatpak C API)
  |  flatpak_installation_*()  — reads
  |  flatpak_transaction_run() — writes (serial worker queue)
  |  GFileMonitor              — update watch (inotify)
  v
Results posted to Dart via Dart_PostCObject_DL (kTypedData)
Payloads encoded with BEVE-Lite binary codec (glaze_meta.h)
```

## Prerequisites

```bash
# Fedora
sudo dnf install flatpak-devel glib2-devel sqlite-devel \
    cmake ninja-build clang

# Ubuntu / Debian
sudo apt install libflatpak-dev libglib2.0-dev libsqlite3-dev \
    cmake ninja-build clang-19
```

`sqlite-devel` / `libsqlite3-dev` is required by the `appstream_dart`
dependency, whose build hook compiles against `sqlite3.h`. The remaining
packages are for this package's own native bridge.

## Building

There is **no manual build step**. The native library (`libflatpak_nc.so`) is
compiled automatically by the package's build hook the first time you run tests,
run an example, or build a Flutter app — and resolved automatically at runtime
(no environment variables).

Add the package and run. The native library is built automatically by the
build hook the first time you run, so there is nothing to compile by hand:

```bash
dart pub add flatpak_dart
dart run example/example.dart
```

Working on the package itself:

```bash
git clone https://github.com/flatpak-minimal/flatpak_dart.git
cd flatpak_dart
dart pub get
dart run example/example.dart
```

In a Flutter app, just add the dependency — `flutter run -d linux` /
`flutter build linux` build and bundle the native library for you:

```yaml
dependencies:
  flatpak_dart: ^0.1.0
```

<details>
<summary>Manual native build (only for C++ work or CI)</summary>

```bash
./scripts/build_release.sh                    # → build-release/libflatpak_nc.so
# explicit toolchain:
CC=clang-19 CXX=clang++-19 ./scripts/build_release.sh
```

The hook always uses the system default compiler (matching the host's
`libflatpak`). For a manual build, avoid forcing a `-stdlib=libc++` toolchain —
mixing C++ runtimes with the system libraries aborts at load time.
</details>

## Usage

```dart
import 'package:flatpak_dart/flatpak_dart.dart';

void main() async {
  final client = FlatpakClient.user();

  // List installed apps
  for (final app in await client.listApplications()) {
    print('${app.ref.name} ${app.appDataVersion}');
  }

  // Install with progress
  final tx = client.install('flathub', 'app/org.gnome.Calculator/x86_64/stable');
  await for (final p in tx.progress) {
    print('${p.progressPercent}% ${p.progressLabel}');
  }
  await tx.result;

  // Pre-install permissions check
  final perms = await client.fetchRemoteMetadata(
      'flathub', 'app/org.gnome.Calculator/x86_64/stable');
  for (final e in perms.where((e) => e.section == 'Context')) {
    print('${e.key}: ${e.value}');
  }

  // Watch for changes (inotify)
  final monitor = client.watchUpdates();
  await for (final _ in monitor.events) {
    print('Installation changed!');
  }

  await client.close();
}
```

## Remote management

```dart
final client = FlatpakClient.user();

// Add from known catalog
await client.remotes.add('flathub', KnownRemotes.flathub);
await client.remotes.add('flathub-floss', KnownRemotes.flathubFloss);

// Browse remote packages
await for (final ref in client.remotes.listApps('flathub')) {
  print('${ref.name}/${ref.arch}/${ref.branch}');
}

// Enable / disable
await client.remotes.disable('flathub-floss');
await client.remotes.enable('flathub-floss');

// Remove
await client.remotes.remove('flathub-floss');
```

## Transaction concurrency

Transactions on the same installation are serialized by an internal worker
queue (OSTree holds an exclusive repo lock). User and system installations
have independent queues and run in parallel.

```dart
final user   = FlatpakClient.user();
final system = FlatpakClient.system();

// These run in parallel (different repo locks)
await Future.wait([
  user.install('flathub', 'app/org.gnome.Calculator/x86_64/stable').result,
  system.install('flathub', 'app/org.gnome.Maps/x86_64/stable').result,
]);
```

## Known remotes

| Constant | Remote | Notes |
|----------|--------|-------|
| `KnownRemotes.flathub` | Flathub | Default, collection `org.flathub.Stable` |
| `KnownRemotes.flathubVerified` | Flathub | `--subset=verified` |
| `KnownRemotes.flathubFloss` | Flathub | `--subset=floss` |
| `KnownRemotes.flathubVerifiedFloss` | Flathub | `--subset=verified_floss` |
| `KnownRemotes.flathubBeta` | Flathub Beta | Pre-release channel |
| `KnownRemotes.fedora` | Fedora | OCI format (`oci+https://`) |
| `KnownRemotes.elementaryOs` | elementary | AppCenter |
| `KnownRemotes.gnomeNightly` | GNOME Nightly | Nightly builds |
| `KnownRemotes.kdeRuntimeNightly` | KDE Nightly | KDE runtime |

## Developer scripts

```bash
./scripts/asan.sh          # AddressSanitizer + UBSan
./scripts/clang_tidy.sh    # clang-tidy
./scripts/coverage.sh      # coverage report
```

These scripts build into their own directories for sanitizer and coverage
runs. They do not affect `dart run`, which always uses the library produced
by the build hook.

## Flutter example

A full Flutter Linux desktop app is included in `example/flutter_remote_manager/`:

```bash
cd example/flutter_remote_manager
flutter pub get
flutter run -d linux
```

## Platform support

| Platform | Support |
|----------|---------|
| Linux (x86_64, aarch64) | Full |
| macOS / Windows | Not supported (Flatpak is Linux-only) |

Requires libflatpak >= 1.12 and Flatpak installed on the host.

## License

MIT. See [LICENSE](LICENSE).

Vendored headers are under their respective licenses.
See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).