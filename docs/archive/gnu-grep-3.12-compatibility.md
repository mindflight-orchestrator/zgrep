# GNU grep 3.12 official-suite comparison

[English](gnu-grep-3.12-compatibility.md) | [Français](gnu-grep-3.12-compatibility.fr.md)

Binary names changed after this capture: `zgr` is now the zpcre2 default and
`zgrc` is the C GNU-compat engine (the former `zgr`). The table below keeps the
names used when the suite was run.

This comparison was captured on 2026-08-28 from commit `0e97e41` on Linux
6.8.0-138 x86_64 with Zig 0.16.0. It complements the repository's focused
differential tests by running GNU grep's own functional test suite unchanged
against both zgr regex backends.

## Reproducibility

- official source: [GNU grep 3.12](https://ftp.gnu.org/gnu/grep/grep-3.12.tar.xz)
- source SHA-256:
  `2649b27c0e90e632eadcd757be06c6e9a4f48d941de51e7c0f83ff76408a07b9`
- configuration: `configure --disable-nls`
- build: `make -j8`
- functional suite: the generated `tests/Makefile`, invoked with
  `make -j8 check` after `make clean`

The native GNU binary was tested first. For each zgr run, only the generated
`src/grep` entry point was replaced with a wrapper that executes the frozen
candidate binary. GNU's generated `egrep` and `fgrep` wrappers therefore used
the same candidate through `grep -E` and `grep -F`. Test files and commands
were not edited.

Tested ReleaseFast binaries:

- `zgr` (C PCRE2):
  `fdc9ecb6223ca8fdab9ccd807f1a6b70cc5e8f6e53cdbcb4e82670126133aa92`
- `zgr-zpcre2`:
  `113499f16a8137c0053763978d082ecc76987cc2aca2b61dfb6a403be9585358`

The complete candidate runs disabled core dumps and limited each generated
file to 128 MiB. This bound was added after an initial unbounded run exposed
the `in-eq-out-infloop` failure described below; it did not change the official
test commands.

## Results

| Implementation | Total | Pass | Skip | XFAIL | Fail | XPASS | Error |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| GNU grep 3.12 | 128 | 107 | 19 | 2 | 0 | 0 | 0 |
| zgr, C PCRE2 | 128 | 84 | 19 | 0 | 23 | 2 | 0 |
| zgr-zpcre2 | 128 | 80 | 19 | 1 | 27 | 1 | 0 |

The two C-backend XPASS results, `glibc-infloop` and `triple-backref`, are
positive unexpected passes for cases that GNU marks as expected failures.
The zpcre2 backend XPASSes `triple-backref`; `glibc-infloop` remains XFAIL.

The full top-level GNU `make check` additionally runs gnulib tests. Five socket
tests failed with `EBADF` in the sandbox. They are outside grep's 128-test
functional suite and are not attributed to any grep implementation.

## Failure comparison

Both backends fail these 22 test files:

`binary-file-matches`, `bre`, `color-colors`, `context-0`, `ere`,
`filename-lineno`, `hangul-syllable`, `help-version`, `in-eq-out-infloop`,
`include-exclude`, `initial-tab`, `max-count-overread`, `pcre`, `pcre-abort`,
`pcre-context`, `pcre-wx-backref`, `skip-read`, `stack-overflow`,
`version-pcre`, `warn-char-classes`, `write-error-msg`, and `yesno`.

Only the C-PCRE2 binary fails `pcre-utf8-bug224`.

Only the zpcre2 binary fails `backref`, `c-locale`, `case-fold-char-type`,
`spencer1`, and `spencer1-locale`. It passes `pcre-utf8-bug224` and fewer
individual BRE cases than the C backend, but regresses cross-pattern
backreferences, C-locale handling, locale-sensitive case folding, and several
Spencer regex cases. The net result is four fewer passing test files.

## Highest-priority findings

1. `in-eq-out-infloop`: zgr does not reject a file used simultaneously as
   input and redirected output. It can grow the file until storage is
   exhausted; GNU grep returns status 2.
2. `stack-overflow`: several official cases terminate zgr with a segmentation
   fault instead of reporting a controlled `stack overflow` error.
3. `max-count-overread` and parts of `yesno`: zgr consumes stdin beyond the
   requested `-m` match limit, changing the stream left for its caller.
4. `include-exclude`, `context-0`, and `yesno`: recursion filters, context
   separators and grouping options differ observably from GNU grep.
5. zpcre2 adds locale, case-folding and Spencer-suite regressions beyond the
   shared failures.

## Interpretation

A regex-engine microbenchmark and a complete grep compatibility suite measure
different things. The former can show zpcre2 matching an isolated expression
faster than C PCRE2. The latter also exercises parsing, streaming and mmap I/O,
line handling, output formatting, recursion, locales, diagnostics and exact
GNU semantics. Engine speed therefore does not imply either lower end-to-end
latency or better CLI compatibility.
