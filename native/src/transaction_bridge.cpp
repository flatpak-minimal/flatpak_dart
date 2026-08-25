// transaction_bridge.cpp — GObject signal handlers → PostCObject_DL.
//
// TransactionWorker — one per FlatpakInstallation, owns a single dedicated
// thread and a serial queue of pending transactions.

#include "transaction_bridge.h"

#include <cstring>

#include "flatpak_bridge.h"
#include "flatpak_post.h"

// ── Post helpers ────────────────────────────────────────────────────────────

namespace {

template <typename T>
void post_glaze(Dart_Port port, uint8_t discriminator, const T& value) {
    auto payload = glz::write_binary(value);
    flatpak_nc::post_framed(port, discriminator, reinterpret_cast<const uint8_t*>(payload.data()),
                            payload.size());
}

void post_sentinel(Dart_Port port) {
    const uint8_t buf[1] = {0x01};
    flatpak_nc::post_copy(port, buf, 1);
}

void post_error(Dart_Port port, const char* msg) {
    flatpak_nc::post_framed_error(port, 0x02, msg);
}

const char* op_kind_str(FlatpakTransactionOperationType type) {
    switch (type) {
        case FLATPAK_TRANSACTION_OPERATION_INSTALL:
            return "install";
        case FLATPAK_TRANSACTION_OPERATION_UPDATE:
            return "update";
        case FLATPAK_TRANSACTION_OPERATION_INSTALL_BUNDLE:
            return "install";
        case FLATPAK_TRANSACTION_OPERATION_UNINSTALL:
            return "uninstall";
        default:
            return "unknown";
    }
}

const char* safe_str(const char* s) {
    return s ? s : "";
}

}  // anonymous namespace

// ── GObject signal handlers ─────────────────────────────────────────────────

static void on_new_operation(FlatpakTransaction*, FlatpakTransactionOperation* op,
                             FlatpakTransactionProgress* prog, gpointer port_ptr) {
    auto port = *static_cast<Dart_Port*>(port_ptr);
    auto ref = std::string(safe_str(flatpak_transaction_operation_get_ref(op)));
    auto kind = std::string(op_kind_str(flatpak_transaction_operation_get_operation_type(op)));

    // Post an immediate "starting" event so Dart knows this op exists
    TransactionProgress start;
    start.op = kind;
    start.ref = ref;
    start.progress = 0;
    start.bytesTransferred = 0;
    start.bytesTotal = 0;
    start.status = "Starting";
    post_glaze(port, 0x10, start);

    auto* ctx = new ProgressCtx{
        .port = port,
        .ref = ref,
        .op_kind = kind,
    };
    // g_signal_connect_data with notify frees ctx when the signal disconnects.
    g_signal_connect_data(
        prog, "changed", G_CALLBACK(+[](FlatpakTransactionProgress* prog, gpointer ctx_ptr) {
            auto* ctx = static_cast<ProgressCtx*>(ctx_ptr);

            TransactionProgress p;
            p.op = ctx->op_kind;
            p.ref = ctx->ref;
            p.progress = flatpak_transaction_progress_get_progress(prog);
            p.bytesTransferred = flatpak_transaction_progress_get_bytes_transferred(prog);
            p.bytesTotal = 0;  // no get_bytes_total API; use p.progress (0-100%) instead
            p.status = safe_str(flatpak_transaction_progress_get_status(prog));

            post_glaze(ctx->port, 0x10, p);
        }),
        ctx, [](gpointer data, GClosure*) { delete static_cast<ProgressCtx*>(data); },
        static_cast<GConnectFlags>(0));
}

static void on_operation_done(FlatpakTransaction*, FlatpakTransactionOperation* op,
                              const char* /*commit*/, FlatpakTransactionResult /*result*/,
                              gpointer port_ptr) {
    auto port = *static_cast<Dart_Port*>(port_ptr);

    TransactionProgress done;
    done.op = op_kind_str(flatpak_transaction_operation_get_operation_type(op));
    done.ref = safe_str(flatpak_transaction_operation_get_ref(op));
    done.progress = 100;
    done.bytesTransferred = 0;
    done.bytesTotal = 0;
    done.status = "Done";
    post_glaze(port, 0x10, done);
}

static gboolean on_ready(FlatpakTransaction*, gpointer /*self*/) {
    // Return TRUE to proceed with the transaction.
    // Without this handler, flatpak_transaction_run() never starts.
    return TRUE;
}

static gboolean on_choose_remote_for_ref(FlatpakTransaction*, const char* /*for_ref*/,
                                         const char* /*runtime_ref*/, const char* const* remotes,
                                         gpointer /*self*/) {
    // Auto-select the first available remote for runtime dependencies.
    return 0;  // index 0
}

// ── TransactionWorker ───────────────────────────────────────────────────────

TransactionWorker::TransactionWorker(FlatpakInstallation* inst)
    : inst_(static_cast<FlatpakInstallation*>(g_object_ref(inst))) {
    thread_ = std::thread(&TransactionWorker::loop, this);
}

TransactionWorker::~TransactionWorker() {
    {
        std::lock_guard lk(mu_);
        stop_ = true;
    }
    cv_.notify_one();
    thread_.join();
    g_object_unref(inst_);
}

void TransactionWorker::enqueue(PendingTx item) {
    {
        std::lock_guard lk(mu_);
        queue_.push(std::move(item));
    }
    cv_.notify_one();
}

void TransactionWorker::cancel_current() {
    std::lock_guard lk(mu_);
    if (current_cancel_) {
        g_cancellable_cancel(current_cancel_);
    }
}

void TransactionWorker::loop() {
    while (true) {
        PendingTx item;
        {
            std::unique_lock lk(mu_);
            cv_.wait(lk, [&] { return stop_ || !queue_.empty(); });
            if (stop_) {
                return;
            }
            item = std::move(queue_.front());
            queue_.pop();
            current_cancel_ = item.cancel;
        }
        execute(item);
        {
            std::lock_guard lk(mu_);
            current_cancel_ = nullptr;
        }
        g_object_unref(item.cancel);
        g_object_unref(item.tx);
    }
}

void TransactionWorker::execute(const PendingTx& item) {
    g_signal_connect(item.tx, "ready", G_CALLBACK(on_ready), nullptr);
    g_signal_connect(item.tx, "new-operation", G_CALLBACK(on_new_operation),
                     const_cast<Dart_Port*>(&item.port));
    g_signal_connect(item.tx, "operation-done", G_CALLBACK(on_operation_done),
                     const_cast<Dart_Port*>(&item.port));
    g_signal_connect(item.tx, "choose-remote-for-ref", G_CALLBACK(on_choose_remote_for_ref),
                     nullptr);

    g_autoptr(GError) err = nullptr;
    const bool ok = flatpak_transaction_run(item.tx, item.cancel, &err);

    ok ? post_sentinel(item.port) : post_error(item.port, err->message);
}

// ── C ABI — worker ──────────────────────────────────────────────────────────

static FlatpakInstallation* open_installation(const char* name) {
    g_autoptr(GError) err = nullptr;
    if (g_strcmp0(name, "user") == 0) {
        return flatpak_installation_new_user(nullptr, &err);
    }
    if (g_strcmp0(name, "system") == 0) {
        return flatpak_installation_new_system(nullptr, &err);
    }
    g_autoptr(GFile) path = g_file_new_for_path(name);
    return flatpak_installation_new_for_path(path, false, nullptr, &err);
}

extern "C" {

void* flatpak_worker_create(const char* installation) {
    auto* inst = open_installation(installation);
    if (!inst) {
        return nullptr;
    }
    auto* w = new TransactionWorker(inst);
    g_object_unref(inst);
    return w;
}

void flatpak_worker_destroy(void* handle) {
    delete static_cast<TransactionWorker*>(handle);
}

void flatpak_worker_cancel_current(void* handle) {
    static_cast<TransactionWorker*>(handle)->cancel_current();
}

// ── C ABI — transaction handle ──────────────────────────────────────────────

void* flatpak_tx_create(void* worker_handle, Dart_Port port) {
    auto* worker = static_cast<TransactionWorker*>(worker_handle);

    g_autoptr(GError) err = nullptr;
    auto* tx = flatpak_transaction_new_for_installation(worker->installation(), nullptr, &err);
    if (!tx) {
        post_error(port, err ? err->message : "failed to create transaction");
        return nullptr;
    }

    auto* h = new TxHandle{
        .worker = worker,
        .tx = tx,
        .cancel = g_cancellable_new(),
        .port = port,
    };
    return h;
}

void flatpak_tx_destroy(void* handle) {
    auto* h = static_cast<TxHandle*>(handle);
    if (h->tx) {
        g_object_unref(h->tx);
    }
    if (h->cancel) {
        g_object_unref(h->cancel);
    }
    delete h;
}

void flatpak_tx_add_install(void* handle, const char* remote, const char* ref) {
    auto* h = static_cast<TxHandle*>(handle);
    if (!h->tx) {
        return;
    }
    g_autoptr(GError) err = nullptr;
    if (!flatpak_transaction_add_install(h->tx, remote, ref, nullptr, &err)) {
        post_error(h->port, err ? err->message : "add_install failed");
    }
}

void flatpak_tx_add_update(void* handle, const char* ref) {
    auto* h = static_cast<TxHandle*>(handle);
    if (!h->tx) {
        return;
    }
    g_autoptr(GError) err = nullptr;
    if (!flatpak_transaction_add_update(h->tx, ref, nullptr, nullptr, &err)) {
        post_error(h->port, err ? err->message : "add_update failed");
    }
}

void flatpak_tx_add_uninstall(void* handle, const char* ref) {
    auto* h = static_cast<TxHandle*>(handle);
    if (!h->tx) {
        return;
    }
    g_autoptr(GError) err = nullptr;
    if (!flatpak_transaction_add_uninstall(h->tx, ref, &err)) {
        post_error(h->port, err ? err->message : "add_uninstall failed");
    }
}

void flatpak_tx_add_install_bundle(void* handle, const char* bundle_path) {
    auto* h = static_cast<TxHandle*>(handle);
    if (!h->tx) {
        return;
    }
    g_autoptr(GError) err = nullptr;
    g_autoptr(GFile) file = g_file_new_for_path(bundle_path);
    if (!flatpak_transaction_add_install_bundle(h->tx, file, nullptr, &err)) {
        post_error(h->port, err ? err->message : "add_install_bundle failed");
    }
}

void flatpak_tx_submit(void* handle) {
    auto* h = static_cast<TxHandle*>(handle);
    if (!h->tx) {
        post_error(h->port, "No transaction created");
        return;
    }
    // Transfer ownership to the worker
    PendingTx ptx{
        .tx = h->tx,
        .cancel = h->cancel,
        .port = h->port,
    };
    h->tx = nullptr;  // worker owns it now
    h->cancel = nullptr;
    h->worker->enqueue(ptx);
}

}  // extern "C"
