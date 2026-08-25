# zgrep

`zgrep` is a performance-first grep/egrep implementation written for Zig
0.16. Small regular files use buffered positional reads while larger files are
memory-mapped. Literal patterns use SIMD/Boyer-Moore-Horspool fast paths, and
compatible non-literal BRE/ERE patterns use PCRE2 JIT. GNU regex semantics
validate or execute constructs that PCRE2 would interpret differently. Regex
`-o` preserves POSIX leftmost-longest spans, using PCRE2 DFA for ambiguous
compatible patterns and GNU matching as the fallback. Positive ERE sequences
made only of ASCII bracket classes, exact repetitions and `+` use a bounded
64-state bit-parallel NFA on proven-ASCII records, with PCRE2/GNU fallback for
all other syntax and subjects. Counts for literals, literal ERE alternations,
class sequences and PCRE2 expressions are parallelized with per-thread mutable
state. Proven-ASCII class-sequence counts use a calibrated 6 MiB-per-worker
budget while the general regex count path keeps its 8 MiB budget. Sparse
required-literal regexes skip directly between candidate
records before running the full matcher, classifying prefilter density during
that same scan. Large regular-file literal,
literal-alternation and sparse
required-literal regex output uses bounded, ordered parallel match discovery;
literal `-o` plus sparse literal and required-literal regex context output use
the same approach, and all eligible modes fall back before output if their
metadata cap would be exceeded.
Recursive `-l`/`-L`
searches are also parallel while preserving output order, with one PCRE2 match
state per worker and ordered GNU-style `--include`, `--exclude`, `--exclude-from` and
`--exclude-dir` filters. Eligible literal list searches scan each file as one
buffer instead of rediscovering record boundaries; UTF-8 word searches verify
only candidate boundaries through libc. Binary-file handling follows GNU grep's `binary`,
`text` (`-a`) and `without-match` (`-I`) modes; literal stdin output remains
streaming and bounded by the longest input record. NUL-delimited records
(`-z`/`--null-data`) share the same SIMD, parallel-count, context and PCRE2
paths, including GNU's dot-matches-newline behavior within a NUL record.
Printed filenames can independently use NUL termination with `-Z`/`--null`.
Leading, trailing and symmetric context (`-A`, `-B`, `-C`) use GNU grep's
grouping, separators and match/context prefixes.
In NUL-data mode, records remain NUL-terminated while separated context groups
retain GNU's newline-terminated group separator.
`-T`/`--initial-tab` reproduces GNU's size-aware numeric field widths for
regular files and its unknown-size width for pipes. `--line-buffered` flushes
each complete output record and retains streaming context behavior before EOF.
Buffered and line-buffered stdout failures preserve the underlying Zig 0.16
file error, including GNU-compatible `zgrep: write error: Broken pipe`
diagnostics instead of exposing the writer's internal `WriteFailed` sentinel.
`-U`/`--binary` is accepted as the GNU/Linux compatibility no-op.
ANSI highlighting supports `--color`/`--colour` in `always`, `never` and
terminal-aware `auto` modes, including GNU's aliases and `GREP_COLORS`
capabilities for matches, filenames, offsets, separators and context. Explicit
FIFOs and devices are read by default; recursively discovered devices are
skipped unless `-D read` is supplied, matching GNU grep without forcing the
regular-file traversal onto a blocking path.
Recursive `-l`/`-L` searches keep the established scheduler for medium trees.
At 512 regular files, a bounded producer/consumer pipeline begins scanning
while directory traversal continues, then emits completed results in original
traversal order. Its arena-owned paths are NUL-terminated so POSIX workers can
open them without an additional `PATH_MAX` copy. The pipeline uses 12 workers
for fast literal, alternation and required-literal matchers, avoiding queue and
I/O contention, while compute-heavy regexes without a prefilter retain the
16-worker ceiling. Ordinary recursive full-line output uses the same bounded
ordered pipeline in forced-text, default binary and without-match modes. Each
worker formats into one temporary 64 KiB buffer, then retains only the exact
bytes produced under a shared 16 MiB payload budget; this lets thousands of
small dense outputs stay in the first ordered pass without fixed 64 KiB waste.
Matching candidates that contain a NUL fall back before emission, while
invalid UTF-8 summaries are propagated in traversal order.
UTF-8 locales use libc's locale-aware GNU regex semantics for Unicode classes,
case folding and word boundaries. ASCII inputs take a verified SIMD/PCRE2
hybrid path; threaded recursive scans classify an eligible file buffer once
instead of repeating the ASCII check for every record. Non-ASCII records retain
the GNU engine; malformed UTF-8
matches follow GNU's binary/text/only-matching behavior. The same locale matrix
is checked against GNU grep in every normal test run.

This repository is an early implementation. Compatibility and performance are
validated continuously against GNU grep and ripgrep; it is not yet a drop-in
replacement for every GNU grep option. The current supported build target is
x86_64 GNU/Linux; the GNU regex and POSIX mmap dependencies have not yet been
ported to macOS or Windows.

## Build

Requires Zig 0.16, GNU/Linux and PCRE2 8-bit development files.

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

`zig build test` runs Zig unit tests, the general CLI differential suite, a
59-case BRE/ERE semantic matrix and a 141-case UTF-8 locale matrix against GNU
grep. The locale cases run across every available `C.utf8`, `en_US.utf8` and
`nl_BE.utf8` locale and include malformed UTF-8 plus the optimized ASCII
hybrid, long-s/dotless-i folds, exact POSIX class semantics and recursive Unicode
word boundaries. The regex matrix covers
leftmost-longest output, GNU operators, backreferences, intervals, invalid
expressions, whole-line/word matching and PCRE-only syntax traps. A
deterministic structured-text benchmark is included. The general differential
suite also compares ANSI color byte streams, explicit/recursive FIFO handling,
and buffered plus line-buffered broken-pipe diagnostics:

`zig build test-stress -Doptimize=ReleaseFast` additionally generates temporary
newline- and NUL-delimited corpora larger than 64 MiB. It forces the production
parallel-output threshold for literal and required-literal regex context, plus
the bounded dense-match fallback, against GNU grep. A separate
greater-than-512-file tree forces the recursive list/output pipelines and
checks exact file/output order, default binary summaries, invalid UTF-8
suppression and NUL-delimited records.

`zig build test-fuzz -Doptimize=ReleaseFast` runs a reproducible seeded BRE/ERE
generator against GNU grep. Override `ZGREP_FUZZ_SEED` or
`ZGREP_FUZZ_ITERATIONS` to expand a particular run.

```sh
bench/generate.sh /tmp/zgrep-bench.txt 3000000
ZGREP=./zig-out/bin/zgrep bench/run.sh /tmp/zgrep-bench.txt 20
BENCH_BATCHES=5 ZGREP=./zig-out/bin/zgrep bench/run.sh /tmp/zgrep-bench.txt 20
BENCH_BATCHES=5 BENCH_CACHE=cold BENCH_CPUSET=0-15 \
  ZGREP=./zig-out/bin/zgrep bench/run.sh /tmp/zgrep-bench.txt 1
BENCH_PROFILE=ripgrep-sherlock BENCH_BATCHES=9 BENCH_CPUSET=0-15 \
  ZGREP=./zig-out/bin/zgrep \
  bench/run.sh /path/to/ripgrep/tests/data/sherlock-nul.txt 50
bench/generate.sh /tmp/zgrep-bench-nul.dat 3000000 nul
BENCH_BATCHES=5 ZGREP=./zig-out/bin/zgrep bench/run-null.sh /tmp/zgrep-bench-nul.dat 20
```

Benchmarks default to the C locale, use `rg -a`, warm the page cache, verify
every result against GNU grep, and write output to a regular file so `/dev/null`
shortcuts cannot skew the result. Set `BENCH_LOCALE=C.utf8` to measure the
locale-aware hybrid under the same correctness gate. Set `BENCH_BATCHES` above
one to report mean, median, p95, minimum and maximum across independently timed
batches; each batch contains the requested number of repetitions so timestamp
process overhead remains amortized. `BENCH_CACHE=cold` uses GNU `dd`'s
`iflag=nocache,count=0` for a single corpus, while the tree harness compiles a
temporary one-process `posix_fadvise` walker. Both require one repeat per batch,
and eviction stays outside the timed region. `BENCH_CPUSET` passes an
explicit CPU list to `taskset` so hybrid-core machines can be measured on a
stable subset. The case matrix is adapted from
ripgrep's dual MIT/Unlicense benchmark suite at commit
`3fce3b5bb0236da2df6d99672afb8a719642eca7`.
`BENCH_PROFILE=ripgrep-sherlock` selects its seven English-subtitle pattern
families for a supplied corpus; `BENCH_PROFILE=ripgrep-linux` selects its seven
forced-text Linux-tree literal, word, alternation and regex families. Use
`BENCH_PROFILE=ripgrep-linux-default` to replay the same matrix with each
tool's default binary-file handling.

Ripgrep's Rust test harness is tied to rg-specific options and cannot execute a
grep-compatible binary unchanged. Its portable scenarios are nevertheless
reused in `tests/differential.sh`: maximum counts, duplicate pattern files,
binary/NUL handling, context grouping and partial context overrides. The
suite also covers NUL-delimited records, recursive include/exclude glob
ordering, initial-tab formatting and observable line-buffered streaming before
EOF. The benchmark scripts likewise reuse its two complementary workload families
(one large structured file and a tree of many small files), its literal,
case-insensitive, word, alternation, required-literal and no-literal pattern
classes, and its rule that every timed command must first produce the same
answer.

For the complementary many-small-files workload, point the tree benchmark at
an existing source checkout. It includes hidden and ignored files in ripgrep
so all three tools search the same tree:

```sh
BENCH_BATCHES=5 bench/run-tree.sh /path/to/ripgrep/crates SearcherBuilder 20
BENCH_PROFILE=ripgrep-linux BENCH_BATCHES=5 BENCH_CPUSET=0-15 \
  bench/run-tree.sh /path/to/linux PM_RESUME 5
BENCH_PROFILE=ripgrep-linux-default BENCH_BATCHES=5 BENCH_CPUSET=0-15 \
  bench/run-tree.sh /path/to/linux PM_RESUME 5
BENCH_CACHE=cold BENCH_BATCHES=3 BENCH_CPUSET=0-15 \
  bench/run-tree.sh /path/to/ripgrep SearcherBuilder 1
```

Repeat measurements on an otherwise idle system before making performance
claims across machines.

## CI and releases

GitHub Actions runs Debug, ReleaseSafe and ReleaseFast tests on Ubuntu 24.04.
The ReleaseFast lane also runs deterministic fuzzing, the greater-than-64-MiB
stress suite and a correctness-checked benchmark smoke test in `C.utf8`.

Annotated version tags trigger the release workflow. It rejects tags that do
not match both `src/main.zig` and `build.zig.zon`, reruns the full release gates,
then publishes stripped `x86_64-linux-gnu` archives plus SHA-256 checksums. The
archive remains dynamically linked to glibc and the PCRE2 8-bit runtime; it is
not advertised as a portable or static binary.
