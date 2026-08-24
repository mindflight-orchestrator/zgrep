# zgrep

`zgrep` is a performance-first grep/egrep implementation written for Zig
0.16. Small regular files use buffered positional reads while larger files are
memory-mapped. Literal patterns use SIMD/Boyer-Moore-Horspool fast paths, and
compatible non-literal BRE/ERE patterns use PCRE2 JIT. GNU regex semantics
validate or execute constructs that PCRE2 would interpret differently. Regex
`-o` preserves POSIX leftmost-longest spans, using PCRE2 DFA for ambiguous
compatible patterns and GNU matching as the fallback. Counts for literals,
literal ERE alternations and PCRE2 expressions are parallelized with per-thread
mutable state. Sparse required-literal regexes skip directly between candidate
records before running the full matcher. Large regular-file literal,
literal-alternation and sparse
required-literal regex output uses bounded, ordered parallel match discovery;
literal `-o` uses the same path and all eligible modes fall back before output
if their metadata cap would be exceeded. Recursive `-l`/`-L`
searches are also parallel while preserving output order, with one PCRE2 match
state per worker and ordered GNU-style `--include`, `--exclude`, `--exclude-from` and
`--exclude-dir` filters. Binary-file handling follows GNU grep's `binary`,
`text` (`-a`) and `without-match` (`-I`) modes; literal stdin output remains
streaming and bounded by the longest input record. NUL-delimited records
(`-z`/`--null-data`) share the same SIMD, parallel-count, context and PCRE2
paths, including GNU's dot-matches-newline behavior within a NUL record.
Printed filenames can independently use NUL termination with `-Z`/`--null`.
Leading, trailing and symmetric context (`-A`, `-B`, `-C`) use GNU grep's
grouping, separators and match/context prefixes.

This repository is an early implementation. Compatibility and performance are
validated continuously against GNU grep and ripgrep; it is not yet a drop-in
replacement for every GNU grep option.

## Build

Requires Zig 0.16 and PCRE2 8-bit development files.

```sh
zig build -Doptimize=ReleaseFast
```

The build installs two binaries:

- `zig-out/bin/zgrep`: BRE syntax by default.
- `zig-out/bin/zegrep`: ERE syntax by default.

Release binaries are stripped; Debug builds retain symbols.

## Examples

```sh
zig-out/bin/zgrep 'needle' large.log
zig-out/bin/zegrep -n 'error|warning' src/*.zig
zig-out/bin/zgrep -Fic 'content-length' access.log
zig-out/bin/zgrep -nbo -E 'request_[0-9]+' access.log
```

Exit status follows grep: 0 when a line is selected, 1 when no line is
selected, and 2 on an error.

## Verification and benchmarks

`zig build test` runs Zig unit tests, the general CLI differential suite, and a
59-case BRE/ERE semantic matrix against GNU grep. The regex matrix covers
leftmost-longest output, GNU operators, backreferences, intervals, invalid
expressions, whole-line/word matching and PCRE-only syntax traps. A
deterministic structured-text benchmark is included:

`zig build test-stress -Doptimize=ReleaseFast` additionally generates temporary
newline- and NUL-delimited corpora larger than 64 MiB. It forces the production
parallel-output threshold and the bounded dense-match fallback against GNU grep.

`zig build test-fuzz -Doptimize=ReleaseFast` runs a reproducible seeded BRE/ERE
generator against GNU grep. Override `ZGREP_FUZZ_SEED` or
`ZGREP_FUZZ_ITERATIONS` to expand a particular run.

```sh
bench/generate.sh /tmp/zgrep-bench.txt 3000000
ZGREP=./zig-out/bin/zgrep bench/run.sh /tmp/zgrep-bench.txt 20
bench/generate.sh /tmp/zgrep-bench-nul.dat 3000000 nul
ZGREP=./zig-out/bin/zgrep bench/run-null.sh /tmp/zgrep-bench-nul.dat 20
```

Benchmarks force GNU grep into the C locale, use `rg -a`, warm the page cache,
verify every result against GNU grep, and write counts to a regular file so
`/dev/null` shortcuts cannot skew the result. The case matrix is adapted from
ripgrep's dual MIT/Unlicense benchmark suite at commit
`3fce3b5bb0236da2df6d99672afb8a719642eca7`.

Ripgrep's Rust test harness is tied to rg-specific options and cannot execute a
grep-compatible binary unchanged. Its portable scenarios are nevertheless
reused in `tests/differential.sh`: maximum counts, duplicate pattern files,
binary/NUL handling, context grouping and partial context overrides. The
suite also covers NUL-delimited records and recursive include/exclude glob
ordering. The benchmark scripts likewise reuse its two complementary workload families
(one large structured file and a tree of many small files), its literal,
case-insensitive, word, alternation, required-literal and no-literal pattern
classes, and its rule that every timed command must first produce the same
answer.

For the complementary many-small-files workload, point the tree benchmark at
an existing source checkout. It includes hidden and ignored files in ripgrep
so all three tools search the same tree:

```sh
bench/run-tree.sh /path/to/ripgrep/crates SearcherBuilder 20
```

Repeat measurements on an otherwise idle system before making performance
claims across machines.
