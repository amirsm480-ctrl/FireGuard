#!/usr/bin/env bash
set -eu
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_BINARY=$(mktemp "${TMPDIR:-/tmp}/fireguard-firmware-test.XXXXXX")
trap 'rm -f "$TEST_BINARY"' EXIT
c++ -std=c++17 -Wall -Wextra -Werror -I"$TEST_DIR/stubs" "$TEST_DIR/firmware_test.cpp" -o "$TEST_BINARY"
"$TEST_BINARY"
