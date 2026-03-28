/// Base class for all flatpak_dart exceptions.
sealed class FlatpakException implements Exception {
  final String message;
  const FlatpakException(this.message);
  @override
  String toString() => '${runtimeType}: $message';
}

/// The operation failed due to insufficient polkit authorization.
final class FlatpakPermissionException extends FlatpakException {
  const FlatpakPermissionException(super.message);
}

/// The libflatpak system installation is unavailable or the polkit agent
/// rejected the authorization request.
final class FlatpakServiceUnavailableException extends FlatpakException {
  const FlatpakServiceUnavailableException(super.message);
}

/// An in-progress transaction failed.
final class FlatpakTransactionException extends FlatpakException {
  final String ref;

  /// True when another process currently holds the OSTree repo lock.
  /// Typically means GNOME Software, the flatpak CLI, or another
  /// flatpak_dart client is already running a transaction.
  bool get isAlreadyRunning =>
      message.contains('already running') ||
      message.contains('FLATPAK_ERROR_ALREADY_RUNNING');

  /// True when the caller cancelled via FlatpakTransaction.cancel().
  bool get isCancelled => message.contains('Operation was cancelled');

  const FlatpakTransactionException(super.message, {required this.ref});
}

/// The requested application or runtime was not found.
final class FlatpakNotFoundException extends FlatpakException {
  const FlatpakNotFoundException(super.message);
}

/// A remote management operation failed.
final class FlatpakRemoteException extends FlatpakException {
  const FlatpakRemoteException(super.message);
}
