/// Monitors an installation for update availability using
/// libflatpak's `FlatpakMonitor` GObject (inotify-based).
///
/// Works from any host process — no D-Bus portal, no sandbox required.
final class UpdateAvailableEvent {
  const UpdateAvailableEvent();
}

class UpdateMonitor {
  final Stream<UpdateAvailableEvent> events;
  final Future<void> Function() _close;

  const UpdateMonitor({
    required this.events,
    required Future<void> Function() close,
  }) : _close = close;

  Future<void> close() => _close();
}
