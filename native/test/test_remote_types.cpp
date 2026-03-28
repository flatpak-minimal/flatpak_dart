// test_remote_types.cpp — verifies RemoteConfig and expanded FlatpakRemoteInfo
// encode/decode correctly through the glaze binary codec.

#include <gtest/gtest.h>

#include "flatpak_types.h"

TEST(RemoteConfig, RoundtripBasic) {
    RemoteConfig orig;
    orig.url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    orig.title = "Flathub";
    orig.collectionId = "org.flathub.Stable";
    orig.gpgVerify = 1;
    orig.priority = 1;

    std::vector<uint8_t> buf;
    glz::write_binary(orig, buf);

    RemoteConfig decoded;
    glz::read_binary(decoded, buf);

    EXPECT_EQ(decoded.url, orig.url);
    EXPECT_EQ(decoded.title, orig.title);
    EXPECT_EQ(decoded.collectionId, orig.collectionId);
    EXPECT_EQ(decoded.gpgVerify, orig.gpgVerify);
    EXPECT_EQ(decoded.priority, orig.priority);
}

TEST(RemoteConfig, SubsetEncodes) {
    RemoteConfig cfg;
    cfg.subset = "verified_floss";
    std::vector<uint8_t> buf;
    glz::write_binary(cfg, buf);
    RemoteConfig out;
    glz::read_binary(out, buf);
    EXPECT_EQ(out.subset, "verified_floss");
}

TEST(RemoteConfig, SentinelValuesPreserved) {
    RemoteConfig cfg;  // all sentinels
    std::vector<uint8_t> buf;
    glz::write_binary(cfg, buf);
    RemoteConfig out;
    glz::read_binary(out, buf);
    EXPECT_EQ(out.priority, -1);
    EXPECT_EQ(out.gpgVerify, -1);
    EXPECT_EQ(out.disabled, -1);
    EXPECT_EQ(out.noDeps, -1);
}

TEST(RemoteConfig, GpgKeyDataBytes) {
    RemoteConfig cfg;
    cfg.gpgKeyData = {0xDE, 0xAD, 0xBE, 0xEF};
    std::vector<uint8_t> buf;
    glz::write_binary(cfg, buf);
    RemoteConfig out;
    glz::read_binary(out, buf);
    EXPECT_EQ(out.gpgKeyData, cfg.gpgKeyData);
}

TEST(FlatpakRemoteInfo, SubsetAndCollectionId) {
    FlatpakRemoteInfo info;
    info.name = "flathub-floss";
    info.url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    info.subset = "floss";
    info.collectionId = "";
    info.remoteType = 0;  // user
    info.gpgVerify = true;

    std::vector<uint8_t> buf;
    glz::write_binary(info, buf);
    FlatpakRemoteInfo out;
    glz::read_binary(out, buf);

    EXPECT_EQ(out.subset, "floss");
    EXPECT_EQ(out.remoteType, 0);
    EXPECT_EQ(out.gpgVerify, true);
}

TEST(FlatpakRemoteInfo, OciRemote) {
    FlatpakRemoteInfo info;
    info.name = "fedora";
    info.url = "oci+https://registry.fedoraproject.org";
    info.remoteType = 2;  // static
    std::vector<uint8_t> buf;
    glz::write_binary(info, buf);
    FlatpakRemoteInfo out;
    glz::read_binary(out, buf);
    EXPECT_EQ(out.url, "oci+https://registry.fedoraproject.org");
    EXPECT_EQ(out.remoteType, 2);
}
