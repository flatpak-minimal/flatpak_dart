// test_installation_reader.cpp — tests for InstallationReader.
// These tests require a mock FlatpakInstallation or a real user installation.
// For CI, we test with the user installation (which may be empty).

#include <gtest/gtest.h>

#include "installation_reader.h"

// Note: Full integration tests require a running Flatpak installation.
// These tests verify the reader can be constructed and destroyed without
// crashing when given a user installation path.

TEST(InstallationReader, CreateAndDestroyUser) {
    // This test will only pass on systems with Flatpak installed.
    // CI environments install libflatpak-dev which provides the user dir.
    g_autoptr(GError) err = nullptr;
    auto* inst = flatpak_installation_new_user(nullptr, &err);
    if (!inst) {
        GTEST_SKIP() << "No user Flatpak installation available";
    }
    Dart_Port port = 0;  // dummy port
    auto reader = InstallationReader(port, inst);
    g_object_unref(inst);
    // Destructor should not crash
}

TEST(InstallationReader, ListRemotesOnEmptyInstallation) {
    g_autoptr(GError) err = nullptr;
    auto* inst = flatpak_installation_new_user(nullptr, &err);
    if (!inst) {
        GTEST_SKIP() << "No user Flatpak installation available";
    }
    Dart_Port port = 0;
    auto reader = InstallationReader(port, inst);
    // list_remotes posts to port=0; we just verify it doesn't crash
    reader.list_remotes();
    g_object_unref(inst);
}
