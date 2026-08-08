/// Typed Dart API for managing Flatpak applications on Linux.
///
/// Calls into the libflatpak C API through a C++23 bridge. Results are
/// delivered to Dart as binary messages whose buffers are handed to the VM
/// without a copy on send. No D-Bus client library required.
library;

export 'package:appstream_dart/appstream.dart';

export 'src/application.dart';
export 'src/appstream/catalog.dart';
export 'src/exceptions.dart';
export 'src/flatpak_client.dart';
export 'src/installation_info.dart';
export 'src/instance.dart';
export 'src/known_remotes.dart';
export 'src/permissions.dart';
export 'src/portal/permission_flow.dart';
export 'src/portal/permission_store.dart';
export 'src/remote.dart';
export 'src/remote_manager.dart';
export 'src/storage_info.dart';
export 'src/transaction.dart' hide TransactionBridge, VoidCallback;
export 'src/ffi/codec.dart' show MetadataEntry;
export 'src/update_monitor.dart';
