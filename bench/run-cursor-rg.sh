#!/bin/sh
# Compare Cursor's bundled ripgrep (or rg on PATH) with zgr on a source tree
# and an optional generated corpus. This is not a GNU-correctness gate:
# default Cursor rg honors gitignore and skips hidden/binary files; zgr -r
# does not. Search diagnostics (including GNU-style binary-file notices) are
# discarded so the log stays comparable.
set -eu

TREE=${1:-}
REPEATS=${2:-5}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
if [ -z "$TREE" ]; then
    TREE=$REPO_ROOT
fi
BENCH_BATCHES=${BENCH_BATCHES:-1}
ZGREP=${ZGR:-${ZGREP:-$REPO_ROOT/zig-out/bin/zgr}}
ZGRC=${ZGRC:-$(dirname "$ZGREP")/zgrc}
BENCH_LOCALE=${BENCH_LOCALE:-C}
BENCH_CPUSET=${BENCH_CPUSET:-}
TREE_PATTERN=${TREE_PATTERN:-Matcher}
DIALECT_PATTERN=${DIALECT_PATTERN:-'error|warning'}
BENCH_EXCLUDE_DIRS=${BENCH_EXCLUDE_DIRS:-.git .zig-cache zig-out}
CORPUS=${CORPUS:-}
CORPUS_LINES=${CORPUS_LINES:-100000}
SINK=$(mktemp /tmp/zgrep-cursor-rg-output.XXXXXX)
SAMPLES=$(mktemp /tmp/zgrep-cursor-rg-samples.XXXXXX)
trap 'rm -f "$SINK" "$SAMPLES"' EXIT HUP INT TERM

if [ ! -d "$TREE" ]; then
    echo "benchmark tree not found: $TREE" >&2
    exit 2
fi
if [ ! -x "$ZGREP" ]; then
    echo "zgr binary not found: $ZGREP" >&2
    echo "run: zig build -Doptimize=ReleaseFast" >&2
    exit 2
fi
case $REPEATS in ''|*[!0-9]*|0) echo "repeats must be a positive integer" >&2; exit 2 ;; esac
case $BENCH_BATCHES in ''|*[!0-9]*|0) echo "BENCH_BATCHES must be a positive integer" >&2; exit 2 ;; esac
if [ -n "$BENCH_CPUSET" ] && ! command -v taskset >/dev/null 2>&1; then
    echo "BENCH_CPUSET requires taskset" >&2
    exit 2
fi

find_cursor_rg() {
    if [ -n "${CURSOR_RG:-}" ]; then
        printf '%s\n' "$CURSOR_RG"
        return 0
    fi
    for candidate in \
        /tmp/.mount_cursor*/usr/share/cursor/resources/app/node_modules/@vscode/ripgrep/bin/rg \
        /usr/share/cursor/resources/app/node_modules/@vscode/ripgrep/bin/rg \
        "$HOME/.local/share/cursor/resources/app/node_modules/@vscode/ripgrep/bin/rg"
    do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v rg >/dev/null 2>&1; then
        command -v rg
        return 0
    fi
    return 1
}

if ! RG=$(find_cursor_rg); then
    echo "ripgrep not found. Set CURSOR_RG or install rg." >&2
    echo "Cursor AppImage ships rg under /tmp/.mount_cursor*/.../node_modules/@vscode/ripgrep/bin/rg" >&2
    exit 2
fi
if [ ! -x "$RG" ]; then
    echo "ripgrep binary is not executable: $RG" >&2
    exit 2
fi

HAVE_GREP=0
if command -v grep >/dev/null 2>&1; then
    HAVE_GREP=1
fi
HAVE_ZGRC=0
if [ -x "$ZGRC" ]; then
    HAVE_ZGRC=1
fi

ZGR_EXCLUDES=
GREP_EXCLUDES=
for dir in $BENCH_EXCLUDE_DIRS; do
    ZGR_EXCLUDES="$ZGR_EXCLUDES --exclude-dir=$dir"
    GREP_EXCLUDES="$GREP_EXCLUDES --exclude-dir=$dir"
done

run_benchmark_command() {
    if [ -n "$BENCH_CPUSET" ]; then
        taskset -c "$BENCH_CPUSET" "$@"
    else
        "$@"
    fi
}

report_samples() {
    label=$1
    if [ "$BENCH_BATCHES" -eq 1 ]; then
        awk -v label="$label" -v repeats="$REPEATS" \
            'NR == 1 { printf "%-42s %8.3f ms/run\n", label, $1 / repeats / 1000000 }' \
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
            printf "%-42s mean %8.3f  median %8.3f  p95 %8.3f  min %8.3f  max %8.3f ms/run\n", \
                label, total / NR / scale, median / scale, p95 / scale, samples[1] / scale, samples[NR] / scale
        }'
}

benchmark() {
    label=$1
    shift
        run_benchmark_command "$@" >"$SINK" 2>/dev/null || [ "$?" -eq 1 ]
    : >"$SAMPLES"
    batch=0
    while [ "$batch" -lt "$BENCH_BATCHES" ]; do
        start=$(date +%s%N)
        index=0
        while [ "$index" -lt "$REPEATS" ]; do
            run_benchmark_command "$@" >"$SINK" 2>/dev/null || [ "$?" -eq 1 ]
            index=$((index + 1))
        done
        end=$(date +%s%N)
        printf '%s\n' "$((end - start))" >>"$SAMPLES"
        batch=$((batch + 1))
    done
    report_samples "$label"
}

count_lines() {
    wc -l <"$SINK" | tr -d ' '
}

print_count() {
    printf '  %s lines\n' "$(count_lines)"
}

rg_file_count() {
    run_benchmark_command env LC_ALL="$BENCH_LOCALE" "$RG" --files "$@" 2>/dev/null | wc -l | tr -d ' '
}

printf 'tree: %s\n' "$TREE"
printf 'repeats: %s, batches: %s, locale: %s, cpuset: %s, pattern: %s\n' \
    "$REPEATS" "$BENCH_BATCHES" "$BENCH_LOCALE" "${BENCH_CPUSET:-unrestricted}" "$TREE_PATTERN"
printf 'cursor rg: %s\n' "$RG"
"$RG" --version | awk 'NR <= 3 { print "  " $0 }'
printf 'zgr: %s\n' "$ZGREP"
"$ZGREP" --version | awk 'NR <= 2 { print "  " $0 }'
if [ "$HAVE_ZGRC" -eq 1 ]; then
    printf 'zgrc: %s\n' "$ZGRC"
fi
if [ "$HAVE_GREP" -eq 1 ]; then
    grep --version | awk 'NR == 1 { print "grep: " $0 }'
fi
printf 'exclude-dir: %s\n' "$BENCH_EXCLUDE_DIRS"
printf 'files walked by cursor rg --files: %s\n' "$(rg_file_count "$TREE")"
printf 'files walked by cursor rg --files --no-ignore --hidden: %s\n' \
    "$(rg_file_count --no-ignore --hidden "$TREE")"
printf 'files found by find -type f: %s\n' "$(find "$TREE" -type f | wc -l | tr -d ' ')"

printf '\n%s\n' "=== tree search: $TREE_PATTERN (line numbers) ==="
benchmark 'cursor rg' \
    env LC_ALL="$BENCH_LOCALE" "$RG" -n "$TREE_PATTERN" "$TREE"
print_count
benchmark 'zgr -r (GNU recursive)' \
    env LC_ALL="$BENCH_LOCALE" "$ZGREP" -r -n "$TREE_PATTERN" "$TREE"
print_count
benchmark 'zgr -r exclude caches' \
    env LC_ALL="$BENCH_LOCALE" "$ZGREP" -r -n $ZGR_EXCLUDES "$TREE_PATTERN" "$TREE"
print_count
if [ "$HAVE_GREP" -eq 1 ]; then
    benchmark 'GNU grep -r exclude caches' \
        env LC_ALL="$BENCH_LOCALE" grep -r -n $GREP_EXCLUDES "$TREE_PATTERN" "$TREE"
    print_count
fi

printf '\n%s\n' "=== tree search: $TREE_PATTERN (files with matches) ==="
benchmark 'cursor rg -l' \
    env LC_ALL="$BENCH_LOCALE" "$RG" -l "$TREE_PATTERN" "$TREE"
print_count
benchmark 'zgr -rl exclude caches' \
    env LC_ALL="$BENCH_LOCALE" "$ZGREP" -r -l $ZGR_EXCLUDES "$TREE_PATTERN" "$TREE"
print_count
benchmark 'zgr -rl full tree' \
    env LC_ALL="$BENCH_LOCALE" "$ZGREP" -r -l "$TREE_PATTERN" "$TREE"
print_count

if [ -d "$TREE/src" ]; then
    printf '\n%s\n' "=== src/ only ==="
    benchmark 'cursor rg src' \
        env LC_ALL="$BENCH_LOCALE" "$RG" -n "$TREE_PATTERN" "$TREE/src"
    print_count
    benchmark 'zgr -r src' \
        env LC_ALL="$BENCH_LOCALE" "$ZGREP" -r -n "$TREE_PATTERN" "$TREE/src"
    print_count
    if [ "$HAVE_GREP" -eq 1 ]; then
        benchmark 'GNU grep -r src' \
            env LC_ALL="$BENCH_LOCALE" grep -r -n "$TREE_PATTERN" "$TREE/src"
        print_count
    fi
fi

DIALECT_ROOT=$TREE
if [ -d "$TREE/src" ]; then
    DIALECT_ROOT=$TREE/src
fi
printf '\n%s\n' "=== dialect: $DIALECT_PATTERN in $DIALECT_ROOT ==="
run_benchmark_command env LC_ALL="$BENCH_LOCALE" "$RG" -n "$DIALECT_PATTERN" "$DIALECT_ROOT" >"$SINK" 2>/dev/null || [ "$?" -eq 1 ]
printf 'cursor rg (Rust regex)                      %s hits\n' "$(count_lines)"
run_benchmark_command env LC_ALL="$BENCH_LOCALE" "$ZGREP" -r -n "$DIALECT_PATTERN" "$DIALECT_ROOT" >"$SINK" 2>/dev/null || [ "$?" -eq 1 ]
printf 'zgr default BRE                             %s hits\n' "$(count_lines)"
run_benchmark_command env LC_ALL="$BENCH_LOCALE" "$ZGREP" -E -r -n "$DIALECT_PATTERN" "$DIALECT_ROOT" >"$SINK" 2>/dev/null || [ "$?" -eq 1 ]
printf 'zgr -E                                      %s hits\n' "$(count_lines)"

if [ -z "$CORPUS" ]; then
    CORPUS=/tmp/zgrep-cursor-rg-bench.txt
fi
if [ ! -r "$CORPUS" ]; then
    echo
    echo "generating corpus: $CORPUS ($CORPUS_LINES records)"
    "$SCRIPT_DIR/generate.sh" "$CORPUS" "$CORPUS_LINES"
fi
if [ ! -r "$CORPUS" ]; then
    echo "corpus not found: $CORPUS" >&2
    exit 2
fi

HAVE_PCRE=0
if "$RG" --pcre2-version >/dev/null 2>&1; then
    HAVE_PCRE=1
fi

printf '\ncorpus: %s (%s bytes)\n' "$CORPUS" "$(wc -c <"$CORPUS" | tr -d ' ')"
printf '%s\n' "=== generated file ==="

corpus_case() {
    label=$1
    zgr_flags=$2
    grep_flags=$3
    rg_flags=$4
    pattern=$5

    printf '%s\n' "$label"
    benchmark '  cursor rg' \
        env LC_ALL="$BENCH_LOCALE" "$RG" $rg_flags "$pattern" "$CORPUS"
    benchmark '  zgr' \
        env LC_ALL="$BENCH_LOCALE" "$ZGREP" $zgr_flags "$pattern" "$CORPUS"
    if [ "$HAVE_ZGRC" -eq 1 ]; then
        benchmark '  zgrc' \
            env LC_ALL="$BENCH_LOCALE" "$ZGRC" $zgr_flags "$pattern" "$CORPUS"
    fi
    if [ "$HAVE_GREP" -eq 1 ] && [ -n "$grep_flags" ]; then
        benchmark '  grep' \
            env LC_ALL="$BENCH_LOCALE" grep $grep_flags "$pattern" "$CORPUS"
    fi
}

corpus_case 'literal miss' \
    '-F -c' '-F -c' '-c' 'this-string-is-not-in-the-corpus-at-all'
corpus_case 'rare literal hit' \
    '-F -c' '-F -c' '-c' 'rare-needle'
corpus_case 'word literal' \
    '-F -c -w' '-F -c -w' '-c -w' 'rare-needle'
corpus_case 'literal case-insensitive' \
    '-F -c -i' '-F -c -i' '-c -i' 'RARE-NEEDLE'
corpus_case 'extended regexp' \
    '-E -c' '-E -c' '-c' 'status=(200|500)'
corpus_case 'regexp with inner literal' \
    '-E -c' '-E -c' '-c' \
    'route=/api/item/[[:digit:]]+[[:space:]]+status=500'
corpus_case 'literal output with line numbers' \
    '-F -n' '-F -n' '-n' 'rare-needle'
if [ "$HAVE_PCRE" -eq 1 ]; then
    corpus_case 'PCRE -P' \
        '-P -c' '' '-P -c' 'latency_us=\d+'
fi
