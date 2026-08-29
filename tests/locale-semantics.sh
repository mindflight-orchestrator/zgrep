#!/usr/bin/env bash
set -euo pipefail

ZGREP=${1:?missing candidate binary}
ZGREP=$(realpath "$ZGREP")
PROG=$(basename "$ZGREP")
TEST_DIR=$(mktemp -d /tmp/zgrep-locale.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
CORPUS="$TEST_DIR/utf8.txt"
ASCII_CORPUS="$TEST_DIR/ascii.txt"
INVALID_CORPUS="$TEST_DIR/invalid-utf8.txt"
INVALID_NUL_CORPUS="$TEST_DIR/invalid-utf8-nul.txt"
INVALID_FOLD_CORPUS="$TEST_DIR/invalid-utf8-fold.txt"
INVALID_WITNESS_CORPUS="$TEST_DIR/invalid-utf8-witness.txt"
UNICODE_WITNESS_CORPUS="$TEST_DIR/unicode-witness.txt"
LOCALE_TREE="$TEST_DIR/locale-tree"
mkdir -p "$LOCALE_TREE"

cat >"$CORPUS" <<'EOF'
café
CAFÉ
École
école
Ωmega
ωMEGA
naïve
NAÏVE
Straße
STRAẞE
kelvin
Kelvin
é
xéx
àéà
foo中文
中文foo
中文
I
ı
İ
ſearcherBuilder
EOF
cat >"$ASCII_CORPUS" <<'EOF'
rare-needle
RARE-NEEDLE
xrare-needlex
route=/api/item/42 status=500
alpha_42 sample7
EOF
printf 'invalid\303( target\nvalid target\n' >"$INVALID_CORPUS"
printf 'invalid\303( target\0valid target\0' >"$INVALID_NUL_CORPUS"
printf 'invalid\377 prefix \305\277earcherBuilder suffix\n' >"$INVALID_FOLD_CORPUS"
printf 'invalid\377 prefix abcdefghijkl suffix\n' >"$INVALID_WITNESS_CORPUS"
printf '\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\n' >"$UNICODE_WITNESS_CORPUS"
printf 'plain SearcherBuilder word\n' >"$LOCALE_TREE/match.txt"
printf 'adjacent \344\270\255\346\226\207SearcherBuilder\344\270\255\346\226\207\n' >"$LOCALE_TREE/cjk-adjacent.txt"

available_locales=$(locale -a)
locales=()
for candidate in C.utf8 en_US.utf8 nl_BE.utf8; do
    if grep -Fxq "$candidate" <<<"$available_locales"; then
        locales+=("$candidate")
    fi
done
if [ "${#locales[@]}" -eq 0 ]; then
    echo "$PROG locale differentials skipped: no UTF-8 locale available"
    exit 0
fi

case_count=0
compare() {
    description=$1
    locale_name=$2
    shift 2
    compare_file "$description" "$locale_name" "$CORPUS" "$@"
}

compare_file() {
    description=$1
    locale_name=$2
    corpus=$3
    shift 3
    set +e
    LC_ALL=$locale_name grep "$@" "$corpus" \
        >"$TEST_DIR/gnu.out" 2>"$TEST_DIR/gnu.err"
    gnu_status=$?
    LC_ALL=$locale_name "$ZGREP" "$@" "$corpus" \
        >"$TEST_DIR/zgrep.out" 2>"$TEST_DIR/zgrep.err"
    zgrep_status=$?
    set -e
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/gnu.err" >"$TEST_DIR/gnu-normalized.err"
    if [ "$gnu_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/gnu.out" "$TEST_DIR/zgrep.out" || \
        ! cmp -s "$TEST_DIR/gnu-normalized.err" "$TEST_DIR/zgrep.err"; then
        echo "locale differential failure: $locale_name / $description" >&2
        echo "status: GNU=$gnu_status zgrep=$zgrep_status" >&2
        echo 'GNU stdout:' >&2
        od -An -v -tx1 "$TEST_DIR/gnu.out" >&2
        echo 'zgrep stdout:' >&2
        od -An -v -tx1 "$TEST_DIR/zgrep.out" >&2
        exit 1
    fi
    case_count=$((case_count + 1))
}

compare_tree() {
    description=$1
    locale_name=$2
    shift 2
    set +e
    LC_ALL=$locale_name grep "$@" "$LOCALE_TREE" \
        >"$TEST_DIR/gnu.out" 2>"$TEST_DIR/gnu.err"
    gnu_status=$?
    LC_ALL=$locale_name "$ZGREP" "$@" "$LOCALE_TREE" \
        >"$TEST_DIR/zgrep.out" 2>"$TEST_DIR/zgrep.err"
    zgrep_status=$?
    set -e
    sort -o "$TEST_DIR/gnu.out" "$TEST_DIR/gnu.out"
    sort -o "$TEST_DIR/zgrep.out" "$TEST_DIR/zgrep.out"
    sed "s/^grep:/${PROG}:/" "$TEST_DIR/gnu.err" >"$TEST_DIR/gnu-normalized.err"
    if [ "$gnu_status" -ne "$zgrep_status" ] || \
        ! cmp -s "$TEST_DIR/gnu.out" "$TEST_DIR/zgrep.out" || \
        ! cmp -s "$TEST_DIR/gnu-normalized.err" "$TEST_DIR/zgrep.err"; then
        echo "locale tree differential failure: $locale_name / $description" >&2
        exit 1
    fi
    case_count=$((case_count + 1))
}

for locale_name in "${locales[@]}"; do
    compare 'fixed accented case folding' "$locale_name" -F -i café
    compare 'fixed Greek case folding' "$locale_name" -F -i ωmega
    compare 'fixed libc Kelvin folding' "$locale_name" -F -i kelvin
    compare 'fixed libc sharp-s folding' "$locale_name" -F -i straße
    compare 'fixed libc long-s folding' "$locale_name" -F -i SearcherBuilder
    compare 'fixed whole-line case folding' "$locale_name" -F -i -x café
    compare 'fixed accented word boundary' "$locale_name" -F -w é
    compare 'fixed CJK right word boundary' "$locale_name" -F -w foo
    compare 'fixed CJK word' "$locale_name" -F -w 中文
    compare 'ERE upper class' "$locale_name" -E '[[:upper:]]'
    compare 'ERE alpha class' "$locale_name" -E '^[[:alpha:]]+$'
    compare 'ERE accented case folding' "$locale_name" -E -i '^école$'
    compare 'ERE character count' "$locale_name" -E '^..$'
    compare 'ERE character only-matching' "$locale_name" -E -n -b -o '.'
    compare 'BRE character only-matching' "$locale_name" -G -n -b -o '.'
    compare 'ERE GNU accented boundary' "$locale_name" -E -n -b -o '\<é\>'
    compare 'ERE whole-word alternatives' "$locale_name" -E -w -n -b -o 'é|foo'
    compare 'ERE inverted Unicode class' "$locale_name" -E -v '^[[:alpha:]]+$'
    compare 'ERE Unicode count' "$locale_name" -E -c '[[:alpha:]]+'
    compare 'PCRE character only-matching' "$locale_name" -P -n -b -o '.'
    compare 'PCRE Unicode property' "$locale_name" -P -n -b -o '\p{L}+'
    compare 'PCRE ASCII word class' "$locale_name" -P -n -b -o '\w+'
    compare 'colored Unicode spans' "$locale_name" --color=always -E -H -n -b -o 'é|中文'

    compare_file 'invalid UTF-8 binary summary' "$locale_name" "$INVALID_CORPUS" -n target
    compare_file 'invalid UTF-8 without-match output' "$locale_name" "$INVALID_CORPUS" -I -n target
    compare_file 'invalid UTF-8 forced text' "$locale_name" "$INVALID_CORPUS" -a -n target
    compare_file 'invalid UTF-8 count' "$locale_name" "$INVALID_CORPUS" -c target
    compare_file 'invalid UTF-8 file listing' "$locale_name" "$INVALID_CORPUS" -l target
    compare_file 'invalid UTF-8 literal spans' "$locale_name" "$INVALID_CORPUS" -n -b -o target
    compare_file 'invalid UTF-8 ERE spans' "$locale_name" "$INVALID_CORPUS" -E -n -b -o '.'
    compare_file 'invalid UTF-8 PCRE spans' "$locale_name" "$INVALID_CORPUS" -P -n -b -o '.'
    compare_file 'invalid UTF-8 inverted summary' "$locale_name" "$INVALID_CORPUS" -n -v '^valid'
    compare_file 'invalid UTF-8 NUL records' "$locale_name" "$INVALID_NUL_CORPUS" -z -n target
    compare_file 'invalid UTF-8 fixed long-s folding' "$locale_name" "$INVALID_FOLD_CORPUS" -a -F -i -n SearcherBuilder
    compare_file 'invalid UTF-8 fixed long-s listing' "$locale_name" "$INVALID_FOLD_CORPUS" -F -i -l SearcherBuilder
    compare_file 'invalid UTF-8 positive ASCII regex witness' "$locale_name" "$INVALID_WITNESS_CORPUS" -E -l '[[:alnum:]_]{12}'
    compare_file 'Unicode regex witness exact fallback' "$locale_name" "$UNICODE_WITNESS_CORPUS" -E -c '[[:alnum:]_]{12}'
    compare_file 'negated Unicode class cannot use ASCII witness' "$locale_name" "$UNICODE_WITNESS_CORPUS" -E -c '[^[:alnum:]_]{12}'
    compare_tree 'recursive fixed ASCII Unicode word boundaries' "$locale_name" -r -l -F -w SearcherBuilder

    compare_file 'ASCII hybrid fixed case folding' "$locale_name" "$ASCII_CORPUS" -F -i -c rare-needle
    compare_file 'ASCII hybrid fixed word boundary' "$locale_name" "$ASCII_CORPUS" -F -w -n rare-needle
    compare_file 'ASCII hybrid ERE count' "$locale_name" "$ASCII_CORPUS" -E -c 'status=(200|500)'
    compare_file 'ASCII hybrid ERE case folding' "$locale_name" "$ASCII_CORPUS" -E -i -c 'RARE-NEEDLE|STATUS=500'
    compare_file 'ASCII hybrid ERE prefilter' "$locale_name" "$ASCII_CORPUS" -E -n 'route=/api/item/[[:digit:]]+[[:space:]]+status=500'
    compare_file 'ASCII hybrid ERE longest span' "$locale_name" "$ASCII_CORPUS" -E -n -b -o '(rare|rare-needle)'
    compare_file 'ASCII hybrid BRE longest span' "$locale_name" "$ASCII_CORPUS" -G -n -b -o '\(rare\|rare-needle\)'
    compare_file 'ASCII hybrid ERE without literal' "$locale_name" "$ASCII_CORPUS" -E -c '[[:alnum:]_]{4}[[:space:]]+[[:alnum:]_]{7}'
done

printf '%s UTF-8 locale differentials passed (%s cases across %s locales)\n' \
    "$PROG" "$case_count" "${#locales[@]}"
