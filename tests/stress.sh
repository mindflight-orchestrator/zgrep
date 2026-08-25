#!/usr/bin/env bash
set -euo pipefail

ZGREP=${1:?missing zgr binary}
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
    compare_large_locale "$description" C "$corpus" "$@"
}

compare_large_locale() {
    description=$1
    locale_name=$2
    corpus=$3
    shift 3
    set +e
    LC_ALL=$locale_name grep "$@" "$corpus" >"$TEST_DIR/grep.out" 2>"$TEST_DIR/grep.err"
    grep_status=$?
    LC_ALL=$locale_name "$ZGREP" "$@" "$corpus" >"$TEST_DIR/zgrep.out" 2>"$TEST_DIR/zgrep.err"
    zgrep_status=$?
    set -e
    sed 's/^grep:/zgr:/' "$TEST_DIR/grep.err" >"$TEST_DIR/grep-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/grep.out" "$TEST_DIR/zgrep.out" || \
        ! cmp -s "$TEST_DIR/grep-normalized.err" "$TEST_DIR/zgrep.err"; then
        echo "large-file differential failure: $description" >&2
        echo "status: GNU=$grep_status zgrep=$zgrep_status" >&2
        diff -u "$TEST_DIR/grep.out" "$TEST_DIR/zgrep.out" >&2 || true
        diff -u "$TEST_DIR/grep-normalized.err" "$TEST_DIR/zgrep.err" >&2 || true
        exit 1
    fi
}

# Sparse output stays below the metadata cap and uses ordered parallel match
# discovery on a real file larger than the production 64 MiB threshold.
compare_large "parallel sparse literal output" \
    "$TEXT_CORPUS" -F -n -b rare-needle
compare_large "parallel sparse literal only-matching output" \
    "$TEXT_CORPUS" -F -n -b -o rare-needle
GREP_COLORS= compare_large "parallel sparse literal colored output" \
    "$TEXT_CORPUS" --color=always -F -n -b rare-needle
compare_large "parallel sparse literal context output" \
    "$TEXT_CORPUS" -a -F -n -b -C2 rare-needle
GREP_COLORS= compare_large "parallel sparse literal colored context output" \
    "$TEXT_CORPUS" --color=always -a -F -n -b -C2 rare-needle
compare_large "parallel literal-alternation output" \
    "$TEXT_CORPUS" -E -n 'rare-needle|status=500|route=/api/item/42'
compare_large "parallel sparse-regexp count" \
    "$TEXT_CORPUS" -E -c '[a-z]+-needle'
compare_large "parallel inverted sparse-regexp count" \
    "$TEXT_CORPUS" -E -v -c '[a-z]+-needle'
compare_large "parallel class-sequence regexp count" \
    "$TEXT_CORPUS" -E -c '[[:alpha:]]{4}[[:space:]]+[[:alnum:]]{3}'
compare_large "parallel inverted class-sequence regexp count" \
    "$TEXT_CORPUS" -E -v -c '[[:alpha:]]{4}[[:space:]]+[[:alnum:]]{3}'
compare_large "parallel sparse-regexp output" \
    "$TEXT_CORPUS" -E -n -b '[a-z]+-needle'
compare_large "parallel sparse-regexp context output" \
    "$TEXT_CORPUS" -a -E -n -b -C2 '[a-z]+-needle'
GREP_COLORS= compare_large "parallel sparse-regexp colored output" \
    "$TEXT_CORPUS" --color=always -E -n -b '[a-z]+-needle'
GREP_COLORS= compare_large "parallel sparse-regexp colored context output" \
    "$TEXT_CORPUS" --color=always -a -E -n -b -C2 '[a-z]+-needle'
compare_large "sparse-regexp only-matching output" \
    "$TEXT_CORPUS" -E -n -b -o '[a-z]+-needle'
GREP_COLORS= compare_large "sparse-regexp colored only-matching output" \
    "$TEXT_CORPUS" --color=always -E -n -b -o '[a-z]+-needle'
compare_large "leftmost-longest regexp only-matching output" \
    "$TEXT_CORPUS" -E -n -b -o '(rare|rare-needle)'

# INFO selects every record. Each 16 MiB chunk exceeds the 64 Ki span cap, so
# zgrep must abandon collected metadata and restart sequentially before output.
compare_large "dense metadata fallback" "$TEXT_CORPUS" -F -n INFO
compare_large "dense context metadata fallback" "$TEXT_CORPUS" -a -F -n -C2 INFO

# Exercise the same production threshold and ordering rules with NUL records.
compare_large "parallel NUL-record output" "$NUL_CORPUS" -z -F -n -b rare-needle
compare_large "parallel NUL literal context output" \
    "$NUL_CORPUS" -a -z -F -n -b -C2 rare-needle
compare_large "parallel NUL sparse-regexp output" \
    "$NUL_CORPUS" -z -E -n -b '[a-z]+-needle'
compare_large "parallel NUL class-sequence regexp count" \
    "$NUL_CORPUS" -z -E -c '[[:alpha:]]{4}[[:space:]]+[[:alnum:]]{3}'
compare_large "parallel NUL sparse-regexp context output" \
    "$NUL_CORPUS" -a -z -E -n -b -C2 '[a-z]+-needle'
compare_large "NUL sparse-regexp only-matching output" \
    "$NUL_CORPUS" -z -E -n -b -o '[a-z]+-needle'
compare_large "dense NUL metadata fallback" "$NUL_CORPUS" -z -F -n INFO

# A few multi-megabyte files use the size-aware recursive list scheduler even
# though the tree has fewer than the normal 32-files-per-worker threshold.
PARALLEL_TREE="$TEST_DIR/parallel-list-tree"
mkdir "$PARALLEL_TREE"
"$REPO_ROOT/bench/generate.sh" "$PARALLEL_TREE/a.txt" 30000 newline >/dev/null
cp "$PARALLEL_TREE/a.txt" "$PARALLEL_TREE/b.txt"
cp "$PARALLEL_TREE/a.txt" "$PARALLEL_TREE/c.txt"
set +e
LC_ALL=C grep -E -r -l '[[:alnum:]_]{12}' "$PARALLEL_TREE" | sort >"$TEST_DIR/grep-tree.out"
grep_status=${PIPESTATUS[0]}
LC_ALL=C "$ZGREP" -E -r -l '[[:alnum:]_]{12}' "$PARALLEL_TREE" | sort >"$TEST_DIR/zgrep-tree.out"
zgrep_status=${PIPESTATUS[0]}
set -e
if [ "$grep_status" -ne "$zgrep_status" ] ||
    ! cmp -s "$TEST_DIR/grep-tree.out" "$TEST_DIR/zgrep-tree.out"; then
    echo 'large-file differential failure: size-aware recursive list scheduling' >&2
    exit 1
fi

SMALL_TREE="$TEST_DIR/small-list-tree"
mkdir "$SMALL_TREE"
for index in $(seq 1 38); do
    printf 'small recursive needle %s\n' "$index" >"$SMALL_TREE/file-$index.txt"
done
: >"$SMALL_TREE/empty.txt"
dd if=/dev/zero of="$SMALL_TREE/exact-64k.dat" bs=65536 count=1 status=none
set +e
LC_ALL=C grep -r -l needle "$SMALL_TREE" | sort >"$TEST_DIR/grep-small-tree.out"
grep_status=${PIPESTATUS[0]}
LC_ALL=C "$ZGREP" -r -l needle "$SMALL_TREE" | sort >"$TEST_DIR/zgrep-small-tree.out"
zgrep_status=${PIPESTATUS[0]}
set -e
if [ "$grep_status" -ne "$zgrep_status" ] ||
    ! cmp -s "$TEST_DIR/grep-small-tree.out" "$TEST_DIR/zgrep-small-tree.out"; then
    echo 'large-file differential failure: stat-free small-file recursive list' >&2
    exit 1
fi

# Trees above the pipeline threshold overlap traversal with list-mode scans.
# Alternating selected files proves both -l and -L while exact output comparison
# retains GNU's traversal order rather than sorting away ordering mistakes.
PIPELINED_TREE="$TEST_DIR/pipelined-list-tree"
for directory in $(seq 0 7); do
    mkdir -p "$PIPELINED_TREE/directory-$directory"
done
for index in $(seq 0 519); do
    directory=$((index % 8))
    if [ $((index % 2)) -eq 0 ]; then
        printf 'pipelined recursive needle %s\n' "$index"
    else
        printf 'pipelined recursive haystack %s\n' "$index"
    fi >"$PIPELINED_TREE/directory-$directory/file-$index.txt"
done
for index in $(seq 1 2000); do
    printf 'dense recursive output line %s\n' "$index"
done >"$PIPELINED_TREE/directory-0/dense-output.txt"
printf 'ZZZZZ\nYYYYY\n' \
    >"$PIPELINED_TREE/directory-3/regex-cross-record.txt"
printf 'ZZZZZ YYYYY\n' \
    >"$PIPELINED_TREE/directory-7/regex-within-record.txt"
compare_large "pipelined recursive matching-file list" \
    "$PIPELINED_TREE" -F -r -l needle
compare_large "pipelined recursive non-matching-file list" \
    "$PIPELINED_TREE" -F -r -L needle
compare_large "pipelined recursive multiple-literal list" \
    "$PIPELINED_TREE" -F -r -l -e definitely-absent-zgrep -e needle
compare_large "pipelined sparse recursive literal output" \
    "$PIPELINED_TREE" -a -F -r -n -b 'pipelined recursive needle 0'
compare_large "pipelined ordered recursive literal output" \
    "$PIPELINED_TREE" -a -F -r -n -b needle
compare_large "pipelined dense-file output fallback" \
    "$PIPELINED_TREE" -a -F -r -n -b 'dense recursive'
compare_large "pipelined recursive no-literal regexp output" \
    "$PIPELINED_TREE" -a -E -r -n -b \
    '[[:alnum:]_]{9}[[:space:]]+[[:alnum:]_]{9}'
compare_large "pipelined default sparse recursive literal output" \
    "$PIPELINED_TREE" -F -r -n -b 'pipelined recursive needle 0'
compare_large "pipelined default ordered recursive literal output" \
    "$PIPELINED_TREE" -F -r -n -b needle
compare_large "pipelined default dense-file output fallback" \
    "$PIPELINED_TREE" -F -r -n -b 'dense recursive'
compare_large "pipelined default recursive no-literal regexp output" \
    "$PIPELINED_TREE" -E -r -n -b \
    '[[:alnum:]_]{9}[[:space:]]+[[:alnum:]_]{9}'
compare_large "pipelined whole-buffer regexp preserves record boundaries" \
    "$PIPELINED_TREE" -E -r -n -b '[Z]{5}[[:space:]]+[Y]{5}'
compare_large "pipelined without-match recursive literal output" \
    "$PIPELINED_TREE" -I -F -r -n -b needle

# Exact-size capture may retain more than 256 small outputs, but the aggregate
# payload remains capped at 16 MiB. This tree exceeds that byte budget while
# keeping every individual file below the 64 KiB per-file fallback.
CAPTURE_BUDGET_TREE="$TEST_DIR/capture-budget-tree"
for directory in $(seq 0 7); do
    mkdir -p "$CAPTURE_BUDGET_TREE/directory-$directory"
done
for index in $(seq 0 519); do
    directory=$((index % 8))
    awk -v file="$index" 'BEGIN {
        for (line = 1; line <= 300; line++) {
            printf "capture budget target file=%04d line=%04d 0123456789012345678901234567890123456789\n", file, line
        }
    }' >"$CAPTURE_BUDGET_TREE/directory-$directory/file-$index.txt"
done
compare_large "pipelined aggregate capture budget fallback" \
    "$CAPTURE_BUDGET_TREE" -a -F -r -n -b 'capture budget target'

# Matching NUL files must leave the parallel path before it emits anything so
# GNU's block-sensitive binary summaries and any earlier text output remain
# byte exact. These patterns do not affect the ordinary text cases above.
printf 'binary-pipeline-target\0payload\n' \
    >"$PIPELINED_TREE/directory-1/binary-first.dat"
printf 'prefix\nbinary-pipeline-target\0payload\n' \
    >"$PIPELINED_TREE/directory-6/binary-second.dat"
printf 'early-binary-pipeline-target\n' \
    >"$PIPELINED_TREE/directory-2/binary-late.dat"
head -c 300000 /dev/zero | tr '\0' x \
    >>"$PIPELINED_TREE/directory-2/binary-late.dat"
printf '\0\nlate-binary-pipeline-target\n' \
    >>"$PIPELINED_TREE/directory-2/binary-late.dat"
compare_large "pipelined default ordered binary summaries" \
    "$PIPELINED_TREE" -F -r -n -b binary-pipeline-target
compare_large "pipelined default text match before late binary block" \
    "$PIPELINED_TREE" -F -r -n -b early-binary-pipeline-target
compare_large "pipelined default match after late binary block" \
    "$PIPELINED_TREE" -F -r -n -b late-binary-pipeline-target
compare_large "pipelined without-match skips NUL files" \
    "$PIPELINED_TREE" -I -F -r -n -b binary-pipeline-target
compare_large "without-match late NUL count" \
    "$PIPELINED_TREE" -I -F -r -c early-binary-pipeline-target
compare_large "without-match late NUL matching-file list" \
    "$PIPELINED_TREE" -I -F -r -l early-binary-pipeline-target
compare_large "without-match late NUL non-matching-file list" \
    "$PIPELINED_TREE" -I -F -r -L early-binary-pipeline-target
compare_large "without-match late NUL quiet status" \
    "$PIPELINED_TREE" -I -F -r -q early-binary-pipeline-target
compare_large "without-match late NUL maximum count" \
    "$PIPELINED_TREE" -I -F -r -n -m1 early-binary-pipeline-target
compare_large "without-match late NUL context" \
    "$PIPELINED_TREE" -I -F -r -n -C1 early-binary-pipeline-target
compare_large "without-match late NUL only-matching" \
    "$PIPELINED_TREE" -I -F -r -n -b -o early-binary-pipeline-target

# With -z, NUL is the record delimiter rather than a binary marker; keep this
# on the parallel path and preserve record numbers, offsets and NUL output.
printf 'haystack\0nul-pipeline-target one\0tail\0' \
    >"$PIPELINED_TREE/directory-4/nul-record-first.dat"
printf 'nul-pipeline-target two\0tail\0' \
    >"$PIPELINED_TREE/directory-5/nul-record-second.dat"
compare_large "pipelined default NUL-record output" \
    "$PIPELINED_TREE" -z -F -r -n -b nul-pipeline-target
compare_large "pipelined without-match NUL-record output" \
    "$PIPELINED_TREE" -I -z -F -r -n -b nul-pipeline-target

if locale -a | grep -Fxq C.utf8; then
    compare_large_locale "parallel UTF-8 class-sequence regexp count" C.utf8 \
        "$TEXT_CORPUS" -E -c '[[:alpha:]]{4}[[:space:]]+[[:alnum:]]{3}'
    printf 'valid utf8-pipeline-target\ninvalid\303( utf8-pipeline-target\nvalid-after utf8-pipeline-target\n' \
        >"$PIPELINED_TREE/directory-3/invalid-utf8-first.txt"
    printf 'valid-two utf8-pipeline-target\ninvalid\377 utf8-pipeline-target\n' \
        >"$PIPELINED_TREE/directory-7/invalid-utf8-second.txt"
    compare_large_locale "pipelined ordered invalid UTF-8 summaries" C.utf8 \
        "$PIPELINED_TREE" -F -r -n -b utf8-pipeline-target
    compare_large_locale "pipelined without-match invalid UTF-8 suppression" C.utf8 \
        "$PIPELINED_TREE" -I -F -r -n -b utf8-pipeline-target
    compare_large_locale "pipelined UTF-8 whole-buffer regexp boundaries" C.utf8 \
        "$PIPELINED_TREE" -E -r -n -b '[Z]{5}[[:space:]]+[Y]{5}'
fi

printf 'zgr large-file stress differentials passed\n'
