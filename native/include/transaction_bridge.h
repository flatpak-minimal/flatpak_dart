// TransactionBridge — GObject signal bridge for FlatpakTransaction.
//
// Owns one FlatpakTransaction; runs it synchronously on the worker thread.
// All GObject signals are forwarded as kExternalTypedData to dart_port.
//
// Discriminator byte at offset 0:
//   0x10 = TransactionProgress (in-flight)
//   0x01 = success sentinel
//   0x02 = error (glaze-encoded string)
#pragma once
#include <flatpak/flatpak.h>

#include <condition_variable>
#include <mutex>
#include <queue>
#include <string>
#include <thread>

#include "dart_api_dl.h"
#include "flatpak_types.h"

// ── PendingTx — one per batch of operations ──────────────────────────────

struct PendingTx {
    FlatpakTransaction* tx;  // transfer-full
    GCancellable* cancel;
    Dart_Port port;  // single port: 0x10=progress, 0x01=done, 0x02=err
};

// ── ProgressCtx — per-operation context for the progress signal ──────────
//
// Captures the ref string at on_new_operation time so the progress handler
// can include it in each TransactionProgress payload. Freed via
// GClosureNotify when the signal disconnects.

struct ProgressCtx {
    Dart_Port port;
    std::string ref;      // captured from FlatpakTransactionOperation
    std::string op_kind;  // "install" | "update" | "uninstall"
};

// ── TransactionWorker — serial queue, one per FlatpakInstallation ────────
//
// Why serial? flatpak_transaction_run() acquires an exclusive OSTree repo
// lock for the installation directory. Two concurrent calls on the same
// installation either deadlock or fail with FLATPAK_ERROR_ALREADY_RUNNING.
// The serial queue ensures each transaction runs to completion before
// the next begins.
//
// Cross-installation parallelism (user vs system) is fine: they have
// separate OSTree repos and separate TransactionWorkers.

class TransactionWorker {
   public:
    explicit TransactionWorker(FlatpakInstallation* inst);
    ~TransactionWorker();

    // Enqueue a transaction; returns immediately.
    // Ownership of tx and cancel transfers to the worker.
    void enqueue(PendingTx item);

    // Signal the currently-executing transaction to cancel.
    void cancel_current();

    // Access the installation (needed to create FlatpakTransaction objects).
    [[nodiscard]] FlatpakInstallation* installation() const {
        return inst_;
    }

   private:
    void loop();
    void execute(const PendingTx& item);

    FlatpakInstallation* inst_;
    std::thread thread_;
    std::mutex mu_;
    std::condition_variable cv_;
    std::queue<PendingTx> queue_;
    GCancellable* current_cancel_{nullptr};
    bool stop_{false};
};

// ── TxHandle — accumulates operations before submit ──────────────────────

struct TxHandle {
    TransactionWorker* worker;
    FlatpakTransaction* tx;
    GCancellable* cancel;
    Dart_Port port;
};
