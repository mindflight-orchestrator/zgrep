#!/bin/sh
set -eu

CORPUS=${1:-/tmp/zgrep-bench-nul.dat}
REPEATS=${2:-20}
BENCH_BATCHES=${BENCH_BATCHES:-1}
ZGREP=${ZGREP:-./zig-out/bin/zgrep}
SINK=$(mktemp /tmp/zgrep-null-benchmark-output.XXXXXX)
REFERENCE=$(mktemp /tmp/zgrep-null-benchmark-reference.XXXXXX)
SAMPLES=$(mktemp /tmp/zgrep-null-benchmark-samples.XXXXXX)
trap 'rm -f "$SINK" "$REFERENCE" "$SAMPLES"' EXIT HUP INT TERM

if [ ! -r "$CORPUS" ]; then
    echo "NUL benchmark corpus not found: $CORPUS" >&2
    echo "run: bench/generate.sh $CORPUS 3000000 nul" >&2
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
    echo "zgrep binary not found: $ZGREP" >&2
    exit 2
fi
case $REPEATS in ''|*[!0-9]*|0) echo "repeats must be a positive integer" >&2; exit 2 ;; esac
case $BENCH_BATCHES in ''|*[!0-9]*|0) echo "BENCH_BATCHES must be a positive integer" >&2; exit 2 ;; esac

run_capture() {
    output=$1
    shift
    set +e
    "$@" >"$output"
    captured_status=$?
    set -e
}

benchmark() {
    label=$1
    shift
    "$@" >"$SINK" || [ "$?" -eq 1 ]
    : >"$SAMPLES"
    batch=0
    while [ "$batch" -lt "$BENCH_BATCHES" ]; do
        start=$(date +%s%N)
        index=0
        while [ "$index" -lt "$REPEATS" ]; do
            "$@" >"$SINK" || [ "$?" -eq 1 ]
            index=$((index + 1))
        done
        end=$(date +%s%N)
        printf '%s\n' "$((end - start))" >>"$SAMPLES"
        batch=$((batch + 1))
    done
    report_samples "$label"
}

benchmark_case() {
    label=$1
    zgrep_flags=$2
    grep_flags=$3
    ripgrep_flags=$4
    pattern=$5

    run_capture "$REFERENCE" env LC_ALL=C grep $grep_flags "$pattern" "$CORPUS"
    reference_status=$captured_status
    run_capture "$SINK" env LC_ALL=C "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    if [ "$captured_status" -ne "$reference_status" ] || ! cmp -s "$REFERENCE" "$SINK"; then
        echo "NUL benchmark correctness failure: zgrep / $label" >&2
        exit 1
    fi
    run_capture "$SINK" env LC_ALL=C rg $ripgrep_flags "$pattern" "$CORPUS"
    ripgrep_matches=false
    case " $ripgrep_flags " in
        *' -c '*)
            if tr '\0' '\n' <"$SINK" | cmp -s "$REFERENCE" -; then
                ripgrep_matches=true
            fi
            ;;
        *)
            if cmp -s "$REFERENCE" "$SINK"; then
                ripgrep_matches=true
            fi
            ;;
    esac
    if [ "$captured_status" -ne "$reference_status" ] || [ "$ripgrep_matches" != true ]; then
        echo "NUL benchmark correctness failure: ripgrep / $label" >&2
        exit 1
    fi

    printf '%s\n' "$label"
    benchmark zgrep env LC_ALL=C "$ZGREP" $zgrep_flags "$pattern" "$CORPUS"
    benchmark grep env LC_ALL=C grep $grep_flags "$pattern" "$CORPUS"
    benchmark ripgrep env LC_ALL=C rg $ripgrep_flags "$pattern" "$CORPUS"
}

printf 'NUL corpus: %s (%s bytes), repeats: %s, batches: %s\n' \
    "$CORPUS" "$(wc -c <"$CORPUS")" "$REPEATS" "$BENCH_BATCHES"
benchmark_case 'NUL literal miss' \
    '-z -F -c' '-z -F -c' '--null-data -F -c --include-zero' 'not-present-anywhere'
benchmark_case 'NUL rare literal hit' \
    '-z -F -c' '-z -F -c' '--null-data -F -c' 'rare-needle'
benchmark_case 'NUL case-insensitive literal' \
    '-z -F -i -c' '-z -F -i -c' '--null-data -F -i -c' 'RARE-NEEDLE'
benchmark_case 'NUL literal alternation' \
    '-z -E -c' '-z -E -c' '--null-data -c' \
    'rare-needle|status=500|route=/api/item/42|latency_us=999'
benchmark_case 'NUL regexp without literal' \
    '-z -E -c' '-z -E -c' '--null-data -c' \
    '[[:alnum:]_]{4}[[:space:]]+[[:alnum:]_]{7}'
benchmark_case 'NUL literal numbered output' \
    '-z -F -n' '-z -F -n' '--null-data -F -n' 'rare-needle'
