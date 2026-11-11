# zgr vs zpcre2 v0.4 — generated-corpus comparison

Binary names changed after this capture: `zgr` is now the zpcre2 default and
`zgrc` is the C GNU-compat engine (the former `zgr`). Numbers below keep the
names used when the run was recorded. The current named capture, including
experimental GNU gaps for default `zgr`, is
[benchmark-zgr-zgrc.md](benchmark-zgr-zgrc.md).

Measurement captured on 2026-08-27 at 12:59 CEST on Linux 6.8.0-138 x86_64,
with an Intel Core i9-13900KF (32 logical CPUs), Zig 0.16.0, GNU grep 3.11
and ripgrep 15.1.0. The corpus was the generated file
`/tmp/zgrep-zpcre2-bench.txt`: 100,000 lines, 9,378,980 bytes.

## Compared artifacts

- `zgr` (C PCRE2 JIT), zgrep `90cfb05` plus local engine stubs, ReleaseFast:
  `343c0ef19ee920b1969604f27474261b162f628662c9cf7bd6ac0771c37e03ed`
- `zgr-zpcre2` (zpcre2 [v0.4](https://github.com/mindflight-orchestrator/zpcre2/releases/tag/v0.4)
  `c91d476`) plus an uncommitted `zg_regex_required_literal` prefilter in
  `matcher.zig`, ReleaseFast:
  `1150c89a8535275927fae336944f2c0025b63f60c0b0a9764886c76a4d9cdf5f`

The C shim's `zg_regex_required_literal` always returns false, so only
`zgr-zpcre2` got a study-literal prefilter in front of the engine. Inner-literal
times mix v0.4's matcher with that zgrep-side skip.
- GNU grep 3.11
- ripgrep 15.1.0 (`c3e3c2f7ec`)

zpcre2 v0.4 matches linear grep shapes without the interpreter (literal / class
/ alt chains, including capture slots). That is the change under test relative
to v0.3, which only skipped on a later required literal.

## Method

- warm cache, `LC_ALL=C`, unrestricted CPU
- 5 runs per tool and case, stdout redirected to a regular file
- every case compared with GNU grep before it was timed; all `zgr-zpcre2`
  results matched
- peak RSS from GNU time `%M` (Maximum resident set size, KiB), 3 samples,
  median reported

```sh
zig build -Doptimize=ReleaseFast
bench/generate.sh /tmp/zgrep-zpcre2-bench.txt 100000
BENCH_BATCHES=1 ZGR=./zig-out/bin/zgr \
  bench/run.sh /tmp/zgrep-zpcre2-bench.txt 5
```

This is a small generated-file sample, not the recursive tree profile in
[benchmark-v0.2.md](benchmark-v0.2.md). It does not support universal claims
across machines, file systems or cold caches.

## Time

Milliseconds per run. Lower is better. Ratio is `zgr-zpcre2 / zgr`.

| Workload | zgr | zgr-zpcre2 | grep | ripgrep | zpcre2 / C |
|---|---:|---:|---:|---:|---:|
| literal miss | 3.612 | 3.442 | 4.233 | 3.255 | 0.95× |
| rare literal hit | 3.136 | 2.318 | 4.625 | 3.613 | 0.74× |
| literal case-insensitive | 2.457 | 2.511 | 4.944 | 4.410 | 1.02× |
| word literal | 2.531 | 2.507 | 5.193 | 2.845 | 0.99× |
| **extended regexp** `status=(200\|500)` | 5.021 | 7.897 | 8.998 | 7.581 | **1.57×** |
| regexp with literal suffix | 2.058 | 2.405 | 5.717 | 2.712 | 1.17× |
| literal alternation | 7.311 | 7.171 | 12.585 | 5.698 | 0.98× |
| case-i literal alternation | 10.117 | 8.932 | 13.109 | 14.706 | 0.88× |
| **regexp with inner literal** | 6.987 | **5.257** | 13.076 | 8.837 | **0.75×** |
| regexp without literal | 3.455 | 3.416 | 6.510 | 7.388 | 0.99× |
| literal output `-n` | 2.598 | 2.417 | 5.468 | 3.551 | 0.93× |
| literal output text mode | 2.590 | 2.579 | 5.422 | 3.102 | 1.00× |
| regexp suffix output `-n` | 2.858 | 2.909 | 6.006 | 3.105 | 1.02× |
| regexp only-matching | 2.935 | 2.932 | 6.342 | 3.478 | 1.00× |
| literal alternation output `-n` | 8.051 | 9.189 | 14.239 | 6.571 | 1.14× |
| literal only-matching | 2.462 | 2.409 | 5.090 | 3.067 | 0.98× |
| literal colored output | 2.687 | 2.626 | 5.098 | — | 0.98× |
| regexp colored output | 2.907 | 3.191 | 6.592 | — | 1.10× |
| literal output with context | 2.583 | 2.692 | 5.481 | 3.032 | 1.04× |
| regexp output with context | 8.753 | 10.713 | 7.088 | 3.574 | 1.22× |
| rare literal from stdin | 5.082 | 4.718 | 4.828 | 5.415 | 0.93× |

On the inner-literal ERE
`route=/api/item/[[:digit:]]+[[:space:]]+status=500`, v0.3 (engine skip only,
no zgrep prefilter) was 14.3 ms (~2.3× C). This run is 5.3 ms and **ahead of
C PCRE2 JIT** on this corpus (6.99 ms). Every generated line has the
`route=/api/item/` prefix; only `i % 17 == 0` has `status=500`. Both v0.4's
linear study path and the local matcher prefilter memmem that tail; C did
not get the prefilter.

`status=(200|500)` still matches **every** line, so there is no skip. v0.4
is 7.9 ms versus 5.0 ms for C JIT (~1.6×). Literal paths remain a tie: both
binaries use the same Zig scanner.

## Memory

Peak RSS, KiB (GNU time `%M`), median of 3 samples. The file is 9,158 KiB.

| Workload | zgr | zgr-zpcre2 | grep | ripgrep |
|---|---:|---:|---:|---:|
| literal miss | 11008 | 11008 | 1792 | 13568 |
| rare literal hit | 11008 | 11008 | 1792 | 13568 |
| extended regexp | 12032 | 12288 | 2048 | 13568 |
| inner literal | 11776 | 12288 | 2048 | 13312 |
| regexp without literal | 11776 | 12544 | 1792 | 13056 |
| literal output `-n` | 11008 | 11008 | 1536 | 13568 |
| rare literal from stdin | 2048 | 2048 | 1792 | 4352 |

On a named file, `zgr` and `zgr-zpcre2` sit just above the corpus size
(~10.8 MiB literals, ~11.5–12.3 MiB regex). GNU grep stays near 1.5–2.0 MiB
because it streams. ripgrep is ~13.3 MiB. zpcre2 is within 0.8 MiB of C
PCRE2; there is no extra JIT image, and no large interpreter heap.

From stdin both zgr binaries drop to ~2.0 MiB, in line with grep. That is
the mmap-the-file vs stream-the-pipe split, not an engine difference.

## Raw timing

```
corpus: /tmp/zgrep-zpcre2-bench.txt (9378980 bytes), profile: generated, repeats: 5, batches: 1, locale: C, cache: warm, cpuset: unrestricted, zpcre2: /home/dlamotte/Documents/mindflight/zgrep/zig-out/bin/zgr-zpcre2
literal miss
zgr                               3.612 ms/run
zgr-zpcre2                        3.442 ms/run
grep                              4.233 ms/run
ripgrep                           3.255 ms/run
rare literal hit
zgr                               3.136 ms/run
zgr-zpcre2                        2.318 ms/run
grep                              4.625 ms/run
ripgrep                           3.613 ms/run
literal case-insensitive
zgr                               2.457 ms/run
zgr-zpcre2                        2.511 ms/run
grep                              4.944 ms/run
ripgrep                           4.410 ms/run
word literal
zgr                               2.531 ms/run
zgr-zpcre2                        2.507 ms/run
grep                              5.193 ms/run
ripgrep                           2.845 ms/run
extended regexp
zgr                               5.021 ms/run
zgr-zpcre2                        7.897 ms/run
grep                              8.998 ms/run
ripgrep                           7.581 ms/run
regexp with literal suffix
zgr                               2.058 ms/run
zgr-zpcre2                        2.405 ms/run
grep                              5.717 ms/run
ripgrep                           2.712 ms/run
literal alternation
zgr                               7.311 ms/run
zgr-zpcre2                        7.171 ms/run
grep                             12.585 ms/run
ripgrep                           5.698 ms/run
case-i literal alternation
zgr                              10.117 ms/run
zgr-zpcre2                        8.932 ms/run
grep                             13.109 ms/run
ripgrep                          14.706 ms/run
regexp with inner literal
zgr                               6.987 ms/run
zgr-zpcre2                        5.257 ms/run
grep                             13.076 ms/run
ripgrep                           8.837 ms/run
regexp without literal
zgr                               3.455 ms/run
zgr-zpcre2                        3.416 ms/run
grep                              6.510 ms/run
ripgrep                           7.388 ms/run
literal output with line numbers
zgr                               2.598 ms/run
zgr-zpcre2                        2.417 ms/run
grep                              5.468 ms/run
ripgrep                           3.551 ms/run
literal output text mode
zgr                               2.590 ms/run
zgr-zpcre2                        2.579 ms/run
grep                              5.422 ms/run
ripgrep                           3.102 ms/run
regexp suffix output with line numbers
zgr                               2.858 ms/run
zgr-zpcre2                        2.909 ms/run
grep                              6.006 ms/run
ripgrep                           3.105 ms/run
regexp only-matching output
zgr                               2.935 ms/run
zgr-zpcre2                        2.932 ms/run
grep                              6.342 ms/run
ripgrep                           3.478 ms/run
literal alternation output with line numbers
zgr                               8.051 ms/run
zgr-zpcre2                        9.189 ms/run
grep                             14.239 ms/run
ripgrep                           6.571 ms/run
literal only-matching output
zgr                               2.462 ms/run
zgr-zpcre2                        2.409 ms/run
grep                              5.090 ms/run
ripgrep                           3.067 ms/run
literal colored output
zgr                               2.687 ms/run
zgr-zpcre2                        2.626 ms/run
grep                              5.098 ms/run
regexp colored output
zgr                               2.907 ms/run
zgr-zpcre2                        3.191 ms/run
grep                              6.592 ms/run
literal output with context
zgr                               2.583 ms/run
zgr-zpcre2                        2.692 ms/run
grep                              5.481 ms/run
ripgrep                           3.032 ms/run
regexp output with context
zgr                               8.753 ms/run
zgr-zpcre2                       10.713 ms/run
grep                              7.088 ms/run
ripgrep                           3.574 ms/run
rare literal hit from stdin
zgr                               5.082 ms/run
zgr-zpcre2                        4.718 ms/run
grep                              4.828 ms/run
ripgrep                           5.415 ms/run
```
