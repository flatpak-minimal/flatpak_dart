#!/usr/bin/env bash
# Usage: ./scripts/clang_format.sh check|fix
set -euo pipefail
MODE="${1:-check}"
which clang-format-19 &>/dev/null || { echo "ERROR: clang-format-19 not found"; exit 1; }
SOURCES=$(find native/src native/include native/test \
    \( -name "*.cpp" -o -name "*.h" \) \
    | grep -v dart_api_dl | grep -v generated)
if [[ "$MODE" == "fix" ]]; then
    echo "=== Auto-formatting ==="
    echo "$SOURCES" | xargs clang-format-19 -i
    echo "Done."
else
    echo "=== Checking formatting ==="
    FAILED=0
    while IFS= read -r f; do
        clang-format-19 --dry-run --Werror "$f" 2>/dev/null || { echo "NEEDS FORMAT: $f"; FAILED=1; }
    done <<< "$SOURCES"
    [[ $FAILED -eq 0 ]] && echo "All files correctly formatted." || { echo "Run: ./scripts/clang_format.sh fix"; exit 1; }
fi
