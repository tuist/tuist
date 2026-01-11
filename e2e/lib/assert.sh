#!/usr/bin/env bash
# Assertion helpers for e2e tests
# Adapted from mise's e2e framework

E2E_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=style.sh
source "$E2E_LIB_DIR/style.sh"

fail() {
    err "$*"
    exit 1
}

assert_succeed() {
    local cmd="$1"
    local status=0
    debug "$ $cmd"
    bash -c "$cmd" || status=$?
    if [[ $status -ne 0 ]]; then
        fail "[$cmd] expected success but exited with $status"
    fi
    ok "[$cmd] succeeded"
}

assert_fail() {
    local cmd="$1"
    local status=0
    debug "$ $cmd"
    bash -c "$cmd" 2>&1 || status=$?
    if [[ $status -eq 0 ]]; then
        fail "[$cmd] expected failure but succeeded"
    fi
    ok "[$cmd] failed as expected"
}

assert_contains() {
    local actual="$1"
    local expected="$2"
    if [[ $actual == *"$expected"* ]]; then
        ok "output contains '$expected'"
    else
        fail "expected '$expected' in output but got: $actual"
    fi
}

assert_not_contains() {
    local actual="$1"
    local expected="$2"
    if [[ $actual != *"$expected"* ]]; then
        ok "output does not contain '$expected'"
    else
        fail "expected '$expected' NOT to be in output but it was"
    fi
}

assert_file_exists() {
    if [[ -f $1 ]]; then
        ok "file '$1' exists"
    else
        fail "file '$1' does not exist"
    fi
}

assert_file_not_exists() {
    if [[ ! -f $1 ]]; then
        ok "file '$1' does not exist"
    else
        fail "file '$1' exists but should not"
    fi
}

assert_dir_exists() {
    if [[ -d $1 ]]; then
        ok "directory '$1' exists"
    else
        fail "directory '$1' does not exist"
    fi
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    if [[ $actual == "$expected" ]]; then
        ok "values are equal"
    else
        fail "expected '$expected' but got '$actual'"
    fi
}

assert_gt() {
    local actual="$1"
    local expected="$2"
    if [[ $actual -gt $expected ]]; then
        ok "$actual > $expected"
    else
        fail "expected $actual > $expected"
    fi
}

assert_ge() {
    local actual="$1"
    local expected="$2"
    if [[ $actual -ge $expected ]]; then
        ok "$actual >= $expected"
    else
        fail "expected $actual >= $expected"
    fi
}

require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        fail "required command '$1' not found"
    fi
}

require_env() {
    if [[ -z ${!1:-} ]]; then
        fail "required environment variable '$1' not set"
    fi
}
