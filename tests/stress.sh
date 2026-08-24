#!/usr/bin/env bash
set -euo pipefail

ZGREP=${1:?missing zgrep binary}
ZGREP=$(realpath "$ZGREP")
REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/zgrep-stress.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

TEXT_CORPUS="$TEST_DIR/large.txt"
NUL_CORPUS="$TEST_DIR/large-nul.dat"
"$REPO_ROOT/bench/generate.sh" "$TEXT_CORPUS" 800000 newline >/dev/null
"$REPO_ROOT/bench/generate.sh" "$NUL_CORPUS" 750000 nul >/dev/null

compare_large() {
    description=$1
    corpus=$2
    shift 2
    set +e
    LC_ALL=C grep "$@" "$corpus" >"$TEST_DIR/grep.out" 2>"$TEST_DIR/grep.err"
    grep_status=$?
    LC_ALL=C "$ZGREP" "$@" "$corpus" >"$TEST_DIR/zgrep.out" 2>"$TEST_DIR/zgrep.err"
    zgrep_status=$?
    set -e
    sed 's/^grep:/zgrep:/' "$TEST_DIR/grep.err" >"$TEST_DIR/grep-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/grep.out" "$TEST_DIR/zgrep.out" || \
        ! cmp -s "$TEST_DIR/grep-normalized.err" "$TEST_DIR/zgrep.err"; then
        echo "large-file differential failure: $description" >&2
        exit 1
    fi
}

# Sparse output stays below the metadata cap and uses ordered parallel match
# discovery on a real file larger than the production 64 MiB threshold.
compare_large "parallel sparse literal output" \
    "$TEXT_CORPUS" -F -n -b rare-needle
compare_large "parallel sparse literal only-matching output" \
    "$TEXT_CORPUS" -F -n -b -o rare-needle
compare_large "parallel literal-alternation output" \
    "$TEXT_CORPUS" -E -n 'rare-needle|status=500|route=/api/item/42'
compare_large "parallel sparse-regexp count" \
    "$TEXT_CORPUS" -E -c '[a-z]+-needle'
compare_large "parallel inverted sparse-regexp count" \
    "$TEXT_CORPUS" -E -v -c '[a-z]+-needle'
compare_large "parallel sparse-regexp output" \
    "$TEXT_CORPUS" -E -n -b '[a-z]+-needle'
compare_large "sparse-regexp only-matching output" \
    "$TEXT_CORPUS" -E -n -b -o '[a-z]+-needle'
compare_large "leftmost-longest regexp only-matching output" \
    "$TEXT_CORPUS" -E -n -b -o '(rare|rare-needle)'

# INFO selects every record. Each 16 MiB chunk exceeds the 64 Ki span cap, so
# zgrep must abandon collected metadata and restart sequentially before output.
compare_large "dense metadata fallback" "$TEXT_CORPUS" -F -n INFO

# Exercise the same production threshold and ordering rules with NUL records.
compare_large "parallel NUL-record output" "$NUL_CORPUS" -z -F -n -b rare-needle
compare_large "parallel NUL sparse-regexp output" \
    "$NUL_CORPUS" -z -E -n -b '[a-z]+-needle'
compare_large "NUL sparse-regexp only-matching output" \
    "$NUL_CORPUS" -z -E -n -b -o '[a-z]+-needle'
compare_large "dense NUL metadata fallback" "$NUL_CORPUS" -z -F -n INFO

printf 'zgrep large-file stress differentials passed\n'
