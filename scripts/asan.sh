#!/usr/bin/env bash
# Build and run C++ tests under AddressSanitizer + UBSan.
set -euo pipefail
BUILD_DIR="${1:-build-asan}"
CPU_COUNT="$(nproc 2>/dev/null || echo 4)"
echo "=== Building with ASAN ==="
cmake -B "$BUILD_DIR" native/ \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_COMPILER=clang++-19 \
    -DCMAKE_C_COMPILER=clang-19 \
    -DENABLE_ASAN=ON \
    -DBUILD_TESTING=ON
cmake --build "$BUILD_DIR" --parallel "$CPU_COUNT"
echo ""
echo "=== Running tests under ASAN ==="
export ASAN_OPTIONS="detect_leaks=0:halt_on_error=1:abort_on_error=1"
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1"
ctest --test-dir "$BUILD_DIR/test" --output-on-failure -j"$CPU_COUNT"
echo "=== ASAN clean ==="
