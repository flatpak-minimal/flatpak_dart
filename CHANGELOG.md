## 0.1.0

- Initial release.
- Typed Dart API for Flatpak management via libflatpak C API.
- Installation reader: list apps, list remotes, remote info, remote refs, app info, permissions, check updates, fetch remote metadata.
- Transaction bridge: install, update, uninstall, bundle install with progress streaming and cancellation via serial worker queue.
- Remote management: add, modify, remove, enable, disable, update summary, subset filtering.
- Update monitor: inotify-based change detection with state-diffing (no duplicate events).
- Known remotes catalog: Flathub (all subsets), Flathub Beta, Fedora, elementary, PureOS, Igalia, EndlessOS, GNOME Nightly, KDE Nightly.
- BEVE-Lite binary codec via glaze_meta.h (C++23, no external dependencies).
- CLI examples: list_apps, install_app, uninstall_app, update_all, watch_updates, manage_remotes.
- Flutter desktop example: two-pane remote manager with package browser and permissions dialog.