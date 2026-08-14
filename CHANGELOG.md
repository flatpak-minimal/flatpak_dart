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