#!/usr/bin/env bash
# Build and run the C++ tests under ThreadSanitizer.
#
# Companion to asan.sh. ASan and TSan cannot be combined in one build, and they
# catch different things: the reaper and the launch/transaction workers are
# concurrent code whose bugs are races, not memory errors. A move-assignment
# race in ChildReaper reached review passing the ASan job, clang-tidy and 700
# stress runs, which is what this job exists to catch earlier.
set -euo pipefail
BUILD_DIR="${1:-build-tsan}"
CPU_COUNT="$(nproc 2>/dev/null || echo 4)"
echo "=== Building with TSAN ==="
cmake -B "$BUILD_DIR" native/ \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_COMPILER=clang++-19 \
    -DCMAKE_C_COMPILER=clang-19 \
    -DENABLE_TSAN=ON \
    -DBUILD_TESTING=ON
cmake --build "$BUILD_DIR" --parallel "$CPU_COUNT"
echo ""
echo "=== Running tests under TSAN ==="
# report_thread_leaks=0: the reaper tests fork(), and a forked child inherits
# TSan's view of the parent's threads, then reports every one of them as leaked
# at exit. Those reports name the child's pid, not the test's. Nothing to do
# with the code under test.
export TSAN_OPTIONS="halt_on_error=1:second_deadlock_stack=1:report_thread_leaks=0"
#
# test_installation_reader is excluded, not suppressed. It is the one target
# that opens a real FlatpakInstallation, which starts GLib's gdbus worker and
# pulls in whatever GIO modules the host has (gvfs, on a desktop). GLib and
# libflatpak are linked as distribution binaries, so TSan cannot see their
# internal synchronisation and reports their correctly-ordered allocations as
# races — every such report bottoms out in those libraries with no frame of
# ours. Suppressing by library name is worse than excluding: the obvious
# `called_from_lib:libflatpak` also matches our own libflatpak_nc.so, which
# would silence exactly the code this job is meant to check.
#
# The concurrency we own — ChildReaper, the transaction worker — lives in the
# targets that do run, and they are clean with no suppressions at all.
ctest --test-dir "$BUILD_DIR/test" --output-on-failure -j"$CPU_COUNT" \
    -E '^test_installation_reader$'
echo "=== TSAN clean ==="
