#!/usr/bin/env bash
set -euo pipefail

ZGREP=${1:?missing candidate binary}
ZGREP=$(realpath "$ZGREP")
PROG=$(basename "$ZGREP")
TEST_DIR=$(mktemp -d /tmp/zgrep-regex-fuzz.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
CORPUS="$TEST_DIR/corpus.txt"
SEED=${ZGREP_FUZZ_SEED:-1592594996}
ITERATIONS=${ZGREP_FUZZ_ITERATIONS:-64}

cat >"$CORPUS" <<'EOF'

a
b
aa
ab
ba
aaa
abb
abc
abbc
cab
foo
foobar
foo bar
bar foo
barfoo
_foo_
x9
42
alpha_42
punctuation: foo-bar!
EOF
printf 'crlf foo\r\nlast bar' >>"$CORPUS"

ere_atoms=(
    'a' 'b' '.' '[ab]' '[^x]' '[[:digit:]]' '[[:alpha:]_]'
    'foo' 'bar' '[0-9]'
)
bre_atoms=(
    'a' 'b' '.' '[ab]' '[^x]' '[[:digit:]]' '[[:alpha:]_]'
    'foo' 'bar' '[0-9]'
)

state=$SEED
checks=0

next_random() {
    state=$(((state * 1103515245 + 12345) & 0x7fffffff))
}

compare_case() {
    case_index=$1
    mode=$2
    pattern=$3
    description=$4
    shift 4
    checks=$((checks + 1))

    set +e
    LC_ALL=C grep "$mode" "$@" -- "$pattern" "$CORPUS" \
        >"$TEST_DIR/gnu.out" 2>"$TEST_DIR/gnu.err"
    gnu_status=$?
    LC_ALL=C "$ZGREP" "$mode" "$@" -- "$pattern" "$CORPUS" \
        >"$TEST_DIR/zgrep.out" 2>"$TEST_DIR/zgrep.err"
    zgrep_status=$?
    set -e

    diagnostics_match=true
    if [ "$gnu_status" -eq 2 ]; then
        if [ ! -s "$TEST_DIR/gnu.err" ] || [ ! -s "$TEST_DIR/zgrep.err" ]; then
            diagnostics_match=false
        fi
    fi
    if [ "$gnu_status" -eq "$zgrep_status" ] && \
        cmp -s "$TEST_DIR/gnu.out" "$TEST_DIR/zgrep.out" && \
        [ "$diagnostics_match" = true ]; then
        return
    fi

    printf 'seeded regex differential failure\n' >&2
    printf 'seed=%s case=%s mode=%s operation=%s pattern=<%s>\n' \
        "$SEED" "$case_index" "$mode" "$description" "$pattern" >&2
    printf 'status: GNU=%s zgrep=%s\n' "$gnu_status" "$zgrep_status" >&2
    diff -u "$TEST_DIR/gnu.out" "$TEST_DIR/zgrep.out" >&2 || true
    exit 1
}

exercise_pattern() {
    case_index=$1
    mode=$2
    pattern=$3
    compare_case "$case_index" "$mode" "$pattern" normal -n
    compare_case "$case_index" "$mode" "$pattern" count -c
    compare_case "$case_index" "$mode" "$pattern" inverted-count -v -c
    compare_case "$case_index" "$mode" "$pattern" only-matching -n -b -o
    compare_case "$case_index" "$mode" "$pattern" whole-line -x -n
    compare_case "$case_index" "$mode" "$pattern" whole-word -w -n
}

index=0
while [ "$index" -lt "$ITERATIONS" ]; do
    next_random
    first=${ere_atoms[$((state % ${#ere_atoms[@]}))]}
    next_random
    second=${ere_atoms[$((state % ${#ere_atoms[@]}))]}
    next_random
    third=${ere_atoms[$((state % ${#ere_atoms[@]}))]}
    next_random
    template=$((state % 6))
    case "$template" in
        0) ere_pattern="${first}${second}" ;;
        1) ere_pattern="(${first}|${second})${third}" ;;
        2) ere_pattern="^${first}${second}$" ;;
        3) ere_pattern="(${first}|${second}){1,2}${third}" ;;
        4) ere_pattern="${first}(${second}|${third})" ;;
        5) ere_pattern="(${first}${second}|${third}+)" ;;
    esac
    exercise_pattern "$index" -E "$ere_pattern"

    next_random
    first=${bre_atoms[$((state % ${#bre_atoms[@]}))]}
    next_random
    second=${bre_atoms[$((state % ${#bre_atoms[@]}))]}
    next_random
    third=${bre_atoms[$((state % ${#bre_atoms[@]}))]}
    next_random
    template=$((state % 6))
    case "$template" in
        0) bre_pattern="${first}${second}" ;;
        1) bre_pattern="\\(${first}\\|${second}\\)${third}" ;;
        2) bre_pattern="^${first}${second}$" ;;
        3) bre_pattern="\\(${first}\\|${second}\\)\\{1,2\\}${third}" ;;
        4) bre_pattern="${first}\\(${second}\\|${third}\\)" ;;
        5) bre_pattern="\\(${first}${second}\\|${third}\\+\\)" ;;
    esac
    exercise_pattern "$index" -G "$bre_pattern"
    index=$((index + 1))
done

printf '%s seeded regex differentials passed (%s checks, seed %s)\n' \
    "$PROG" "$checks" "$SEED"
