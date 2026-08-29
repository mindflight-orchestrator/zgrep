#!/bin/sh
set -eu

TREE=${1:?usage: bench/run-tree.sh TREE [PATTERN] [REPEATS]}
PATTERN=${2:-SearcherBuilder}
REPEATS=${3:-20}
BENCH_BATCHES=${BENCH_BATCHES:-1}
ZGREP=${ZGR:-${ZGREP:-./zig-out/bin/zgr}}
ZGRC=${ZGRC:-$(dirname "$ZGREP")/zgrc}
BENCH_LOCALE=${BENCH_LOCALE:-C}
BENCH_CACHE=${BENCH_CACHE:-warm}
BENCH_CPUSET=${BENCH_CPUSET:-}
BENCH_PROFILE=${BENCH_PROFILE:-generic}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SINK=$(mktemp /tmp/zgrep-tree-benchmark-output.XXXXXX)
REFERENCE=$(mktemp /tmp/zgrep-tree-benchmark-reference.XXXXXX)
CANDIDATE=$(mktemp /tmp/zgrep-tree-benchmark-candidate.XXXXXX)
SAMPLES=$(mktemp /tmp/zgrep-tree-benchmark-samples.XXXXXX)
CACHE_EVICTOR=
trap 'rm -f "$SINK" "$REFERENCE" "$CANDIDATE" "$SAMPLES"; if [ -n "$CACHE_EVICTOR" ]; then rm -f "$CACHE_EVICTOR"; fi' EXIT HUP INT TERM

if [ ! -d "$TREE" ]; then
    echo "benchmark tree not found: $TREE" >&2
    exit 2
fi

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
if [ ! -x "$ZGREP" ]; then
    echo "zgr binary not found: $ZGREP" >&2
    echo "run: zig build -Doptimize=ReleaseFast" >&2
    exit 2
fi
if [ ! -x "$ZGRC" ]; then
    echo "zgrc binary not found: $ZGRC" >&2
    echo "run: zig build -Doptimize=ReleaseFast" >&2
    exit 2
fi
case $REPEATS in ''|*[!0-9]*|0) echo "repeats must be a positive integer" >&2; exit 2 ;; esac
case $BENCH_BATCHES in ''|*[!0-9]*|0) echo "BENCH_BATCHES must be a positive integer" >&2; exit 2 ;; esac
case $BENCH_CACHE in warm|cold) ;; *) echo "BENCH_CACHE must be warm or cold" >&2; exit 2 ;; esac
case $BENCH_PROFILE in generic|ripgrep-linux|ripgrep-linux-default) ;; *) echo "BENCH_PROFILE must be generic, ripgrep-linux, or ripgrep-linux-default" >&2; exit 2 ;; esac
if [ "$BENCH_CACHE" = cold ] && [ "$REPEATS" -ne 1 ]; then
    echo "cold-cache benchmarks require repeats=1; use BENCH_BATCHES for samples" >&2
    exit 2
fi
if [ -n "$BENCH_CPUSET" ] && ! command -v taskset >/dev/null 2>&1; then
    echo "BENCH_CPUSET requires taskset" >&2
    exit 2
fi
if [ "$BENCH_CACHE" = cold ]; then
    if ! command -v cc >/dev/null 2>&1; then
        echo "BENCH_CACHE=cold requires a C compiler" >&2
        exit 2
    fi
    CACHE_EVICTOR=$(mktemp /tmp/zgrep-tree-cache-evictor.XXXXXX)
    cc -std=c11 -O2 -Wall -Wextra -Werror \
        "$SCRIPT_DIR/evict-tree-cache.c" -o "$CACHE_EVICTOR"
fi

run_benchmark_command() {
    if [ -n "$BENCH_CPUSET" ]; then
        taskset -c "$BENCH_CPUSET" "$@"
    else
        "$@"
    fi
}

prepare_cache() {
    if [ "$BENCH_CACHE" = cold ]; then
        "$CACHE_EVICTOR" "$TREE"
    fi
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

run_sorted() {
    output=$1
    shift
    set +e
    run_benchmark_command "$@" >"$SINK"
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

    run_sorted "$REFERENCE" env LC_ALL="$BENCH_LOCALE" grep $grep_flags "$pattern" "$TREE" || [ "$?" -eq 1 ]
    run_sorted "$CANDIDATE" env LC_ALL="$BENCH_LOCALE" "$ZGREP" $zgrep_flags "$pattern" "$TREE" || [ "$?" -eq 1 ]
    if ! cmp -s "$REFERENCE" "$CANDIDATE"; then
        echo "recursive result mismatch: zgr / $label" >&2
        diff -u "$REFERENCE" "$CANDIDATE" >&2 || true
        exit 1
    fi
    run_sorted "$CANDIDATE" env LC_ALL="$BENCH_LOCALE" rg $ripgrep_flags "$pattern" "$TREE" || [ "$?" -eq 1 ]
    if ! cmp -s "$REFERENCE" "$CANDIDATE"; then
        echo "recursive result mismatch: ripgrep / $label" >&2
        diff -u "$REFERENCE" "$CANDIDATE" >&2 || true
        exit 1
    fi
    run_sorted "$CANDIDATE" env LC_ALL="$BENCH_LOCALE" "$ZGRC" $zgrep_flags "$pattern" "$TREE" || [ "$?" -eq 1 ]
    if ! cmp -s "$REFERENCE" "$CANDIDATE"; then
        echo "recursive result mismatch: zgrc / $label" >&2
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
    benchmark zgr env LC_ALL="$BENCH_LOCALE" "$ZGREP" $zgrep_flags "$pattern" "$TREE"
    benchmark zgrc env LC_ALL="$BENCH_LOCALE" "$ZGRC" $zgrep_flags "$pattern" "$TREE"
    benchmark grep env LC_ALL="$BENCH_LOCALE" grep $grep_flags "$pattern" "$TREE"
    benchmark ripgrep env LC_ALL="$BENCH_LOCALE" rg $ripgrep_flags "$pattern" "$TREE"
}

files=$(find "$TREE" -type f | wc -l)
bytes=$(find "$TREE" -type f -printf '%s\n' | awk '{ total += $1 } END { print total + 0 }')
printf 'tree: %s (%s files, %s bytes), profile: %s, pattern: %s, repeats: %s, batches: %s, locale: %s, cache: %s, cpuset: %s, zgr: %s, zgrc: %s\n' \
    "$TREE" "$files" "$bytes" "$BENCH_PROFILE" "$PATTERN" "$REPEATS" "$BENCH_BATCHES" \
    "$BENCH_LOCALE" "$BENCH_CACHE" "${BENCH_CPUSET:-unrestricted}" "$ZGREP" "$ZGRC"
if [ "$BENCH_PROFILE" = ripgrep-linux ] || [ "$BENCH_PROFILE" = ripgrep-linux-default ]; then
    no_literal='[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}'
    alternates='ERR_SYS|PME_TURN_OFF|LINK_REQ_RST|CFG_BME_EVT'
    if [ "$BENCH_PROFILE" = ripgrep-linux-default ]; then
        zgrep_base='-r -n'
        grep_base='-r -n'
        ripgrep_base='-uuu -n'
    else
        zgrep_base='-a -r -n'
        grep_base='-a -r -n'
        ripgrep_base='-a -uuu -n'
    fi
    benchmark_case 'Linux literal' "$zgrep_base" "$grep_base" "$ripgrep_base" 'PM_RESUME'
    benchmark_case 'Linux case-insensitive literal' "$zgrep_base -i" "$grep_base -i" "$ripgrep_base -i" 'PM_RESUME'
    benchmark_case 'Linux regexp literal suffix' "$zgrep_base -E" "$grep_base -E" "$ripgrep_base" '[A-Z]+_RESUME'
    benchmark_case 'Linux word literal' "$zgrep_base -w" "$grep_base -w" "$ripgrep_base -w" 'PM_RESUME'
    benchmark_case 'Linux regexp without literal' "$zgrep_base -E" "$grep_base -E" "$ripgrep_base" "$no_literal"
    benchmark_case 'Linux alternates' "$zgrep_base -E" "$grep_base -E" "$ripgrep_base" "$alternates"
    benchmark_case 'Linux case-insensitive alternates' "$zgrep_base -E -i" "$grep_base -E -i" "$ripgrep_base -i" "$alternates"
    exit 0
fi

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
