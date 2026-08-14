#!/usr/bin/env bash
# Full coverage: C++ (gcovr) + Dart (package:coverage).
#
# Reporting goes through gcovr rather than lcov: lcov 2.0 cannot parse the gcov
# format emitted by recent gcc (16.x yields rates above 100% and 0% functions),
# and it is what current distributions ship. gcovr still writes an lcov info
# file, so the CI reporter needs no change.
set -euo pipefail
BUILD_DIR="${1:-build-cov}"
CPU_COUNT="$(nproc 2>/dev/null || echo 4)"

command -v gcovr >/dev/null || { echo "ERROR: gcovr not found (pip install gcovr)"; exit 1; }

echo "=== Building with coverage ==="
cmake -B "$BUILD_DIR" native/ \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_C_COMPILER=gcc \
    -DENABLE_COVERAGE=ON \
    -DBUILD_TESTING=ON
cmake --build "$BUILD_DIR" --parallel "$CPU_COUNT"

echo ""
echo "=== C++ coverage (runs the tests) ==="
cmake --build "$BUILD_DIR" --target coverage

echo ""
echo "=== Dart coverage ==="
dart pub global list 2>/dev/null | grep -q '^coverage ' \
    || dart pub global activate coverage
dart pub get
rm -rf coverage
dart test --coverage=coverage/
dart pub global run coverage:format_coverage \
    --lcov --in=coverage/ \
    --out=coverage/lcov.info \
    --packages=.dart_tool/package_config.json \
    --report-on=lib/

python3 - <<'PY'
import re
total = hit = 0
for block in open('coverage/lcov.info').read().split('end_of_record'):
    lf = re.search(r'^LF:(\d+)', block, re.M)
    lh = re.search(r'^LH:(\d+)', block, re.M)
    if lf and lh:
        total += int(lf.group(1))
        hit += int(lh.group(1))
if total:
    print(f'lines: {100 * hit / total:.1f}% ({hit} out of {total})')
PY

echo ""
echo "C++ HTML:  $BUILD_DIR/coverage_html/index.html"
echo "C++ lcov:  $BUILD_DIR/coverage.info"
echo "Dart lcov: coverage/lcov.info"
