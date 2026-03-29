// transaction.dart
//
// FlatpakTransaction is returned immediately when the caller invokes
// install/update/uninstall. The underlying C++ operation is enqueued on the
// TransactionWorker's serial queue and does not start until the worker thread
// is free.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'exceptions.dart';
import 'ffi/bindings.dart';
import 'ffi/codec.dart';

typedef VoidCallback = void Function();

// ── FlatpakTransaction ────────────────────────────────────────────────────

/// A Flatpak transaction enqueued on the installation's serial worker.
///
/// The [progress] stream is silent while the transaction is waiting in the
/// queue. It begins emitting events once the transaction starts executing.
/// [result] completes when the transaction finishes; it throws a
/// [FlatpakTransactionException] on failure.
class FlatpakTransaction {
  final Stream<TransactionProgress> progress;
  final Future<void> result;
  final VoidCallback _cancel;

  const FlatpakTransaction({
    required this.progress,
    required this.result,
    required VoidCallback cancel,
  }) : _cancel = cancel;

  /// Request cancellation. Has no effect if the transaction has already
  /// completed.
  void cancel() => _cancel();
}

// ── TransactionProgress ───────────────────────────────────────────────────

class TransactionProgress {
  /// Operation kind: "install" | "update" | "uninstall".
  final String op;

  /// Full ref string, e.g. "app/org.gnome.Calculator/x86_64/stable".
  final String ref;

  /// 0-100. May be 0 while libflatpak fetches the remote summary.
  final int progressPercent;

  /// Bytes downloaded so far.
  final int bytesTransferred;

  /// Total download size in bytes. Zero means size is not yet known.
  final int bytesTotal;

  /// Human-readable status string from libflatpak, e.g. "Downloading".
  final String status;

  const TransactionProgress({
    required this.op,
    required this.ref,
    required this.progressPercent,
    required this.bytesTransferred,
    required this.bytesTotal,
    required this.status,
  });

  /// True once libflatpak has resolved the download size.
  bool get sizeKnown => bytesTotal > 0;

  /// Display-ready progress string.
  ///
  /// Always includes percentage (from libflatpak's `get_progress`).
  /// If [bytesTotal] is known, shows transfer ratio; otherwise just bytes.
  String get progressLabel {
    final pct = '$progressPercent%';
    if (sizeKnown) {
      return '$pct  ${_fmt(bytesTransferred)} / ${_fmt(bytesTotal)}';
    }
    if (bytesTransferred > 0) {
      return '$pct  ${_fmt(bytesTransferred)} transferred';
    }
    return '$pct';
  }

  @override
  String toString() =>
      '$op ${ref.split('/').elementAtOrNull(1) ?? ref}: '
      '$progressLabel  [$status]';

  static String _fmt(int n) => n >= 1 << 30
      ? '${(n / (1 << 30)).toStringAsFixed(1)} GiB'
      : n >= 1 << 20
          ? '${(n / (1 << 20)).toStringAsFixed(1)} MiB'
          : '${(n / 1024).toStringAsFixed(1)} KiB';
}

// ── TransactionBridge (internal) ──────────────────────────────────────────

class TransactionBridge {
  final Pointer<Void> _workerHandle;

  TransactionBridge._(this._workerHandle);

  factory TransactionBridge.create(String installation) {
    final handle = FlatpakBindings.workerCreate(installation);
    return TransactionBridge._(handle);
  }

  /// For testing.
  factory TransactionBridge.withHandle(Pointer<Void> handle) =>
      TransactionBridge._(handle);

  FlatpakTransaction _submit(void Function(Pointer<Void> txHandle) addOps) {
    final port = ReceivePort('flatpak.tx');
    final ctrl = StreamController<TransactionProgress>.broadcast();
    final done = Completer<void>();

    final txHandle =
        FlatpakBindings.txCreate(_workerHandle, port.sendPort.nativePort);

    addOps(txHandle);

    port.listen((dynamic msg) {
      if (msg is! Uint8List) return;
      switch (msg[0]) {
        case 0x10:
          final p = GlazeCodec.decodeTransactionProgress(msg, 1);
          if (!ctrl.isClosed) {
            ctrl.add(TransactionProgress(
              op: p.op,
              ref: p.ref,
              progressPercent: p.progressPercent,
              bytesTransferred: p.bytesTransferred,
              bytesTotal: p.bytesTotal,
              status: p.status,
            ));
          }
        case 0x01:
          ctrl.close();
          if (!done.isCompleted) done.complete();
          port.close();
        case 0x02:
          final err = GlazeCodec.decodeError(msg, 1);
          final ex = FlatpakTransactionException(err, ref: '');
          ctrl.addError(ex);
          if (!done.isCompleted) done.completeError(ex);
          port.close();
      }
    });

    FlatpakBindings.txSubmit(txHandle);

    return FlatpakTransaction(
      progress: ctrl.stream,
      result: done.future,
      cancel: () => FlatpakBindings.workerCancelCurrent(_workerHandle),
    );
  }

  FlatpakTransaction install(String remote, String ref) =>
      _submit((h) => FlatpakBindings.txAddInstall(h, remote, ref));

  FlatpakTransaction update(String ref) =>
      _submit((h) => FlatpakBindings.txAddUpdate(h, ref));

  FlatpakTransaction uninstall(String ref) =>
      _submit((h) => FlatpakBindings.txAddUninstall(h, ref));

  FlatpakTransaction installBundle(String path) =>
      _submit((h) => FlatpakBindings.txAddInstallBundle(h, path));

  FlatpakTransaction submitBuilder(TransactionBuilder b) => _submit((h) {
        for (final op in b._ops) {
          op(h);
        }
      });

  void close() => FlatpakBindings.workerDestroy(_workerHandle);
}

// ── TransactionBuilder ────────────────────────────────────────────────────

class TransactionBuilder {
  final List<void Function(Pointer<Void> txHandle)> _ops = [];
  final TransactionBridge _bridge;

  /// Internal constructor — use [FlatpakClient.transaction] instead.
  TransactionBuilder.internal(this._bridge);

  TransactionBuilder addInstall(String remote, String ref) {
    _ops.add((h) => FlatpakBindings.txAddInstall(h, remote, ref));
    return this;
  }

  TransactionBuilder addUpdate(String ref) {
    _ops.add((h) => FlatpakBindings.txAddUpdate(h, ref));
    return this;
  }

  TransactionBuilder addUninstall(String ref) {
    _ops.add((h) => FlatpakBindings.txAddUninstall(h, ref));
    return this;
  }

  FlatpakTransaction submit() => _bridge.submitBuilder(this);
}
