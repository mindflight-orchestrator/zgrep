#!/usr/bin/env bash
set -euo pipefail

ZGREP=${1:?missing zgr binary}
ZGREP=$(realpath "$ZGREP")
TEST_DIR=$(mktemp -d /tmp/zgrep-regex-semantics.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
CORPUS="$TEST_DIR/corpus.txt"

cat >"$CORPUS" <<'EOF'

a
aa
aaa
ab
abb
abc
abbc
ac
ba
foo
foobar
foo bar
word_word
a+b
a?b
a|b
a(b)
a{2}
.
[
]
-
11
1212
ch
q
d
n
foo-x
aaaa
*a
+a
?a
{2}a
a)
EOF

checks=0

compare_results() {
    description=$1
    gnu_status=$2
    zgrep_status=$3
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

    printf '\nregex semantic failure: %s\n' "$description" >&2
    printf 'status: GNU=%s zgrep=%s\n' "$gnu_status" "$zgrep_status" >&2
    diff -u "$TEST_DIR/gnu.out" "$TEST_DIR/zgrep.out" >&2 || true
    printf 'GNU stderr: ' >&2
    tr '\n' ' ' <"$TEST_DIR/gnu.err" >&2
    printf '\nzgrep stderr: ' >&2
    tr '\n' ' ' <"$TEST_DIR/zgrep.err" >&2
    printf '\n' >&2
    exit 1
}

check() {
    description=$1
    pattern=$2
    shift 2
    checks=$((checks + 1))

    set +e
    LC_ALL=C grep "$@" -- "$pattern" "$CORPUS" \
        >"$TEST_DIR/gnu.out" 2>"$TEST_DIR/gnu.err"
    gnu_status=$?
    LC_ALL=C "$ZGREP" "$@" -- "$pattern" "$CORPUS" \
        >"$TEST_DIR/zgrep.out" 2>"$TEST_DIR/zgrep.err"
    zgrep_status=$?
    set -e
    compare_results "$description" "$gnu_status" "$zgrep_status"
}

check_multiple() {
    description=$1
    shift
    checks=$((checks + 1))

    set +e
    LC_ALL=C grep "$@" "$CORPUS" >"$TEST_DIR/gnu.out" 2>"$TEST_DIR/gnu.err"
    gnu_status=$?
    LC_ALL=C "$ZGREP" "$@" "$CORPUS" >"$TEST_DIR/zgrep.out" 2>"$TEST_DIR/zgrep.err"
    zgrep_status=$?
    set -e
    compare_results "$description" "$gnu_status" "$zgrep_status"
}

# GNU grep can warn for accepted repeated operators. Warning wording is not
# compared; selected bytes, exit status, and the presence of fatal diagnostics
# are the compatibility contract in this lane.

# BRE selection and match-span semantics.
check 'BRE anchors' '^a$' -G -n
check 'BRE star' 'a*' -G -n -o
check 'BRE escaped plus' 'a\+' -G -n -o
check 'BRE escaped question' 'ab\?' -G -n -o
check 'BRE grouping and alternation' '\(a\|ab\)c\?' -G -n -b -o
check 'BRE counted repetition' 'a\{2,3\}' -G -n -b -o
check 'BRE open lower interval' 'a\{,2\}' -G -n -b -o
check 'BRE backreference' '\([0-9][0-9]\)\1' -G -n -b -o
check 'BRE ambiguous backreference' '\(a\|aa\)\1' -G -n -b -o
check 'BRE literal extended punctuation' 'a+b' -G -n
check 'BRE literal parentheses' 'a(b)' -G -n
check 'BRE literal braces' 'a{2}' -G -n
check 'BRE POSIX alpha class' '[[:alpha:]]\+' -G -n -b -o
check 'BRE POSIX class followed by literal class member' \
    '[[:alpha:]|]' -G -n -b -o
check 'BRE literal closing bracket class' '[]a]' -G -n -b -o
check 'BRE negated closing bracket class' '[^]]\+' -G -n -b -o
check 'BRE GNU word boundaries' '\<foo\>' -G -n -b -o
check 'BRE GNU word boundary escape' '\bfoo\b' -G -n -b -o
check 'BRE unknown escape' '\q' -G -n
check 'BRE PCRE digit escape is literal' '\d' -G -n -b -o
check 'BRE PCRE newline escape is literal' '\n' -G -n -b -o
check 'BRE bracket backslash is ordinary' '[\d]' -G -n -b -o
check 'BRE trailing escape' 'a\' -G -n
check 'BRE invalid bracket' '[a' -G -n
check 'BRE invalid interval' 'a\{3,2\}' -G -n
check 'BRE repetition above GNU limit' 'a\{32768\}' -G -n
check 'BRE repetition at expression start' '*a' -G -n -b -o

# ERE selection and POSIX leftmost-longest spans.
check 'ERE simple alternation' 'a|ab' -E -n -b -o
check 'ERE nested alternation longest' '(a|ab)c?' -E -n -b -o
check 'ERE nested suffix longest' 'a(b|bb)c?' -E -n -b -o
check 'ERE optional suffix longest' '(ab|a)b?' -E -n -b -o
check 'ERE counted repetition' 'a{1,3}' -E -n -b -o
check 'ERE open lower interval' 'a{,2}' -E -n -b -o
check 'ERE POSIX digit class' '[[:digit:]]+' -E -n -b -o
check 'ERE nested POSIX class count prefilter safety' \
    '^[ab][[:alpha:]_]$' -E -c
check 'ERE nested POSIX class only-matching' \
    '^[ab][[:alpha:]_]$' -E -n -b -o
check 'ERE literal closing bracket class' '[]a]+' -E -n -b -o
check 'ERE GNU word boundary' '\<foo\>' -E -n -b -o
check 'ERE unknown escape' '\q' -E -n
check 'ERE PCRE digit escape is literal' '\d' -E -n -b -o
check 'ERE PCRE newline escape is literal' '\n' -E -n -b -o
check 'ERE bracket backslash is ordinary' '[\d]' -E -n -b -o
check 'ERE PCRE lookahead is not enabled' '(?=a)' -E -n
check 'ERE repeated lazy-looking quantifier' 'a+?' -E -n -b -o
check 'ERE repeated possessive-looking quantifier' 'a++' -E -n -b -o
check 'ERE star at group start' '(*a)' -E -n -b -o
check 'ERE whole-line POSIX fallback' '\q' -E -x -n
check 'ERE whole-word alternative boundary' 'foo.|foo' -E -w -n -b -o
check_multiple 'ERE multiple-pattern longest span' \
    -E -n -b -o -e '(a|ab)c?' -e 'abbc'
check 'ERE trailing escape' 'a\' -E -n
check 'ERE invalid group' '(a' -E -n
check 'ERE invalid interval' 'a{3,2}' -E -n
check 'ERE repetition above GNU limit' 'a{32768}' -E -n
check 'ERE unmatched right parenthesis' ')' -E -n -b -o
check 'ERE unmatched right parenthesis after atom' 'a)' -E -n -b -o
check 'ERE star at expression start' '*a' -E -n -b -o
check 'ERE plus at expression start' '+a' -E -n -b -o
check 'ERE question at expression start' '?a' -E -n -b -o
check 'ERE interval at expression start' '{2}a' -E -n -b -o

printf 'zgr regex semantics differentials passed (%s cases)\n' "$checks"
