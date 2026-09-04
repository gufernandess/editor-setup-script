#!/usr/bin/env bash
# Minimal assertion helpers for the hand-rolled test harness.
# Relies on TESTS_RUN / TESTS_FAILED being declared by the caller.

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_eq}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        return 0
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg - expected [$expected] got [$actual]"
    return 1
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-assert_contains}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg - [$haystack] does not contain [$needle]"
    return 1
}

assert_file_exists() {
    local path="$1" msg="${2:-assert_file_exists}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$path" ]]; then
        return 0
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg - [$path] does not exist"
    return 1
}
