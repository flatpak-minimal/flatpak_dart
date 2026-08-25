// test_types.cpp — glaze roundtrip tests for every struct in flatpak_types.h.

#include <gtest/gtest.h>

#include "flatpak_types.h"

TEST(FpRef, RoundtripBasic) {
    FpRef orig;
    orig.kind = "app";
    orig.name = "org.gnome.Calculator";
    orig.arch = "x86_64";
    orig.branch = "stable";
    orig.commit = "abc123";
    orig.collectionId = "org.flathub.Stable";

    std::vector<uint8_t> buf;
    buf = glz::write_binary(orig);

    FpRef decoded;
    glz::read_binary(buf, decoded);

    EXPECT_EQ(decoded.kind, orig.kind);
    EXPECT_EQ(decoded.name, orig.name);
    EXPECT_EQ(decoded.arch, orig.arch);
    EXPECT_EQ(decoded.branch, orig.branch);
    EXPECT_EQ(decoded.commit, orig.commit);
    EXPECT_EQ(decoded.collectionId, orig.collectionId);
}

TEST(FpRef, EmptyFields) {
    FpRef orig;
    std::vector<uint8_t> buf;
    buf = glz::write_binary(orig);

    FpRef decoded;
    glz::read_binary(buf, decoded);

    EXPECT_TRUE(decoded.kind.empty());
    EXPECT_TRUE(decoded.name.empty());
}

TEST(InstalledApp, RoundtripFull) {
    InstalledApp orig;
    orig.ref.kind = "app";
    orig.ref.name = "org.gnome.Calculator";
    orig.ref.arch = "x86_64";
    orig.ref.branch = "stable";
    orig.origin = "flathub";
    orig.latestCommit = "deadbeef";
    orig.installedPath = "/var/lib/flatpak/app/org.gnome.Calculator";
    orig.installedSize = 1024 * 1024 * 50;
    orig.isCurrentArch = true;
    orig.endOfLife = false;
    orig.appDataName = "Calculator";
    orig.appDataSummary = "Perform arithmetic";
    orig.appDataVersion = "45.0";
    orig.appDataIcon = "org.gnome.Calculator";

    std::vector<uint8_t> buf;
    buf = glz::write_binary(orig);

    InstalledApp decoded;
    glz::read_binary(buf, decoded);

    EXPECT_EQ(decoded.ref.name, orig.ref.name);
    EXPECT_EQ(decoded.origin, orig.origin);
    EXPECT_EQ(decoded.installedSize, orig.installedSize);
    EXPECT_EQ(decoded.isCurrentArch, orig.isCurrentArch);
    EXPECT_EQ(decoded.endOfLife, orig.endOfLife);
    EXPECT_EQ(decoded.appDataName, orig.appDataName);
    EXPECT_EQ(decoded.appDataVersion, orig.appDataVersion);
}

TEST(TransactionProgress, RoundtripBasic) {
    TransactionProgress orig;
    orig.op = "install";
    orig.ref = "app/org.gnome.Calculator/x86_64/stable";
    orig.progress = 45;
    orig.bytesTransferred = 32 * 1024 * 1024;
    orig.bytesTotal = 71 * 1024 * 1024;
    orig.status = "Downloading";

    std::vector<uint8_t> buf;
    buf = glz::write_binary(orig);

    TransactionProgress decoded;
    glz::read_binary(buf, decoded);

    EXPECT_EQ(decoded.op, orig.op);
    EXPECT_EQ(decoded.ref, orig.ref);
    EXPECT_EQ(decoded.progress, orig.progress);
    EXPECT_EQ(decoded.bytesTransferred, orig.bytesTransferred);
    EXPECT_EQ(decoded.bytesTotal, orig.bytesTotal);
    EXPECT_EQ(decoded.status, orig.status);
}

TEST(FpInstance, RoundtripFull) {
    FpInstance orig;
    orig.appId = "org.gnome.Calculator";
    orig.instanceId = "42";
    orig.arch = "x86_64";
    orig.branch = "stable";
    orig.commit = "deadbeef";
    orig.pid = 1234;
    orig.childPid = 1240;
    orig.isRunning = true;

    std::vector<uint8_t> buf;
    buf = glz::write_binary(orig);

    FpInstance decoded;
    glz::read_binary(buf, decoded);

    EXPECT_EQ(decoded.appId, orig.appId);
    EXPECT_EQ(decoded.instanceId, orig.instanceId);
    EXPECT_EQ(decoded.arch, orig.arch);
    EXPECT_EQ(decoded.branch, orig.branch);
    EXPECT_EQ(decoded.commit, orig.commit);
    EXPECT_EQ(decoded.pid, orig.pid);
    EXPECT_EQ(decoded.childPid, orig.childPid);
    EXPECT_EQ(decoded.isRunning, orig.isRunning);
}

TEST(TransactionProgress, ZeroBytesTotal) {
    TransactionProgress orig;
    orig.op = "install";
    orig.ref = "app/org.gnome.Calculator/x86_64/stable";
    orig.progress = 0;
    orig.bytesTransferred = 10 * 1024 * 1024;
    orig.bytesTotal = 0;
    orig.status = "Downloading";

    std::vector<uint8_t> buf;
    buf = glz::write_binary(orig);

    TransactionProgress decoded;
    glz::read_binary(buf, decoded);

    EXPECT_EQ(decoded.bytesTotal, 0u);
    EXPECT_EQ(decoded.bytesTransferred, orig.bytesTransferred);
}
