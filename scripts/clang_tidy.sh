#!/usr/bin/env bash
# Run clang-tidy-19 over all non-generated C++ sources.
set -euo pipefail
BUILD_DIR="${1:-build-tidy}"
CPU_COUNT="$(nproc 2>/dev/null || echo 4)"
which clang-tidy-19 &>/dev/null || { echo "ERROR: clang-tidy-19 not found"; exit 1; }

echo "=== Generating compile_commands.json ==="
cmake -B "$BUILD_DIR" native/ \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_COMPILER=clang++-19 \
    -DCMAKE_C_COMPILER=clang-19 \
    -DENABLE_CLANG_TIDY=OFF \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build "$BUILD_DIR" --parallel "$CPU_COUNT"

echo ""
echo "=== Running clang-tidy-19 ==="
find native/src native/include -name "*.cpp" -o -name "*.h" \
    | grep -v dart_api_dl | grep -v generated \
    | xargs -P"$CPU_COUNT" clang-tidy-19 \
        -p "$BUILD_DIR" \
        --config-file=.clang-tidy \
        --warnings-as-errors="*"
echo "=== clang-tidy-19 clean ==="
