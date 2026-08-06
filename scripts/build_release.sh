#!/usr/bin/env bash
# Build the flatpak_nc shared library in Release mode.
# Usage: ./scripts/build_release.sh [build-dir]
#
# The compiler is left to CMake's default (the same toolchain the target's
# libflatpak/glib were built against) so the C++ runtimes match at load time.
# Override with CC/CXX if you need a specific toolchain, e.g.:
#   CC=clang-19 CXX=clang++-19 ./scripts/build_release.sh
set -euo pipefail
BUILD_DIR="${1:-build-release}"
CPU_COUNT="$(nproc 2>/dev/null || echo 4)"
NATIVE_DIR="$(cd "$(dirname "$0")/../native" && pwd)"

echo "=== Building Release ==="
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -B "$BUILD_DIR" "$NATIVE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    ${CXX:+-DCMAKE_CXX_COMPILER="$CXX"} \
    ${CC:+-DCMAKE_C_COMPILER="$CC"}
cmake --build "$BUILD_DIR" --parallel "$CPU_COUNT"
echo "=== Built: $BUILD_DIR/libflatpak_nc.so ==="
echo ""
echo "This build is for sanitizer, coverage and clang-tidy runs."
echo "dart run builds its own copy through hook/build.dart."
