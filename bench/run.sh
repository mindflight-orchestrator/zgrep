#!/bin/sh
set -eu

CORPUS=${1:-/tmp/zgrep-bench-varied.txt}
REPEATS=${2:-20}
BENCH_BATCHES=${BENCH_BATCHES:-1}
ZGREP=${ZGR:-${ZGREP:-./zig-out/bin/zgr}}
ZGREP_ZPCRE2=${ZGR_ZPCRE2:-$(dirname "$ZGREP")/zgr-zpcre2}
HAVE_ZPCRE2=0
if [ -x "$ZGREP_ZPCRE2" ]; then HAVE_ZPCRE2=1; fi
BENCH_LOCALE=${BENCH_LOCALE:-C}
BENCH_CACHE=${BENCH_CACHE:-warm}
BENCH_CPUSET=${BENCH_CPUSET:-}
BENCH_PROFILE=${BENCH_PROFILE:-generated}
SINK=$(mktemp /tmp/zgrep-benchmark-output.XXXXXX)
REFERENCE=$(mktemp /tmp/zgrep-benchmark-reference.XXXXXX)
SAMPLES=$(mktemp /tmp/zgrep-benchmark-samples.XXXXXX)
trap 'rm -f "$SINK" "$REFERENCE" "$SAMPLES"' EXIT HUP INT TERM

if [ ! -r "$CORPUS" ]; then
    echo "benchmark corpus not found: $CORPUS" >&2
    echo "run: bench/generate.sh $CORPUS" >&2
    exit 2
fi
if [ ! -x "$ZGREP" ]; then
    echo "zgr binary not found: $ZGREP" >&2
    echo "run: zig build -Doptimize=ReleaseFast" >&2
    exit 2
fi
case $REPEATS in ''|*[!0-9]*|0) echo "repeats must be a positive integer" >&2; exit 2 ;; esac
case $BENCH_BATCHES in ''|*[!0-9]*|0) echo "BENCH_BATCHES must be a positive integer" >&2; exit 2 ;; esac
case $BENCH_CACHE in warm|cold) ;; *) echo "BENCH_CACHE must be warm or cold" >&2; exit 2 ;; esac
case $BENCH_PROFILE in generated|ripgrep-sherlock) ;; *) echo "BENCH_PROFILE must be generated or ripgrep-sherlock" >&2; exit 2 ;; esac
if [ "$BENCH_CACHE" = cold ] && [ "$REPEATS" -ne 1 ]; then
    echo "cold-cache benchmarks require repeats=1; use BENCH_BATCHES for samples" >&2
    exit 2
fi
if [ -n "$BENCH_CPUSET" ] && ! command -v taskset >/dev/null 2>&1; then
    echo "BENCH_CPUSET requires taskset" >&2
    exit 2
fi

run_benchmark_command() {
    if [ -n "$BENCH_CPUSET" ]; then
        taskset -c "$BENCH_CPUSET" "$@"
    else
        "$@"
    fi
}

run_benchmark_stream() {
    if [ -n "$BENCH_CPUSET" ]; then
        taskset -c "$BENCH_CPUSET" cat "$CORPUS" | taskset -c "$BENCH_CPUSET" "$@"
    else
        cat "$CORPUS" | "$@"
    fi
}

prepare_cache() {
    if [ "$BENCH_CACHE" = cold ]; then
        dd if="$CORPUS" iflag=nocache count=0 status=none
    fi
}

report_samples() {
    label=$1
    if [ "$BENCH_BATCHES" -eq 1 ]; then
        awk -v label="$label" -v repeats="$REPEATS" \
            'NR == 1 { printf "%-30s %8.3f ms/run\n", label, $1 / repeats / 1000000 }' \
            "$SAMPLES"
        return
    fi
    sort -n "$SAMPLES" | awk -v label="$label" -v repeats="$REPEATS" '
        { samples[NR] = $1; total += $1 }
        END {
            middle = int((NR + 1) / 2)
            median = NR % 2 ? samples[middle] : (samples[middle] + samples[middle + 1]) / 2
            p95 = samples[int((95 * NR + 99) / 100)]
            scale = repeats * 1000000
            printf "%-12s mean %8.3f  median %8.3f  p95 %8.3f  min %8.3f  max %8.3f ms/run\n", \
                label, total / NR / scale, median / scale, p95 / scale, samples[1] / scale, samples[NR] / scale
        }'
}

benchmark() {
    label=$1
    shift
    if [ "$BENCH_CACHE" = warm ]; then
        run_benchmark_command "$@" >"$SINK" || [ "$?" -eq 1 ]
    fi
    : >"$SAMPLES"
    batch=0
    while [ "$batch" -lt "$BENCH_BATCHES" ]; do
        prepare_cache
        start=$(date +%s%N)
        index=0
        while [ "$index" -lt "$REPEATS" ]; do
            run_benchmark_command "$@" >"$SINK" || [ "$?" -eq 1 ]
            index=$((index + 1))
        done
        end=$(date +%s%N)
        printf '%s\n' "$((end - start))" >>"$SAMPLES"
        batch=$((batch + 1))
    done
    report_samples "$label"
}

benchmark_stream() {
    label=$1
    shift
    if [ "$BENCH_CACHE" = warm ]; then
        run_benchmark_stream "$@" >"$SINK" || [ "$?" -eq 1 ]
    fi
    : >"$SAMPLES"
    batch=0
    while [ "$batch" -lt "$BENCH_BATCHES" ]; do
        prepare_cache
        start=$(date +%s%N)
        index=0
        while [ "$index" -lt "$REPEATS" ]; do
            run_benchmark_stream "$@" >"$SINK" || [ "$?" -eq 1 ]
            index=$((index + 1))
        done
        end=$(date +%s%N)
        printf '%s\n' "$((end - start))" >>"$SAMPLES"
        batch=$((batch + 1))
    done
    report_samples "$label"
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

    run_capture "$REFERENCE" env LC_ALL="$BENCH_LOCALE" grep $grep_flags "$pattern" "$CORPUS"
    reference_status=$captured_status
    run_capture "$SINK" env LC_ALL="$BENCH_LOCALE" "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
        echo "benchmark correctness failure: zgr / $label" >&2
        exit 1
    fi
    run_capture "$SINK" env LC_ALL="$BENCH_LOCALE" rg $ripgrep_flags "$pattern" "$CORPUS"
    if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
        echo "benchmark correctness failure: ripgrep / $label" >&2
        exit 1
    fi
    ZPCRE2_OK=0
    if [ "$HAVE_ZPCRE2" -eq 1 ]; then
        run_capture "$SINK" env LC_ALL="$BENCH_LOCALE" "$ZGREP_ZPCRE2" $zgrep_flags "$pattern" "$CORPUS"
        if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
            echo "benchmark correctness failure: zgr-zpcre2 / $label (skipping timing)" >&2
        else
            ZPCRE2_OK=1
        fi
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
    benchmark zgr env LC_ALL="$BENCH_LOCALE" "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    if [ "${ZPCRE2_OK:-0}" -eq 1 ]; then
        benchmark zgr-zpcre2 env LC_ALL="$BENCH_LOCALE" "$ZGREP_ZPCRE2" $zgrep_flags "$pattern" "$CORPUS"
    fi
    benchmark grep env LC_ALL="$BENCH_LOCALE" grep $grep_flags "$pattern" "$CORPUS"
    benchmark ripgrep env LC_ALL="$BENCH_LOCALE" rg $ripgrep_flags "$pattern" "$CORPUS"
}

benchmark_color_case() {
    label=$1
    zgrep_flags=$2
    grep_flags=$3
    pattern=$4

    printf '%s\n' "$label"
    run_capture "$REFERENCE" env GREP_COLORS= LC_ALL="$BENCH_LOCALE" grep $grep_flags "$pattern" "$CORPUS"
    reference_status=$captured_status
    run_capture "$SINK" env GREP_COLORS= LC_ALL="$BENCH_LOCALE" "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
        echo "benchmark correctness failure: zgr / $label" >&2
        exit 1
    fi
    ZPCRE2_OK=0
    if [ "$HAVE_ZPCRE2" -eq 1 ]; then
        run_capture "$SINK" env GREP_COLORS= LC_ALL="$BENCH_LOCALE" "$ZGREP_ZPCRE2" $zgrep_flags "$pattern" "$CORPUS"
        if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
            echo "benchmark correctness failure: zgr-zpcre2 / $label (skipping timing)" >&2
        else
            ZPCRE2_OK=1
        fi
    fi
    benchmark zgr env GREP_COLORS= LC_ALL="$BENCH_LOCALE" "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    if [ "$ZPCRE2_OK" -eq 1 ]; then
        benchmark zgr-zpcre2 env GREP_COLORS= LC_ALL="$BENCH_LOCALE" "$ZGREP_ZPCRE2" $zgrep_flags "$pattern" "$CORPUS"
    fi
    benchmark grep env GREP_COLORS= LC_ALL="$BENCH_LOCALE" grep $grep_flags "$pattern" "$CORPUS"
}

printf 'corpus: %s (%s bytes), profile: %s, repeats: %s, batches: %s, locale: %s, cache: %s, cpuset: %s, zpcre2: %s\n' \
    "$CORPUS" "$(wc -c <"$CORPUS")" "$BENCH_PROFILE" "$REPEATS" "$BENCH_BATCHES" "$BENCH_LOCALE" \
    "$BENCH_CACHE" "${BENCH_CPUSET:-unrestricted}" "$(if [ "$HAVE_ZPCRE2" -eq 1 ]; then echo "$ZGREP_ZPCRE2"; else echo absent; fi)"
# Case selection is adapted from ripgrep's dual MIT/Unlicense benchsuite at
# commit 3fce3b5bb0236da2df6d99672afb8a719642eca7. Every case is checked against
# GNU grep before it is timed.
if [ "$BENCH_PROFILE" = ripgrep-sherlock ]; then
    alternates='Sherlock Holmes|John Watson|Irene Adler|Inspector Lestrade|Professor Moriarty'
    surrounding='[[:alnum:]_]+[[:space:]]+Holmes[[:space:]]+[[:alnum:]_]+'
    no_literal='[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}'
    benchmark_case 'Sherlock literal' '-a' '-a' '-a' 'Sherlock Holmes'
    benchmark_case 'Sherlock case-insensitive literal' '-a -i' '-a -i' '-a -i' 'Sherlock Holmes'
    benchmark_case 'Sherlock word literal' '-a -n -w' '-a -n -w' '-a -n -w' 'Sherlock Holmes'
    benchmark_case 'Sherlock alternates' '-a -E -n' '-a -E -n' '-a -n' "$alternates"
    benchmark_case 'Sherlock case-insensitive alternates' '-a -E -n -i' '-a -E -n -i' '-a -n -i' "$alternates"
    benchmark_case 'Sherlock surrounding words' '-a -E -n' '-a -E -n' '-a -n' "$surrounding"
    benchmark_case 'Sherlock regexp without literal' '-a -E -n' '-a -E -n' '-a -n' "$no_literal"
    exit 0
fi

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
benchmark_color_case 'literal colored output' \
    '--color=always -F -n -b' '--color=always -F -n -b' 'rare-needle'
benchmark_color_case 'regexp colored output' \
    '--color=always -E -n -b' '--color=always -E -n -b' '[a-z]+-needle'
benchmark_case 'literal output with context' \
    '-a -F -n -C2' '-a -F -n -C2' '-a -F -n -C2' 'rare-needle'
benchmark_case 'regexp output with context' \
    '-a -E -n -b -C2' '-a -E -n -b -C2' '-a -n -b -C2' '[a-z]+-needle'

printf '%s\n' 'rare literal hit from stdin'
benchmark_stream zgr env LC_ALL="$BENCH_LOCALE" "$ZGREP" -F -c rare-needle
if [ "$HAVE_ZPCRE2" -eq 1 ]; then
    benchmark_stream zgr-zpcre2 env LC_ALL="$BENCH_LOCALE" "$ZGREP_ZPCRE2" -F -c rare-needle
fi
benchmark_stream grep env LC_ALL="$BENCH_LOCALE" grep -F -c rare-needle
benchmark_stream ripgrep env LC_ALL="$BENCH_LOCALE" rg -a -F -c rare-needle
