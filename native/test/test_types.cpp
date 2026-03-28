// test_types.cpp — glaze roundtrip tests for every struct in flatpak_types.h.

#include <gtest/gtest.h>

#include "flatpak_types.h"

TEST(FlatpakRef, RoundtripBasic) {
    FlatpakRef orig;
    orig.kind = "app";
    orig.name = "org.gnome.Calculator";
    orig.arch = "x86_64";
    orig.branch = "stable";
    orig.commit = "abc123";
    orig.collectionId = "org.flathub.Stable";

    std::vector<uint8_t> buf;
    glz::write_binary(orig, buf);

    FlatpakRef decoded;
    glz::read_binary(decoded, buf);

    EXPECT_EQ(decoded.kind, orig.kind);
    EXPECT_EQ(decoded.name, orig.name);
    EXPECT_EQ(decoded.arch, orig.arch);
    EXPECT_EQ(decoded.branch, orig.branch);
    EXPECT_EQ(decoded.commit, orig.commit);
    EXPECT_EQ(decoded.collectionId, orig.collectionId);
}

TEST(FlatpakRef, EmptyFields) {
    FlatpakRef orig;
    std::vector<uint8_t> buf;
    glz::write_binary(orig, buf);

    FlatpakRef decoded;
    glz::read_binary(decoded, buf);

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
    glz::write_binary(orig, buf);

    InstalledApp decoded;
    glz::read_binary(decoded, buf);

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
    glz::write_binary(orig, buf);

    TransactionProgress decoded;
    glz::read_binary(decoded, buf);

    EXPECT_EQ(decoded.op, orig.op);
    EXPECT_EQ(decoded.ref, orig.ref);
    EXPECT_EQ(decoded.progress, orig.progress);
    EXPECT_EQ(decoded.bytesTransferred, orig.bytesTransferred);
    EXPECT_EQ(decoded.bytesTotal, orig.bytesTotal);
    EXPECT_EQ(decoded.status, orig.status);
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
    glz::write_binary(orig, buf);

    TransactionProgress decoded;
    glz::read_binary(decoded, buf);

    EXPECT_EQ(decoded.bytesTotal, 0u);
    EXPECT_EQ(decoded.bytesTransferred, orig.bytesTransferred);
}
