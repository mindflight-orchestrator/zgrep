#!/bin/sh
set -eu

OUTPUT=${1:-/tmp/zgrep-bench-varied.txt}
LINES=${2:-3000000}
RECORD_MODE=${3:-newline}

case "$RECORD_MODE" in
    newline) TERMINATOR=10 ;;
    nul) TERMINATOR=0 ;;
    *)
        echo "record mode must be 'newline' or 'nul'" >&2
        exit 2
        ;;
esac

awk -v lines="$LINES" -v terminator="$TERMINATOR" 'BEGIN {
    for (i = 0; i < lines; i++) {
        status = (i % 17 == 0 ? 500 : 200)
        marker = (i % 1000 == 0 ? " rare-needle" : "")
        printf "2026-08-23 INFO request_id=%016x route=/api/item/%d status=%d latency_us=%d%s%c", \
            i * 2654435761, i % 100003, status, (i * 48271) % 100000, marker, terminator
    }
}' >"$OUTPUT"
wc -c -l "$OUTPUT"
