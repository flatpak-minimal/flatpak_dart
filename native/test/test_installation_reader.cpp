// test_installation_reader.cpp — tests for the installation reader C ABI.

#include <gtest/gtest.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>

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

// ── /proc start-time identity check (S1) ────────────────────────────────────
// read_start_time() is file-static, so exercise the property it relies on: field 22 of
// /proc/<pid>/stat is stable for a live process and present for our own pid.
namespace {
unsigned long long start_time_of(pid_t pid) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/stat", static_cast<int>(pid));
    FILE* f = fopen(path, "re");
    if (!f) {
        return 0;
    }
    char buf[4096];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = '\0';
    const char* p = strrchr(buf, ')');
    if (!p) {
        return 0;
    }
    p++;
    int field = 2;
    while (*p) {
        while (*p == ' ') {
            p++;
        }
        if (!*p) {
            break;
        }
        field++;
        if (field == 22) {
            unsigned long long v = 0;
            return sscanf(p, "%llu", &v) == 1 ? v : 0;
        }
        while (*p && *p != ' ') {
            p++;
        }
    }
    return 0;
}
}  // namespace

TEST(ProcStartTime, StableForLiveProcess) {
    unsigned long long a = start_time_of(getpid());
    EXPECT_GT(a, 0u);
    EXPECT_EQ(a, start_time_of(getpid()));
}

TEST(ProcStartTime, ZeroForMissingProcess) {
    // Reserved-but-unused high pid; if it happens to exist we only assert we did not crash.
    unsigned long long v = start_time_of(0x7FFFFFF);
    EXPECT_EQ(v, 0u);
}
