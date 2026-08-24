#!/bin/sh
set -eu

CORPUS=${1:-/tmp/zgrep-bench-varied.txt}
REPEATS=${2:-20}
ZGREP=${ZGREP:-./zig-out/bin/zgrep}
SINK=$(mktemp /tmp/zgrep-benchmark-output.XXXXXX)
REFERENCE=$(mktemp /tmp/zgrep-benchmark-reference.XXXXXX)
trap 'rm -f "$SINK" "$REFERENCE"' EXIT HUP INT TERM

if [ ! -r "$CORPUS" ]; then
    echo "benchmark corpus not found: $CORPUS" >&2
    echo "run: bench/generate.sh $CORPUS" >&2
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

benchmark_stream() {
    label=$1
    shift
    cat "$CORPUS" | "$@" >"$SINK" || [ "$?" -eq 1 ]
    start=$(date +%s%N)
    index=0
    while [ "$index" -lt "$REPEATS" ]; do
        cat "$CORPUS" | "$@" >"$SINK" || [ "$?" -eq 1 ]
        index=$((index + 1))
    done
    end=$(date +%s%N)
    awk -v label="$label" -v ns="$((end - start))" -v repeats="$REPEATS" \
        'BEGIN { printf "%-30s %8.3f ms/run\n", label, ns / repeats / 1000000 }'
}

run_capture() {
    output=$1
    shift
    set +e
    "$@" >"$output"
    captured_status=$?
    set -e
}

verify_case() {
    label=$1
    zgrep_flags=$2
    grep_flags=$3
    ripgrep_flags=$4
    pattern=$5

    run_capture "$REFERENCE" env LC_ALL=C grep $grep_flags "$pattern" "$CORPUS"
    reference_status=$captured_status
    run_capture "$SINK" env LC_ALL=C "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
        echo "benchmark correctness failure: zgrep / $label" >&2
        exit 1
    fi
    run_capture "$SINK" env LC_ALL=C rg $ripgrep_flags "$pattern" "$CORPUS"
    if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
        echo "benchmark correctness failure: ripgrep / $label" >&2
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
    benchmark zgrep env LC_ALL=C "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    benchmark grep env LC_ALL=C grep $grep_flags "$pattern" "$CORPUS"
    benchmark ripgrep env LC_ALL=C rg $ripgrep_flags "$pattern" "$CORPUS"
}

printf 'corpus: %s (%s bytes), repeats: %s\n' "$CORPUS" "$(wc -c <"$CORPUS")" "$REPEATS"
# Case selection is adapted from ripgrep's dual MIT/Unlicense benchsuite at
# commit 3fce3b5bb0236da2df6d99672afb8a719642eca7. Every case is checked against
# GNU grep before it is timed.
benchmark_case 'literal miss' \
    '-F -c' '-F -c' '-a -F -c --include-zero' 'not-present-anywhere'
benchmark_case 'rare literal hit' \
    '-F -c' '-F -c' '-a -F -c' 'rare-needle'
benchmark_case 'literal case-insensitive' \
    '-F -i -c' '-F -i -c' '-a -F -i -c' 'RARE-NEEDLE'
benchmark_case 'word literal' \
    '-F -w -c' '-F -w -c' '-a -F -w -c' 'rare-needle'
benchmark_case 'extended regexp' \
    '-E -c' '-E -c' '-a -c' 'status=(200|500)'
benchmark_case 'regexp with literal suffix' \
    '-E -c' '-E -c' '-a -c' '[a-z]+-needle'
benchmark_case 'literal alternation' \
    '-E -c' '-E -c' '-a -c' \
    'rare-needle|status=500|route=/api/item/42|latency_us=999'
benchmark_case 'case-i literal alternation' \
    '-E -i -c' '-E -i -c' '-a -i -c' \
    'RARE-NEEDLE|STATUS=500|ROUTE=/API/ITEM/42|LATENCY_US=999'
benchmark_case 'regexp with inner literal' \
    '-E -n' '-E -n' '-a -n' \
    'route=/api/item/[[:digit:]]+[[:space:]]+status=500'
benchmark_case 'regexp without literal' \
    '-E -c' '-E -c' '-a -c' \
    '[[:alnum:]_]{4}[[:space:]]+[[:alnum:]_]{7}'
benchmark_case 'literal output with line numbers' \
    '-F -n' '-F -n' '-F -n' 'rare-needle'
benchmark_case 'literal output text mode' \
    '-a -F -n' '-a -F -n' '-a -F -n' 'rare-needle'
benchmark_case 'regexp suffix output with line numbers' \
    '-E -n' '-E -n' '-n' '[a-z]+-needle'
benchmark_case 'regexp only-matching output' \
    '-E -n -b -o' '-E -n -b -o' '-a -n -b -o' '[a-z]+-needle'
benchmark_case 'literal alternation output with line numbers' \
    '-E -n' '-E -n' '-n' \
    'rare-needle|status=500|route=/api/item/42|latency_us=999'
benchmark_case 'literal only-matching output' \
    '-a -F -n -b -o' '-a -F -n -b -o' '-a -F -n -b -o' 'rare-needle'
benchmark_case 'literal output with context' \
    '-a -F -n -C2' '-a -F -n -C2' '-a -F -n -C2' 'rare-needle'

printf '%s\n' 'rare literal hit from stdin'
benchmark_stream zgrep "$ZGREP" -F -c rare-needle
benchmark_stream grep env LC_ALL=C grep -F -c rare-needle
benchmark_stream ripgrep rg -a -F -c rare-needle
