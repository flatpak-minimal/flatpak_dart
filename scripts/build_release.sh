#!/usr/bin/env bash
# Build the flatpak_nc shared library in Release mode.
# Usage: ./scripts/build_release.sh [build-dir]
set -euo pipefail
BUILD_DIR="${1:-build-release}"
CPU_COUNT="$(nproc 2>/dev/null || echo 4)"
NATIVE_DIR="$(cd "$(dirname "$0")/../native" && pwd)"

echo "=== Building Release ==="
cmake -B "$BUILD_DIR" "$NATIVE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=clang++-19 \
    -DCMAKE_C_COMPILER=clang-19
cmake --build "$BUILD_DIR" --parallel "$CPU_COUNT"
echo "=== Built: $BUILD_DIR/libflatpak_nc.so ==="
echo ""
echo "Run examples with:"
echo "  FLATPAK_NC_LIB=$BUILD_DIR/libflatpak_nc.so dart run example/list_apps.dart"
