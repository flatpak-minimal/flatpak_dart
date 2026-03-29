// test_transaction_bridge.cpp — Tests for transaction types and glaze
// roundtrip. TransactionWorker lifecycle tests require exported symbols
// and are covered by integration tests instead.

#include <gtest/gtest.h>

#include <vector>

#include "flatpak_types.h"
#include "transaction_bridge.h"

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

    auto buf = glz::write_binary(orig);

    TransactionProgress decoded;
    glz::read_binary(buf, decoded);

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

    auto buf = glz::write_binary(p);

    TransactionProgress decoded;
    glz::read_binary(buf, decoded);

    EXPECT_EQ(decoded.bytesTotal, 0u);
    EXPECT_EQ(decoded.bytesTransferred, p.bytesTransferred);
}
