#!/bin/sh
set -eu

TREE=${1:?usage: bench/run-tree.sh TREE [PATTERN] [REPEATS]}
PATTERN=${2:-SearcherBuilder}
REPEATS=${3:-20}
ZGREP=${ZGREP:-./zig-out/bin/zgrep}
SINK=$(mktemp /tmp/zgrep-tree-benchmark-output.XXXXXX)
REFERENCE=$(mktemp /tmp/zgrep-tree-benchmark-reference.XXXXXX)
CANDIDATE=$(mktemp /tmp/zgrep-tree-benchmark-candidate.XXXXXX)
trap 'rm -f "$SINK" "$REFERENCE" "$CANDIDATE"' EXIT HUP INT TERM

if [ ! -d "$TREE" ]; then
    echo "benchmark tree not found: $TREE" >&2
    exit 2
fi
if [ ! -x "$ZGREP" ]; then
    echo "zgrep binary not found: $ZGREP" >&2
    echo "run: zig build -Doptimize=ReleaseFast" >&2
    exit 2
fi

benchmark() {
    label=$1
    shift
    "$@" >"$SINK" || [ "$?" -eq 1 ]
    start=$(date +%s%N)
    index=0
    while [ "$index" -lt "$REPEATS" ]; do
        "$@" >"$SINK" || [ "$?" -eq 1 ]
        index=$((index + 1))
    done
    end=$(date +%s%N)
    awk -v label="$label" -v ns="$((end - start))" -v repeats="$REPEATS" \
        'BEGIN { printf "%-30s %8.3f ms/run\n", label, ns / repeats / 1000000 }'
}

run_sorted() {
    output=$1
    shift
    set +e
    "$@" >"$SINK"
    command_status=$?
    set -e
    sort "$SINK" >"$output"
    return "$command_status"
}

verify_case() {
    label=$1
    zgrep_flags=$2
    grep_flags=$3
    ripgrep_flags=$4
    pattern=$5

    run_sorted "$REFERENCE" env LC_ALL=C grep $grep_flags "$pattern" "$TREE" || [ "$?" -eq 1 ]
    run_sorted "$CANDIDATE" env LC_ALL=C "$ZGREP" $zgrep_flags "$pattern" "$TREE" || [ "$?" -eq 1 ]
    if ! cmp -s "$REFERENCE" "$CANDIDATE"; then
        echo "recursive result mismatch: zgrep / $label" >&2
        diff -u "$REFERENCE" "$CANDIDATE" >&2 || true
        exit 1
    fi
    run_sorted "$CANDIDATE" env LC_ALL=C rg $ripgrep_flags "$pattern" "$TREE" || [ "$?" -eq 1 ]
    if ! cmp -s "$REFERENCE" "$CANDIDATE"; then
        echo "recursive result mismatch: ripgrep / $label" >&2
        diff -u "$REFERENCE" "$CANDIDATE" >&2 || true
        exit 1
    fi
}

benchmark_case() {
    label=$1
    zgrep_flags=$2
    grep_flags=$3
    ripgrep_flags=$4
    pattern=$5

    printf '%s\n' "$label"
    verify_case "$label" "$zgrep_flags" "$grep_flags" "$ripgrep_flags" "$pattern"
    benchmark zgrep env LC_ALL=C "$ZGREP" $zgrep_flags "$pattern" "$TREE"
    benchmark grep env LC_ALL=C grep $grep_flags "$pattern" "$TREE"
    benchmark ripgrep env LC_ALL=C rg $ripgrep_flags "$pattern" "$TREE"
}

files=$(find "$TREE" -type f | wc -l)
bytes=$(find "$TREE" -type f -printf '%s\n' | awk '{ total += $1 } END { print total + 0 }')
printf 'tree: %s (%s files, %s bytes), pattern: %s, repeats: %s\n' \
    "$TREE" "$files" "$bytes" "$PATTERN" "$REPEATS"
benchmark_case 'tree literal' \
    '-F -r -l' '-a -F -r -l' '-a -uuu -F -l' "$PATTERN"
benchmark_case 'tree case-insensitive literal' \
    '-F -i -r -l' '-a -F -i -r -l' '-a -uuu -F -i -l' "$PATTERN"
benchmark_case 'tree word literal' \
    '-F -w -r -l' '-a -F -w -r -l' '-a -uuu -F -w -l' "$PATTERN"
benchmark_case 'tree multiple literals' \
    '-F -r -l -e definitely-absent-zgrep -e' \
    '-a -F -r -l -e definitely-absent-zgrep -e' \
    '-a -uuu -F -l -e definitely-absent-zgrep -e' \
    "$PATTERN"
benchmark_case 'tree regexp without literal' \
    '-E -r -l' '-a -E -r -l' '-a -uuu -l' '[[:alnum:]_]{12}'
