// test_transaction_bridge.cpp — Tests for TransactionWorker serial queue
// and cancellation. Uses mock constructs since real FlatpakTransaction
// requires a running Flatpak installation.

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

#include "transaction_bridge.h"

using namespace std::chrono_literals;

// ── Helper: create a user installation for testing ──────────────────────────

static FlatpakInstallation* test_installation() {
    g_autoptr(GError) err = nullptr;
    return flatpak_installation_new_user(nullptr, &err);
}

// ── TransactionWorker lifecycle ─────────────────────────────────────────────

TEST(TransactionWorker, CreateAndDestroyCleanly) {
    auto* inst = test_installation();
    if (!inst) {
        GTEST_SKIP() << "No user Flatpak installation available";
    }
    {
        TransactionWorker worker(inst);
        // Destructor joins the thread — should not hang
    }
    g_object_unref(inst);
}

TEST(TransactionWorker, CancelCurrentOnEmptyQueueDoesNotCrash) {
    auto* inst = test_installation();
    if (!inst) {
        GTEST_SKIP() << "No user Flatpak installation available";
    }
    {
        TransactionWorker worker(inst);
        worker.cancel_current();  // no current tx — should be a no-op
    }
    g_object_unref(inst);
}

// ── PendingTx struct ────────────────────────────────────────────────────────

TEST(PendingTx, CanBeDefaultConstructed) {
    PendingTx ptx{};
    EXPECT_EQ(ptx.tx, nullptr);
    EXPECT_EQ(ptx.cancel, nullptr);
    EXPECT_EQ(ptx.port, 0);
}

// ── ProgressCtx struct ──────────────────────────────────────────────────────

TEST(ProgressCtx, CapturesRefAndOpKind) {
    ProgressCtx ctx{
        .port = 42,
        .ref = "app/org.gnome.Calculator/x86_64/stable",
        .op_kind = "install",
    };
    EXPECT_EQ(ctx.port, 42);
    EXPECT_EQ(ctx.ref, "app/org.gnome.Calculator/x86_64/stable");
    EXPECT_EQ(ctx.op_kind, "install");
}

TEST(ProgressCtx, EmptyRefIsValid) {
    ProgressCtx ctx{
        .port = 0,
        .ref = "",
        .op_kind = "update",
    };
    EXPECT_TRUE(ctx.ref.empty());
    EXPECT_EQ(ctx.op_kind, "update");
}

// ── TxHandle struct ─────────────────────────────────────────────────────────

TEST(TxHandle, CanBeConstructedWithNulls) {
    TxHandle h{
        .worker = nullptr,
        .tx = nullptr,
        .cancel = nullptr,
        .port = 0,
    };
    EXPECT_EQ(h.worker, nullptr);
    EXPECT_EQ(h.tx, nullptr);
}

// ── TransactionProgress glaze roundtrip ─────────────────────────────────────

TEST(TransactionProgress, GlazeRoundtrip) {
    TransactionProgress orig;
    orig.op = "install";
    orig.ref = "app/org.gnome.Calculator/x86_64/stable";
    orig.progress = 75;
    orig.bytesTransferred = 50 * 1024 * 1024;
    orig.bytesTotal = 71 * 1024 * 1024;
    orig.status = "Downloading";

    std::vector<uint8_t> buf;
    glz::write_binary(orig, buf);

    TransactionProgress decoded;
    glz::read_binary(decoded, buf);

    EXPECT_EQ(decoded.op, "install");
    EXPECT_EQ(decoded.ref, orig.ref);
    EXPECT_EQ(decoded.progress, 75u);
    EXPECT_EQ(decoded.bytesTransferred, orig.bytesTransferred);
    EXPECT_EQ(decoded.status, "Downloading");
}

TEST(TransactionProgress, ZeroBytesTotalPhase) {
    TransactionProgress p;
    p.op = "install";
    p.ref = "app/org.gnome.Calculator/x86_64/stable";
    p.progress = 0;
    p.bytesTransferred = 10 * 1024 * 1024;
    p.bytesTotal = 0;
    p.status = "Downloading";

    std::vector<uint8_t> buf;
    glz::write_binary(p, buf);

    TransactionProgress decoded;
    glz::read_binary(decoded, buf);

    EXPECT_EQ(decoded.bytesTotal, 0u);
    EXPECT_EQ(decoded.bytesTransferred, p.bytesTransferred);
}
