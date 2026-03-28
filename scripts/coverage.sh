#!/usr/bin/env bash
# Full coverage: C++ (gcov/lcov) + Dart (lcov merge).
set -euo pipefail
BUILD_DIR="build-cov"
CPU_COUNT="$(nproc 2>/dev/null || echo 4)"

echo "=== Building with coverage ==="
cmake -B "$BUILD_DIR" native/ \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_C_COMPILER=gcc \
    -DENABLE_COVERAGE=ON \
    -DBUILD_TESTING=ON
cmake --build "$BUILD_DIR" --parallel "$CPU_COUNT"

echo ""
echo "=== Running C++ tests ==="
ctest --test-dir "$BUILD_DIR/test" --output-on-failure -j"$CPU_COUNT"

echo ""
echo "=== Running Dart tests with coverage ==="
dart test --coverage=coverage/
dart pub global run coverage:format_coverage \
    --lcov --in=coverage/ \
    --out=coverage/lcov.info \
    --packages=.dart_tool/package_config.json \
    --report-on=lib/

echo ""
echo "=== Generating C++ coverage report ==="
cmake --build "$BUILD_DIR" --target coverage

echo ""
lcov --summary "$BUILD_DIR/coverage.info"
echo "HTML: $BUILD_DIR/coverage_html/index.html"
echo "Dart lcov: coverage/lcov.info"
