#!/usr/bin/env bash
set -euo pipefail

# Regression scenarios below are adapted to GNU grep semantics from ripgrep's
# dual MIT/Unlicense test suite at commit
# 3fce3b5bb0236da2df6d99672afb8a719642eca7. In particular, see f159 in
# tests/feature.rs and r1159, r1176, r1259, r1334 and r2658 in
# tests/regression.rs. NUL-data coverage also adapts f993 from feature.rs.

ZGREP=${1:?missing candidate binary}
ZGREP=$(realpath "$ZGREP")
PROG=$(basename "$ZGREP")
TEST_DIR=$(mktemp -d /tmp/zgrep-differential.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
CORPUS="$TEST_DIR/corpus.txt"
mkdir -p "$TEST_DIR/tree/sub"
mkdir -p "$TEST_DIR/symlink-tree/real/sub"
mkdir -p "$TEST_DIR/parallel-tree"
mkdir -p "$TEST_DIR/filter-tree/sub/nested" "$TEST_DIR/filter-tree/subskip"
mkdir -p "$TEST_DIR/device-tree"
mkfifo "$TEST_DIR/device-fifo"
mkfifo "$TEST_DIR/device-tree/input.fifo"

cat >"$CORPUS" <<'EOF'
alpha
Beta 42
alphabet soup
warning: disk almost full
error: request 500

literal .* text
alpha beta alpha
last line
EOF
printf 'tree alpha\n' >"$TEST_DIR/tree/root.txt"
printf 'tree warning\n' >"$TEST_DIR/tree/sub/nested.txt"
printf 'symlink needle\n' >"$TEST_DIR/symlink-tree/real/sub/file.txt"
ln -s real "$TEST_DIR/symlink-tree/link-dir"
ln -s real/sub/file.txt "$TEST_DIR/symlink-tree/link-file"
ln -s .. "$TEST_DIR/symlink-tree/real/sub/loop"
for index in $(seq 1 130); do
    if [ $((index % 3)) -eq 0 ]; then
        printf 'parallel needle %s\n' "$index" >"$TEST_DIR/parallel-tree/file-$index.txt"
    else
        printf 'parallel hay %s\n' "$index" >"$TEST_DIR/parallel-tree/file-$index.txt"
    fi
done
printf 'filter needle\n' >"$TEST_DIR/filter-tree/a.c"
printf 'filter needle\n' >"$TEST_DIR/filter-tree/b.h"
printf 'filter needle\n' >"$TEST_DIR/filter-tree/.hidden.c"
printf 'filter needle\n' >"$TEST_DIR/filter-tree/file7.c"
printf 'filter needle\n' >"$TEST_DIR/filter-tree/sub/c.c"
printf 'filter needle\n' >"$TEST_DIR/filter-tree/sub/d.txt"
printf 'filter needle\n' >"$TEST_DIR/filter-tree/sub/nested/e.c"
printf 'filter needle\n' >"$TEST_DIR/filter-tree/subskip/f.c"
printf '*.txt\nf.c\n' >"$TEST_DIR/filter-globs.txt"
printf 'warning\nerror\n' >"$TEST_DIR/patterns.txt"
: >"$TEST_DIR/empty-patterns.txt"
printf '\n' >"$TEST_DIR/blank-pattern.txt"
printf '[foo]' >"$TEST_DIR/pattern-no-newline.txt"
printf 'fz\n' >"$TEST_DIR/pattern-no-newline-corpus.txt"
printf 'test\ntest\n' >"$TEST_DIR/max-count-corpus.txt"
awk 'BEGIN { for (i = 0; i < 200000; i++) print "alpha" }' >"$TEST_DIR/broken-pipe.txt"
printf 'one\ntwo' >"$TEST_DIR/no-final-newline.txt"
printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n' >"$TEST_DIR/context.txt"
printf 'foo\nctx\ngap\nctx\nfoo\nctx' >"$TEST_DIR/context-groups.txt"
printf 'a\nmatch\nb\n' >"$TEST_DIR/context-one.txt"
printf 'c\nmatch\nd\n' >"$TEST_DIR/context-two.txt"
printf 'a\nb\nc\nd\ne\nd\ne\nd\ne\n' >"$TEST_DIR/context-max.txt"
printf 'before needle\nbinary\0payload\nHeaven after\n' >"$TEST_DIR/binary-small.txt"
printf 'needle\n' >"$TEST_DIR/binary-late.txt"
head -c 300000 /dev/zero | tr '\0' x >>"$TEST_DIR/binary-late.txt"
printf '\0\nHeaven\n' >>"$TEST_DIR/binary-late.txt"
cat >"$TEST_DIR/ere-prefilter.txt" <<'EOF'
foo
bar
foobar
fobar
foo-required
bar-required
alpha-needle
status=200
status=500
EOF
: >"$TEST_DIR/duplicate-patterns.txt"
for _ in $(seq 1 40); do
    printf '1.208.0.0/12\n' >>"$TEST_DIR/duplicate-patterns.txt"
done
printf '1.208.0.0/12\n' >"$TEST_DIR/duplicate-corpus.txt"
head -c 5242880 /dev/zero | tr '\0' x >"$TEST_DIR/long-line.txt"
printf ' rare-needle\nlast\n' >>"$TEST_DIR/long-line.txt"
head -c 262137 /dev/zero | tr '\0' x >"$TEST_DIR/stream-boundary.txt"
printf ' needle\nafter needle\n' >>"$TEST_DIR/stream-boundary.txt"
head -c 262137 /dev/zero | tr '\0' x >"$TEST_DIR/stream-word-boundary.txt"
printf ' needlex\nneedle!\n' >>"$TEST_DIR/stream-word-boundary.txt"
printf 'one\ninside\0two match\0three match' >"$TEST_DIR/null-records.txt"
printf 'foo\0bar\0\0\0baz\0' >"$TEST_DIR/null-empty-records.txt"
printf 'match\0ctx\0gap1\0gap2\0match\0ctx\0' >"$TEST_DIR/null-context-groups.txt"

compare_file() {
    description=$1
    corpus=$2
    shift 2
    if ! diff -u \
        <(LC_ALL=C grep "$@" "$corpus") \
        <(LC_ALL=C "$ZGREP" "$@" "$corpus"); then
        echo "differential failure: $description" >&2
        exit 1
    fi
}

compare() {
    description=$1
    shift
    compare_file "$description" "$CORPUS" "$@"
}

compare_color_file() {
    description=$1
    corpus=$2
    colors=$3
    shift 3
    set +e
    GREP_COLORS=$colors LC_ALL=C grep "$@" "$corpus" \
        >"$TEST_DIR/grep-color.out" 2>"$TEST_DIR/grep-color.err"
    grep_status=$?
    GREP_COLORS=$colors LC_ALL=C "$ZGREP" "$@" "$corpus" \
        >"$TEST_DIR/zgrep-color.out" 2>"$TEST_DIR/zgrep-color.err"
    zgrep_status=$?
    set -e
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-color.err" >"$TEST_DIR/grep-color-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/grep-color.out" "$TEST_DIR/zgrep-color.out" || \
        ! cmp -s "$TEST_DIR/grep-color-normalized.err" "$TEST_DIR/zgrep-color.err"; then
        echo "color differential failure: $description" >&2
        echo "GNU stdout:" >&2
        od -An -v -tx1 "$TEST_DIR/grep-color.out" >&2
        echo "zgrep stdout:" >&2
        od -An -v -tx1 "$TEST_DIR/zgrep-color.out" >&2
        exit 1
    fi
}

command_status=0
capture_status() {
    set +e
    "$@" >/dev/null 2>/dev/null
    command_status=$?
    set -e
}

compare_status() {
    description=$1
    shift
    capture_status env LC_ALL=C grep "$@"
    grep_status=$command_status
    capture_status env LC_ALL=C "$ZGREP" "$@"
    zgrep_status=$command_status
    if [ "$grep_status" -ne "$zgrep_status" ]; then
        echo "status failure: $description (grep=$grep_status, zgrep=$zgrep_status)" >&2
        exit 1
    fi
}

compare_timeout_status() {
    description=$1
    shift
    capture_status timeout 5 env LC_ALL=C grep "$@"
    grep_status=$command_status
    capture_status timeout 5 env LC_ALL=C "$ZGREP" "$@"
    zgrep_status=$command_status
    if [ "$grep_status" -ne "$zgrep_status" ]; then
        echo "timeout status failure: $description (grep=$grep_status, zgrep=$zgrep_status)" >&2
        exit 1
    fi
}

compare_broken_pipe() {
    description=$1
    shift
    set +e
    (
        trap '' PIPE
        exec env LC_ALL=C grep "$@" alpha "$TEST_DIR/broken-pipe.txt"
    ) 2>"$TEST_DIR/grep-broken-pipe.err" | {
            head -n1 >"$TEST_DIR/grep-broken-pipe.out"
            sleep 0.05
        }
    grep_pipeline_status=("${PIPESTATUS[@]}")
    (
        trap '' PIPE
        exec env LC_ALL=C "$ZGREP" "$@" alpha "$TEST_DIR/broken-pipe.txt"
    ) 2>"$TEST_DIR/zgrep-broken-pipe.err" | {
            head -n1 >"$TEST_DIR/zgrep-broken-pipe.out"
            sleep 0.05
        }
    zgrep_pipeline_status=("${PIPESTATUS[@]}")
    set -e

    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-broken-pipe.err" \
        >"$TEST_DIR/grep-broken-pipe-normalized.err"
    if [ "${grep_pipeline_status[0]}" -ne "${zgrep_pipeline_status[0]}" ] || \
        ! cmp -s "$TEST_DIR/grep-broken-pipe.out" "$TEST_DIR/zgrep-broken-pipe.out" || \
        ! cmp -s "$TEST_DIR/grep-broken-pipe-normalized.err" "$TEST_DIR/zgrep-broken-pipe.err"; then
        echo "broken-pipe differential failure: $description" >&2
        echo "GNU status/stderr: ${grep_pipeline_status[0]}" >&2
        cat "$TEST_DIR/grep-broken-pipe.err" >&2
        echo "zgrep status/stderr: ${zgrep_pipeline_status[0]}" >&2
        cat "$TEST_DIR/zgrep-broken-pipe.err" >&2
        exit 1
    fi
}

assert_line_buffered_context() {
    implementation=$1
    implementation_name=${implementation##*/}
    coproc LINE_BUFFERED_SEARCH { LC_ALL=C "$implementation" --line-buffered -A1 needle; }
    input_fd=${LINE_BUFFERED_SEARCH[1]}
    output_fd=${LINE_BUFFERED_SEARCH[0]}
    search_pid=$LINE_BUFFERED_SEARCH_PID

    printf 'needle first\n' >&$input_fd
    if ! IFS= read -r -t 5 first_line <&$output_fd || [ "$first_line" != 'needle first' ]; then
        eval "exec ${input_fd}>&-"
        wait "$search_pid" || true
        echo "line-buffered failure before EOF: $implementation_name" >&2
        exit 1
    fi
    printf 'after\n' >&$input_fd
    if ! IFS= read -r -t 5 second_line <&$output_fd || [ "$second_line" != 'after' ]; then
        eval "exec ${input_fd}>&-"
        wait "$search_pid" || true
        echo "line-buffered context failure before EOF: $implementation_name" >&2
        exit 1
    fi
    eval "exec ${input_fd}>&-"
    wait "$search_pid"
}

compare_fifo_read() {
    description=$1
    fifo=$2
    search_path=$3
    shift 3
    for implementation in grep "$ZGREP"; do
        if [ "$implementation" = grep ]; then
            implementation_name=grep
        else
            implementation_name=zgr
        fi
        timeout 10 sh -c 'printf "device needle\n" >"$1"' sh "$fifo" &
        writer_pid=$!
        set +e
        timeout 10 env LC_ALL=C "$implementation" "$@" "$search_path" \
            >"$TEST_DIR/$implementation_name-fifo.out" \
            2>"$TEST_DIR/$implementation_name-fifo.err"
        eval "${implementation_name}_status=$?"
        wait "$writer_pid"
        writer_status=$?
        set -e
        if [ "$writer_status" -ne 0 ]; then
            echo "FIFO writer failure: $description ($implementation_name=$writer_status)" >&2
            exit 1
        fi
    done
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-fifo.err" >"$TEST_DIR/grep-fifo-normalized.err"
    if [ "$grep_status" -ne "$zgr_status" ] || \
        ! cmp -s "$TEST_DIR/grep-fifo.out" "$TEST_DIR/zgr-fifo.out" || \
        ! cmp -s "$TEST_DIR/grep-fifo-normalized.err" "$TEST_DIR/zgr-fifo.err"; then
        echo "FIFO differential failure: $description" >&2
        exit 1
    fi
}

compare_binary_file() {
    description=$1
    corpus=$2
    shift 2
    set +e
    LC_ALL=C grep "$@" "$corpus" >"$TEST_DIR/grep-binary.out" 2>"$TEST_DIR/grep-binary.err"
    grep_status=$?
    LC_ALL=C "$ZGREP" "$@" "$corpus" >"$TEST_DIR/zgrep-binary.out" 2>"$TEST_DIR/zgrep-binary.err"
    zgrep_status=$?
    set -e
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-binary.err" >"$TEST_DIR/grep-binary-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! diff -u "$TEST_DIR/grep-binary.out" "$TEST_DIR/zgrep-binary.out" || \
        ! diff -u "$TEST_DIR/grep-binary-normalized.err" "$TEST_DIR/zgrep-binary.err"; then
        echo "binary differential failure: $description" >&2
        exit 1
    fi
}

compare_binary_stdin() {
    description=$1
    corpus=$2
    shift 2
    set +e
    LC_ALL=C grep "$@" <"$corpus" >"$TEST_DIR/grep-binary.out" 2>"$TEST_DIR/grep-binary.err"
    grep_status=$?
    LC_ALL=C "$ZGREP" "$@" <"$corpus" >"$TEST_DIR/zgrep-binary.out" 2>"$TEST_DIR/zgrep-binary.err"
    zgrep_status=$?
    set -e
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-binary.err" >"$TEST_DIR/grep-binary-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! diff -u "$TEST_DIR/grep-binary.out" "$TEST_DIR/zgrep-binary.out" || \
        ! diff -u "$TEST_DIR/grep-binary-normalized.err" "$TEST_DIR/zgrep-binary.err"; then
        echo "binary stdin differential failure: $description" >&2
        exit 1
    fi
}

compare_null_file() {
    description=$1
    corpus=$2
    shift 2
    set +e
    LC_ALL=C grep "$@" "$corpus" >"$TEST_DIR/grep-null.out" 2>"$TEST_DIR/grep-null.err"
    grep_status=$?
    LC_ALL=C "$ZGREP" "$@" "$corpus" >"$TEST_DIR/zgrep-null.out" 2>"$TEST_DIR/zgrep-null.err"
    zgrep_status=$?
    set -e
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-null.err" >"$TEST_DIR/grep-null-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/grep-null.out" "$TEST_DIR/zgrep-null.out" || \
        ! cmp -s "$TEST_DIR/grep-null-normalized.err" "$TEST_DIR/zgrep-null.err"; then
        echo "NUL-data differential failure: $description" >&2
        echo "GNU stdout:" >&2
        od -An -t x1 "$TEST_DIR/grep-null.out" >&2
        echo "zgrep stdout:" >&2
        od -An -t x1 "$TEST_DIR/zgrep-null.out" >&2
        exit 1
    fi
}

compare_null_stdin() {
    description=$1
    corpus=$2
    shift 2
    set +e
    LC_ALL=C grep "$@" <"$corpus" >"$TEST_DIR/grep-null.out" 2>"$TEST_DIR/grep-null.err"
    grep_status=$?
    LC_ALL=C "$ZGREP" "$@" <"$corpus" >"$TEST_DIR/zgrep-null.out" 2>"$TEST_DIR/zgrep-null.err"
    zgrep_status=$?
    set -e
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-null.err" >"$TEST_DIR/grep-null-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/grep-null.out" "$TEST_DIR/zgrep-null.out" || \
        ! cmp -s "$TEST_DIR/grep-null-normalized.err" "$TEST_DIR/zgrep-null.err"; then
        echo "NUL-data stdin differential failure: $description" >&2
        exit 1
    fi
}

compare_pattern_stdin() {
    description=$1
    pattern_data=$2
    shift 2
    set +e
    printf '%s' "$pattern_data" | LC_ALL=C grep "$@" \
        >"$TEST_DIR/grep-pattern-stdin.out" 2>"$TEST_DIR/grep-pattern-stdin.err"
    grep_status=${PIPESTATUS[1]}
    printf '%s' "$pattern_data" | LC_ALL=C "$ZGREP" "$@" \
        >"$TEST_DIR/zgrep-pattern-stdin.out" 2>"$TEST_DIR/zgrep-pattern-stdin.err"
    zgrep_status=${PIPESTATUS[1]}
    set -e
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/grep-pattern-stdin.err" \
        >"$TEST_DIR/grep-pattern-stdin-normalized.err"
    if [ "$grep_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/grep-pattern-stdin.out" "$TEST_DIR/zgrep-pattern-stdin.out" || \
        ! cmp -s "$TEST_DIR/grep-pattern-stdin-normalized.err" "$TEST_DIR/zgrep-pattern-stdin.err"; then
        echo "pattern stdin differential failure: $description" >&2
        exit 1
    fi
}

compare "literal BRE fast path" alpha
compare "BRE operators" -n 'alpha.*soup'
compare "ERE alternation" -E -n 'warning|error'
compare "Perl lookbehind" -P -n '(?<=error: )request'
compare "fixed string" -F 'literal .*'
compare "escaped BRE punctuation" 'literal \.\*'
compare "ignore case" -i beta
compare "no-ignore-case overrides ignore-case" -i --no-ignore-case beta
compare "fixed ignore-case count fast path" -F -i -c 'BETA'
compare "invert and count" -v -c alpha
compare "invert regexp count" -E -v -c 'alpha.*soup'
compare "maximum count" -m 2 alpha
compare "maximum count with count" -m2 -c alpha
compare "line and byte offsets" -n -b alpha
compare "only matching fixed strings" -F -o alpha
compare "only matching line and match offsets" -F -n -b -o alpha
compare "only matching long alternative" -F -o -e alpha -e 'alpha beta'
compare "only matching ERE longest alternative" -E -o 'alpha|alphabet'
compare "only matching whole word" -F -w -o alpha
compare "only matching whole line" -F -x -o alpha
compare "only matching count remains line count" -F -c -o alpha
compare "only matching inverted output" -F -v -o absent
compare "word matching" -w -n alpha
compare "word count fast path" -F -w -c alpha
compare "empty word count fast path" -F -w -c -e ''
compare "whole line" -x alpha
compare "multiple patterns" -n -e warning -e error
compare "newline-separated positional patterns" -n $'warning\nerror'
compare "newline-separated regexp argument" -n -e $'warning\nerror'
compare "newline-separated long regexp argument" -n --regexp=$'warning\nerror'
compare "trailing newline adds an empty argument pattern" -n -e $'warning\n'
compare "pattern file" -n -f "$TEST_DIR/patterns.txt"
compare "empty pattern file" -f "$TEST_DIR/empty-patterns.txt"
compare "blank pattern matches every line" -f "$TEST_DIR/blank-pattern.txt"
compare "inverted empty pattern file" -v -f "$TEST_DIR/empty-patterns.txt"
compare "inverted blank pattern file" -v -f "$TEST_DIR/blank-pattern.txt"
compare_pattern_stdin "pattern stdin with explicit input file" \
    $'warning\nerror\n' -n -f - "$CORPUS"
compare_pattern_stdin "pattern stdin consumes implicit search stdin" \
    $'alpha\ninput alpha\n' -n -f -
compare_pattern_stdin "pattern stdin consumes explicit search stdin" \
    $'alpha\ninput alpha\n' -n -f - -
compare_pattern_stdin "multiple pattern stdin operands" \
    $'warning\nerror\n' -n -f - -f - "$CORPUS"
compare_pattern_stdin "mixed command-line and stdin patterns" \
    $'error\n' -n -e warning -f - "$CORPUS"
compare_pattern_stdin "empty pattern stdin" '' -n -f - "$CORPUS"
compare_pattern_stdin "blank pattern from stdin" $'\n' -n -f - "$CORPUS"
compare_pattern_stdin "pattern stdin without final newline" \
    'warning' -n -f - "$CORPUS"
compare "forced filename" -H alpha
compare "files with matches" -l alpha
compare "files without matches" -L absent
compare_color_file "color always highlights all fixed matches" "$CORPUS" '' \
    --color=always -F alpha
compare_color_file "color prefixes and only-matching offsets" "$CORPUS" '' \
    --color=always -F -H -n -b -o alpha
compare_color_file "color context and group separators" "$TEST_DIR/context-groups.txt" '' \
    --color=always -H -n -A1 foo
compare_color_file "color count filename" "$CORPUS" '' \
    --color=always -H -c alpha
compare_color_file "color matching filename" "$CORPUS" '' \
    --color=always -l alpha
compare_color_file "color auto disables markers on a pipe" "$CORPUS" '' \
    --color=auto -H -n -b alpha
compare_color_file "bare color uses auto" "$CORPUS" '' \
    --color -H -n -b alpha
compare_color_file "color yes alias" "$CORPUS" '' \
    --color=yes -F alpha
compare_color_file "color none alias" "$CORPUS" '' \
    --color=none -H -n -b alpha
compare_color_file "color tty alias" "$CORPUS" '' \
    --color=tty -H -n -b alpha
compare_color_file "colour alias" "$CORPUS" '' \
    --colour=always -E 'alpha|Beta'
compare_color_file "custom GREP_COLORS" "$CORPUS" \
    'ms=35:fn=32:ln=33:bn=36:se=37' --color=always -H -n -b alpha
compare_color_file "GREP_COLORS line and context styles" "$TEST_DIR/context-groups.txt" \
    'sl=43:cx=44:ms=35:mc=36' --color=always -H -n -A1 foo
compare_color_file "GREP_COLORS reverse mode" "$CORPUS" \
    'rv:sl=43:cx=44:ms=35:mc=36' --color=always -v alpha
compare_file "pattern file without final newline" \
    "$TEST_DIR/pattern-no-newline-corpus.txt" -f "$TEST_DIR/pattern-no-newline.txt"
compare_file "duplicate fixed patterns" \
    "$TEST_DIR/duplicate-corpus.txt" -F -f "$TEST_DIR/duplicate-patterns.txt"
compare_file "zero maximum count" "$TEST_DIR/max-count-corpus.txt" -m0 test
compare_file "input without final newline" "$TEST_DIR/no-final-newline.txt" two
compare_file "after context" "$TEST_DIR/context.txt" -n -A2 5
compare_file "before context" "$TEST_DIR/context.txt" -n -B2 5
compare_file "symmetric context with byte offsets" "$TEST_DIR/context.txt" -n -b -C1 5
compare_file "numeric context shorthand" "$TEST_DIR/context.txt" -2 5
compare_file "context partial override" "$TEST_DIR/context.txt" -C1 -A2 5
compare_file "context partial override reverse order" "$TEST_DIR/context.txt" -A2 -C1 5
compare_file "context after maximum count" "$TEST_DIR/context.txt" -n -A2 -m1 5
compare_file "context after maximum count includes later matches as context" \
    "$TEST_DIR/context-max.txt" -n -A2 -m1 d
compare_file "only matching ignores context" "$TEST_DIR/context.txt" -n -o -A1 5
compare_file "count ignores context" "$TEST_DIR/context.txt" -C1 -c 5
compare_file "inverted context" "$TEST_DIR/context.txt" -n -C1 -v 5
compare_file "default context group separator" "$TEST_DIR/context-groups.txt" -n -A1 foo
compare_file "custom context group separator" \
    "$TEST_DIR/context-groups.txt" -A1 --group-separator=AAA foo
compare_file "no context group separator" \
    "$TEST_DIR/context-groups.txt" -A1 --no-group-separator foo
compare_file "ERE sparse required literal" "$TEST_DIR/ere-prefilter.txt" -E '[a-z]+-needle'
compare_file "ERE sparse required literal count" "$TEST_DIR/ere-prefilter.txt" -E -c '[a-z]+-needle'
compare_file "ERE required literal after alternation group" \
    "$TEST_DIR/ere-prefilter.txt" -E '(foo|bar)-required'
compare_file "ERE optional atom" "$TEST_DIR/ere-prefilter.txt" -E 'foo?bar'
compare_file "ERE top-level alternation" "$TEST_DIR/ere-prefilter.txt" -E 'foo|bar'
compare_file "ERE brace quantifier" "$TEST_DIR/ere-prefilter.txt" -E 'foo{0}bar'
compare_file "ERE dense required literal" \
    "$TEST_DIR/ere-prefilter.txt" -E '^status=(200|500)$'
compare_file "only matching PCRE2 ranges" \
    "$TEST_DIR/ere-prefilter.txt" -E -n -b -o 'status=(200|500)'
compare_file "Perl only-matching reset start" \
    "$TEST_DIR/ere-prefilter.txt" -P -n -b -o 'status=\K(200|500)'
compare_file "only matching skips empty regex matches" \
    "$TEST_DIR/ere-prefilter.txt" -E -o 'a*'
compare "initial tab with filename and offsets" -T -H -n -b alpha
compare "long initial-tab only matching" --initial-tab -H -n -b -o alpha
compare_file "initial tab with context" "$TEST_DIR/context.txt" -T -H -n -b -C1 5
compare "initial tab does not alter count output" -T -H -c alpha
compare "initial tab does not alter listing output" -T -H -l alpha
compare "binary input compatibility no-op" -U -H -n -b alpha
compare "long binary input compatibility no-op" --binary -H -n -b alpha
compare "line-buffered output bytes" --line-buffered -H -n -b alpha
compare "combined initial-tab flags" -TUHnb alpha
compare_color_file "color initial tab fields" "$TEST_DIR/context.txt" \
    'ms=01;31:mc=01;31:sl=:cx=:fn=35:ln=32:bn=32:se=36' \
    --color=always -T -H -n -b -C1 5

compare_binary_file "binary match before NUL" "$TEST_DIR/binary-small.txt" needle
compare_binary_file "binary match after NUL" "$TEST_DIR/binary-small.txt" Heaven
compare_binary_file "binary diagnostic survives no-messages" "$TEST_DIR/binary-small.txt" -s Heaven
compare_binary_file "binary count" "$TEST_DIR/binary-small.txt" -E -c 'needle|Heaven'
compare_binary_file "binary files with matches" "$TEST_DIR/binary-small.txt" -l Heaven
compare_binary_file "binary files without matches" "$TEST_DIR/binary-small.txt" -L absent
compare_binary_file "binary quiet" "$TEST_DIR/binary-small.txt" -q Heaven
compare_binary_file "binary as text" "$TEST_DIR/binary-small.txt" -a -n Heaven
compare_binary_file "binary only matching as text" "$TEST_DIR/binary-small.txt" -a -n -b -o Heaven
compare_binary_file "binary-files text" "$TEST_DIR/binary-small.txt" --binary-files=text -n Heaven
compare_binary_file "binary-files text separate argument" \
    "$TEST_DIR/binary-small.txt" --binary-files text -n Heaven
compare_binary_file "binary without match count" "$TEST_DIR/binary-small.txt" -I -c Heaven
compare_binary_file "binary without match listing" "$TEST_DIR/binary-small.txt" -I -L Heaven
compare_binary_file "binary-files without-match" \
    "$TEST_DIR/binary-small.txt" --binary-files=without-match Heaven
compare_binary_file "late NUL preserves earlier output" "$TEST_DIR/binary-late.txt" needle
compare_binary_file "late NUL summarizes later match" "$TEST_DIR/binary-late.txt" Heaven
compare_binary_stdin "binary stdin summary" "$TEST_DIR/binary-small.txt" Heaven
compare_binary_stdin "binary stdin match before same-block NUL" "$TEST_DIR/binary-small.txt" needle
compare_binary_stdin "late stdin NUL preserves earlier output" "$TEST_DIR/binary-late.txt" needle
compare_binary_stdin "late stdin NUL summarizes later match" "$TEST_DIR/binary-late.txt" Heaven
compare_binary_stdin "binary stdin as text" "$TEST_DIR/binary-small.txt" -a -n Heaven
compare_binary_stdin "line-buffered streamed before context" \
    "$TEST_DIR/context-groups.txt" --line-buffered -H -n -b -B1 foo
compare_binary_stdin "line-buffered streamed symmetric context" \
    "$TEST_DIR/context-groups.txt" --line-buffered -H -n -b -C1 foo
compare_binary_stdin "line-buffered streamed context and maximum count" \
    "$TEST_DIR/context-max.txt" --line-buffered -H -n -b -A2 -m1 d
compare_binary_stdin "initial tab on unknown-size stdin" \
    "$CORPUS" --initial-tab --label=input -H -n -b alpha

compare_null_file "NUL-delimited literal output" "$TEST_DIR/null-records.txt" -z match
compare_null_file "long null-data option" "$TEST_DIR/null-records.txt" --null-data match
compare_null_file "NUL-delimited line and byte offsets" "$TEST_DIR/null-records.txt" -z -n -b match
compare_null_file "NUL-delimited only matching" "$TEST_DIR/null-records.txt" -z -F -o match
compare_null_file "NUL-delimited count" "$TEST_DIR/null-records.txt" -z -c match
compare_null_file "NUL-delimited literal alternation count" \
    "$TEST_DIR/null-records.txt" -z -E -c 'two|three'
compare_null_file "NUL-delimited regexp count" \
    "$TEST_DIR/null-records.txt" -z -E -c '[a-z]+ match'
compare_null_file "NUL-delimited dot matches newline" \
    "$TEST_DIR/null-records.txt" -z -E 'one.inside'
compare_null_file "NUL-delimited empty records" \
    "$TEST_DIR/null-empty-records.txt" -z -E '.+'
compare_null_file "NUL-delimited whole-record regexp" \
    "$TEST_DIR/null-empty-records.txt" -z -x bar
compare_null_file "NUL-delimited inverted output" "$TEST_DIR/null-records.txt" -z -v absent
compare_null_file "NUL-delimited after context" "$TEST_DIR/null-records.txt" -z -n -A1 two
compare_null_file "NUL-delimited separated context groups" \
    "$TEST_DIR/null-context-groups.txt" -z -n -A1 match
compare_null_file "NUL-delimited maximum count" "$TEST_DIR/null-records.txt" -z -m1 match
compare_null_file "NUL separators are not binary data" "$TEST_DIR/null-records.txt" -z -I match
compare_null_file "NUL-delimited files with matches" "$TEST_DIR/null-records.txt" -z -l match
compare_color_file "color NUL-delimited records" "$TEST_DIR/null-records.txt" '' \
    --color=always -z -H -n -b -o match
compare_null_stdin "NUL-delimited stdin output" "$TEST_DIR/null-records.txt" -z -n match
compare_null_stdin "NUL-delimited stdin only matching" "$TEST_DIR/null-records.txt" -z -b -o match
compare_null_stdin "line-buffered NUL-delimited stdin" \
    "$TEST_DIR/null-records.txt" --line-buffered -z -H -n -b match

compare_null_file "NUL-terminated filename in normal output" "$CORPUS" -Z -H -n -b alpha
compare_null_file "long null filename option" "$CORPUS" --null -H alpha
compare_null_file "NUL-terminated filename in count output" "$CORPUS" -Z -H -c alpha
compare_null_file "NUL-terminated matching filename" "$CORPUS" -Z -l alpha
compare_null_file "NUL-terminated non-matching filename" "$CORPUS" -Z -L absent
compare_null_file "NUL-terminated filename with context" "$CORPUS" -Z -H -n -A1 warning
compare_null_file "NUL input and filename separators" "$TEST_DIR/null-records.txt" -z -Z -H -n match
compare_null_file "initial tab with NUL records" \
    "$TEST_DIR/null-records.txt" -T -z -Z -H -n -b match
compare_null_stdin "NUL-terminated stdin label" "$CORPUS" -Z --label=input -H alpha

diff -u \
    <(LC_ALL=C grep -E -n 'warning|error' "$CORPUS") \
    <(LC_ALL=C "$ZGREP" -E -n 'warning|error' "$CORPUS")

diff -u \
    <(printf 'stdin one\nstdin two\n' | LC_ALL=C grep two) \
    <(printf 'stdin one\nstdin two\n' | LC_ALL=C "$ZGREP" two)

diff -u \
    <(printf 'stdin needle\n' | LC_ALL=C grep --label=input -H needle) \
    <(printf 'stdin needle\n' | LC_ALL=C "$ZGREP" --label=input -H needle)

diff -u \
    <(printf 'stdin needle\n' | LC_ALL=C grep --label input -H needle) \
    <(printf 'stdin needle\n' | LC_ALL=C "$ZGREP" --label input -H needle)

assert_line_buffered_context grep
assert_line_buffered_context "$ZGREP"

diff -u \
    <(cat "$TEST_DIR/context.txt" | LC_ALL=C grep -n -C1 5) \
    <(cat "$TEST_DIR/context.txt" | LC_ALL=C "$ZGREP" -n -C1 5)

diff -u \
    <(LC_ALL=C grep -H -n -C1 match \
        "$TEST_DIR/context-one.txt" "$TEST_DIR/context-two.txt") \
    <(LC_ALL=C "$ZGREP" -H -n -C1 match \
        "$TEST_DIR/context-one.txt" "$TEST_DIR/context-two.txt")

diff -u \
    <(printf 'foo\nctx\nfoo\nctx\n') \
    <(LC_ALL=C "$ZGREP" -A1 --no-context-separator foo "$TEST_DIR/context-groups.txt")

diff -u \
    <(cat "$TEST_DIR/long-line.txt" | LC_ALL=C grep -F -c rare-needle) \
    <(cat "$TEST_DIR/long-line.txt" | LC_ALL=C "$ZGREP" -F -c rare-needle)

diff -u \
    <(cat "$TEST_DIR/stream-boundary.txt" | LC_ALL=C grep -a -F -n -b needle) \
    <(cat "$TEST_DIR/stream-boundary.txt" | LC_ALL=C "$ZGREP" -a -F -n -b needle)

diff -u \
    <(cat "$TEST_DIR/stream-word-boundary.txt" | LC_ALL=C grep -a -F -n -w needle) \
    <(cat "$TEST_DIR/stream-word-boundary.txt" | LC_ALL=C "$ZGREP" -a -F -n -w needle)

diff -u \
    <(LC_ALL=C grep -r -n -E 'alpha|warning' "$TEST_DIR/tree") \
    <(LC_ALL=C "$ZGREP" -r -n -E 'alpha|warning' "$TEST_DIR/tree")

diff -u \
    <(LC_ALL=C grep -d recurse -n alpha "$TEST_DIR/tree") \
    <(LC_ALL=C "$ZGREP" -d recurse -n alpha "$TEST_DIR/tree")

diff -u \
    <(LC_ALL=C grep --directories=recurse -n alpha "$TEST_DIR/tree") \
    <(LC_ALL=C "$ZGREP" --directories=recurse -n alpha "$TEST_DIR/tree")

diff -u \
    <(LC_ALL=C grep -r -d skip -n alpha "$TEST_DIR/tree") \
    <(LC_ALL=C "$ZGREP" -r -d skip -n alpha "$TEST_DIR/tree")

diff -u \
    <(LC_ALL=C grep -d skip -r -n alpha "$TEST_DIR/tree") \
    <(LC_ALL=C "$ZGREP" -d skip -r -n alpha "$TEST_DIR/tree")

diff -u \
    <(LC_ALL=C grep -r -l needle "$TEST_DIR/symlink-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l needle "$TEST_DIR/symlink-tree" | sort)

diff -u \
    <(LC_ALL=C grep -R -l needle "$TEST_DIR/symlink-tree" 2>/dev/null | sort) \
    <(LC_ALL=C "$ZGREP" -R -l needle "$TEST_DIR/symlink-tree" 2>/dev/null | sort)

diff -u \
    <(LC_ALL=C grep -r -l needle "$TEST_DIR/parallel-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l needle "$TEST_DIR/parallel-tree" | sort)

diff -u \
    <(LC_ALL=C grep -r -l -E 'needle [[:digit:]]+' "$TEST_DIR/parallel-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l -E 'needle [[:digit:]]+' "$TEST_DIR/parallel-tree" | sort)

diff -u \
    <(LC_ALL=C grep -r -L needle "$TEST_DIR/parallel-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -L needle "$TEST_DIR/parallel-tree" | sort)

cmp \
    <(LC_ALL=C grep -Z -r -l needle "$TEST_DIR/parallel-tree" | sort -z) \
    <(LC_ALL=C "$ZGREP" -Z -r -l needle "$TEST_DIR/parallel-tree" | sort -z)

cmp \
    <(LC_ALL=C grep -Z -r -L needle "$TEST_DIR/parallel-tree" | sort -z) \
    <(LC_ALL=C "$ZGREP" -Z -r -L needle "$TEST_DIR/parallel-tree" | sort -z)

diff -u \
    <(LC_ALL=C grep -r -l --include='*.c' needle "$TEST_DIR/filter-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l --include='*.c' needle "$TEST_DIR/filter-tree" | sort)

diff -u \
    <(LC_ALL=C grep -r -l --include='*.c' --exclude=c.c needle "$TEST_DIR/filter-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l --include='*.c' --exclude=c.c needle "$TEST_DIR/filter-tree" | sort)

diff -u \
    <(LC_ALL=C grep -r -l --exclude=c.c --include='*.c' needle "$TEST_DIR/filter-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l --exclude=c.c --include='*.c' needle "$TEST_DIR/filter-tree" | sort)

diff -u \
    <(LC_ALL=C grep -r -l --exclude-dir='sub*' needle "$TEST_DIR/filter-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l --exclude-dir='sub*' needle "$TEST_DIR/filter-tree" | sort)

diff -u \
    <(LC_ALL=C grep -r -l --exclude-from="$TEST_DIR/filter-globs.txt" \
        needle "$TEST_DIR/filter-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l --exclude-from="$TEST_DIR/filter-globs.txt" \
        needle "$TEST_DIR/filter-tree" | sort)

diff -u \
    <(LC_ALL=C grep -r -l --include='file[[:digit:]].c' needle "$TEST_DIR/filter-tree" | sort) \
    <(LC_ALL=C "$ZGREP" -r -l --include='file[[:digit:]].c' needle "$TEST_DIR/filter-tree" | sort)

diff -u \
    <(cd "$TEST_DIR/filter-tree" && LC_ALL=C grep -r -l needle | sort) \
    <(cd "$TEST_DIR/filter-tree" && LC_ALL=C "$ZGREP" -r -l needle | sort)

LC_ALL=C "$ZGREP" -R -l needle "$TEST_DIR/symlink-tree" \
    >/dev/null 2>"$TEST_DIR/symlink-warning.txt"
grep -q 'warning: recursive directory loop' "$TEST_DIR/symlink-warning.txt"
LC_ALL=C "$ZGREP" -s -R -l needle "$TEST_DIR/symlink-tree" \
    >/dev/null 2>"$TEST_DIR/symlink-silent.txt"
[ ! -s "$TEST_DIR/symlink-silent.txt" ]

MISSING_FILE="$TEST_DIR/does-not-exist"
compare_status "match" alpha "$CORPUS"
compare_status "quiet match" -q alpha "$CORPUS"
compare_status "match plus error" alpha "$CORPUS" "$MISSING_FILE"
compare_status "quiet match plus later error" -q alpha "$CORPUS" "$MISSING_FILE"
compare_status "no match" absent "$CORPUS"
compare_status "quiet no match" -q absent "$CORPUS"
compare_status "no match plus error" absent "$CORPUS" "$MISSING_FILE"
compare_status "quiet no match plus error" -q absent "$CORPUS" "$MISSING_FILE"
compare_status "invalid option" --definitely-invalid
compare_status "short version" -V
compare_status "invalid binary mode" --binary-files=definitely-invalid alpha "$CORPUS"
compare_status "directory skip" -d skip needle "$TEST_DIR/tree"
compare_status "directory read" -d read needle "$TEST_DIR/tree"
compare_status "recursive then directory read" -r -d read needle "$TEST_DIR/tree"
compare_status "device skip FIFO" -D skip needle "$TEST_DIR/device-fifo"
compare_status "long device skip FIFO" --devices=skip needle "$TEST_DIR/device-fifo"
compare_status "device skip keeps regular files" -D skip alpha "$CORPUS"
compare_timeout_status "recursive default skips FIFO" \
    -r needle "$TEST_DIR/device-tree"
compare_timeout_status "recursive explicit device skip" \
    -r -D skip needle "$TEST_DIR/device-tree"
compare_fifo_read "explicit FIFO is read by default" \
    "$TEST_DIR/device-fifo" "$TEST_DIR/device-fifo" needle
compare_fifo_read "recursive FIFO read" \
    "$TEST_DIR/device-tree/input.fifo" "$TEST_DIR/device-tree" -r -D read needle
compare_fifo_read "recursive FIFO files-with-matches" \
    "$TEST_DIR/device-tree/input.fifo" "$TEST_DIR/device-tree" -r -D read -l needle
compare_fifo_read "recursive FIFO files-without-match" \
    "$TEST_DIR/device-tree/input.fifo" "$TEST_DIR/device-tree" -r -D read -L absent
compare_status "invalid directory action" -d definitely-invalid needle "$TEST_DIR/tree"
compare_status "invalid device action" -D definitely-invalid needle "$CORPUS"
compare_status "invalid color action shows help" --color=definitely-invalid alpha "$CORPUS"
compare_status "explicit file excluded by include" \
    --include='*.h' needle "$TEST_DIR/filter-tree/a.c"
compare_status "empty only-matching pattern still selects" -o -e '' "$CORPUS"
compare_status "inverted only-matching selection" -v -o absent "$CORPUS"
compare_status "files without match with a matching file" -L alpha "$CORPUS"
compare_status "files without match with no matching file" -L absent "$CORPUS"
compare_broken_pipe "buffered output"
compare_broken_pipe "line-buffered output" --line-buffered

printf '%s differential tests passed\n' "$PROG"
