/// Typed Dart API for managing Flatpak applications on Linux.
///
/// Uses native_comms + libflatpak C API for zero-copy integration.
/// No D-Bus client library required.
library flatpak_dart;

export 'src/application.dart';
export 'src/exceptions.dart';
export 'src/flatpak_client.dart';
export 'src/known_remotes.dart';
export 'src/permissions.dart';
export 'src/remote.dart';
export 'src/remote_manager.dart';
export 'src/transaction.dart' hide TransactionBridge, VoidCallback;
export 'src/update_monitor.dart';
