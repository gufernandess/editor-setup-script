#!/usr/bin/env bash
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

TESTS_RUN=0
TESTS_FAILED=0

source "$TEST_DIR/test_helper.sh"

for test_file in "$TEST_DIR"/test_*.sh; do
    base="$(basename "$test_file")"
    [[ "$base" == "test_helper.sh" ]] && continue
    echo "== $base =="
    source "$test_file"
done

echo
echo "Total: $TESTS_RUN run, $TESTS_FAILED failed"
[[ "$TESTS_FAILED" -eq 0 ]]
