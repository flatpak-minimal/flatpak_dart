// test_installation_reader.cpp — tests for the installation reader C ABI.

#include <gtest/gtest.h>

#include "flatpak_bridge.h"

TEST(InstallationReaderCABI, CreateAndDestroyUser) {
    void* handle = flatpak_reader_create("user");
    if (!handle) {
        GTEST_SKIP() << "No user Flatpak installation available";
    }
    flatpak_reader_destroy(handle);
}

TEST(InstallationReaderCABI, CreateSystemMayFail) {
    void* handle = flatpak_reader_create("system");
    if (handle) {
        flatpak_reader_destroy(handle);
    }
}
