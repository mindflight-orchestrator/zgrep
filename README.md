# zgr

[English](README.md) | [Français](README.fr.md)

Fast, grep-compatible text search written in Zig 0.16 for x86_64 GNU/Linux.

`zgr` combines optimized literal and regular-expression search with GNU-oriented
output semantics. It is designed for large files and recursive source-tree
searches while keeping output ordered and memory bounded.

> [!IMPORTANT]
> This is an early implementation, not yet a complete drop-in replacement for
> every GNU grep option. Compatibility and performance claims are continuously
> checked against GNU grep and ripgrep.

## At a glance

| Item | Value |
|---|---|
| Executable | `zgr` |
| Default syntax | Basic regular expressions (BRE) |
| Other modes | ERE with `-E`, fixed strings with `-F`, PCRE with `-P` |
| Platform | x86_64 GNU/Linux |
| Toolchain | Zig 0.16.0 |
| Native dependencies | glibc and PCRE2 8-bit |
| Project status | Early implementation |

The executable is named `zgr` to avoid colliding with the traditional system
`zgrep` command used for compressed files.

## Highlights

- Fast literal search using SIMD and Boyer-Moore-Horspool-style skipping.
- PCRE2 JIT for compatible BRE, ERE and PCRE workloads, with GNU/POSIX
  fallbacks where semantics differ.
- Ordered parallel processing for large files and recursive directory trees.
- Bounded memory for streaming input, dense output and recursive workloads.
- GNU-style binary handling, context output, colors, filters and diagnostics.
- Differential tests, fuzzing and benchmarks checked against GNU grep and
  ripgrep.

## Quick start

### Requirements

- Zig 0.16.0
- x86_64 GNU/Linux
- PCRE2 8-bit development files

### Build

```sh
zig build -Doptimize=ReleaseFast
```

The stripped release executable is written to `zig-out/bin/zgr`. Debug builds
retain symbols.

### Install

```sh
make
sudo make install
```

This copies `zgr` to `/usr/local/bin`. Override the destination with `PREFIX`,
for example `make install PREFIX=$HOME/.local`. Uninstall with
`sudo make uninstall`.

### Examples

```sh
# Basic regular expression syntax is the default.
zig-out/bin/zgr 'needle' large.log

# Use extended regular expressions explicitly.
zig-out/bin/zgr -E -n 'error|warning' src/*.zig

# Search recursively for a fixed string and print line numbers.
zig-out/bin/zgr -F -r -n 'CONFIG_' /path/to/tree

# Count case-insensitive fixed-string matches.
zig-out/bin/zgr -F -i -c 'content-length' access.log

# Print only matching spans with line numbers and byte offsets.
zig-out/bin/zgr -E -n -b -o 'request_[0-9]+' access.log
```

Exit status follows grep conventions:

- `0`: at least one line was selected;
- `1`: no line was selected;
- `2`: an error occurred.

## Supported behavior

| Area | Current support |
|---|---|
| Pattern syntax | BRE, ERE, fixed strings, PCRE, multiple `-e` patterns and `-f` pattern files |
| Matching | Case folding, inversion, whole words, whole lines and POSIX leftmost-longest `-o` spans |
| Output | Counts, line numbers, byte offsets, matching spans, filenames, context groups and maximum counts |
| Recursive search | `-r`, `-R`, ordered output, `--include`, `--exclude`, `--exclude-from` and `--exclude-dir` |
| Binary data | GNU-style `binary`, `text` and `without-match` modes, plus `-a`, `-I` and `-U` |
| Record formats | Newline or NUL-delimited records with independent NUL-terminated filenames |
| Terminal output | `--color`/`--colour`, `GREP_COLORS`, `--initial-tab` and `--line-buffered` |
| Inputs | Regular files, standard input, explicit FIFOs and devices; recursive devices require `-D read` |
| Locales | GNU-compatible UTF-8 classes, case folding and word boundaries through libc |

Run `zig-out/bin/zgr --help` for the complete option list.

## Performance design

The common paths are selected from the pattern, input type and requested output:

- large regular files are memory-mapped, while small files use buffered
  positional reads;
- literal candidates use SIMD and skip-based search;
- compatible regexes use PCRE2 JIT, with specialized or GNU-compatible paths
  for semantics that PCRE2 would interpret differently;
- eligible count and output workloads run in parallel while preserving GNU
  ordering;
- speculative metadata and captured output remain subject to explicit memory
  limits.

<details>
<summary>Detailed matching and I/O architecture</summary>

### Matching engines

- Compatible non-literal BRE and ERE patterns use PCRE2 JIT.
- GNU regex validation or execution is retained for constructs whose behavior
  differs from PCRE2.
- Ambiguous compatible `-o` expressions use PCRE2 DFA to preserve POSIX
  leftmost-longest spans.
- Positive ERE sequences composed of ASCII bracket classes, exact repetitions
  and `+` can use a bounded 64-state bit-parallel NFA on proven-ASCII records.
- Sparse required-literal regexes jump directly between candidate records and
  classify prefilter density during that same scan.

### Parallel work

- Literal, literal-alternation, class-sequence and PCRE2 counts use per-thread
  mutable state.
- Proven-ASCII class-sequence counts use a calibrated 6 MiB-per-worker budget;
  the general regex count path uses 8 MiB per worker.
- Large-file output uses bounded, ordered parallel match discovery where the
  selected mode permits it. It falls back before output if its metadata cap
  would be exceeded.
- Recursive list and full-line output preserve traversal order. Trees of at
  least 512 regular files use a bounded producer/consumer pipeline so scanning
  can begin while traversal continues.
- Fast literal and required-literal recursive searches use up to 12 workers;
  compute-heavy regexes without a prefilter retain a 16-worker ceiling.

### Memory and streaming

- Recursive output workers format into temporary 64 KiB buffers and retain only
  the exact produced bytes under a shared 16 MiB payload budget.
- Literal standard-input output remains streaming and bounded by the longest
  input record.
- Matching candidates containing NUL bytes fall back before ordered emission;
  invalid UTF-8 summaries propagate in traversal order.
- Buffered and line-buffered write failures preserve the underlying Zig file
  error, including `zgr: write error: Broken pipe`.

### GNU-oriented details

- Leading, trailing and symmetric context use GNU grouping, separators and
  match/context prefixes.
- NUL-data records remain NUL-terminated, while separated context groups retain
  GNU's newline-terminated group separator.
- `--initial-tab` reproduces GNU's size-aware field widths for regular files and
  unknown-size width for pipes.
- ANSI highlighting supports GNU aliases and `GREP_COLORS` capabilities for
  matches, filenames, offsets, separators and context.
- UTF-8 locales use libc semantics for Unicode classes, case folding and word
  boundaries. Proven-ASCII inputs use optimized paths; non-ASCII and malformed
  inputs retain the required GNU fallbacks.

</details>

## Verification

### Standard suite

```sh
zig build test
```

This runs the Zig unit tests and the main GNU differential lanes, including:

- the general CLI behavior matrix;
- 59 BRE/ERE semantic cases;
- 141 UTF-8 locale cases across available `C.utf8`, `en_US.utf8` and
  `nl_BE.utf8` locales;
- ANSI color byte streams, FIFOs, binary/NUL handling and broken-pipe behavior.

### Deterministic regex fuzzing

```sh
zig build test-fuzz -Doptimize=ReleaseFast
```

Use `ZGREP_FUZZ_SEED` and `ZGREP_FUZZ_ITERATIONS` to reproduce or expand a run.

### Large-file and recursive stress

```sh
zig build test-stress -Doptimize=ReleaseFast
```

The stress suite generates newline- and NUL-delimited corpora larger than
64 MiB. It exercises parallel output thresholds, dense-match fallbacks,
greater-than-512-file recursive pipelines, exact output order, binary summaries
and invalid UTF-8 handling against GNU grep.

<details>
<summary>Reused ripgrep scenarios</summary>

The portable scenarios in `tests/differential.sh` adapt maximum-count, duplicate
pattern-file, binary/NUL, context and regression cases from ripgrep's dual
MIT/Unlicense test suite at commit
`3fce3b5bb0236da2df6d99672afb8a719642eca7`.

Ripgrep's Rust harness itself is tied to rg-specific options, so it cannot run a
grep-compatible executable unchanged. The local suite keeps the portable
behavioral cases and validates their results independently.

</details>

## Benchmarks

The repository includes correctness-gated benchmarks for one large structured
file and trees containing many small files. Every candidate result is compared
with GNU grep before it is timed.

The latest saved comparison is documented in
[docs/benchmark-v0.3.md](docs/benchmark-v0.3.md).

### Generated corpus

```sh
bench/generate.sh /tmp/zgrep-bench.txt 3000000
BENCH_BATCHES=5 ZGR=./zig-out/bin/zgr \
  bench/run.sh /tmp/zgrep-bench.txt 20
```

### Existing source tree

```sh
BENCH_PROFILE=ripgrep-linux-default BENCH_BATCHES=5 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run-tree.sh /path/to/linux PM_RESUME 5
```

Repeat performance measurements on an otherwise idle system before making
cross-machine claims.

<details>
<summary>Benchmark profiles and reproducibility controls</summary>

### Additional workloads

```sh
# NUL-delimited generated corpus
bench/generate.sh /tmp/zgrep-bench-nul.dat 3000000 nul
BENCH_BATCHES=5 ZGR=./zig-out/bin/zgr \
  bench/run-null.sh /tmp/zgrep-bench-nul.dat 20

# Ripgrep Sherlock workload
BENCH_PROFILE=ripgrep-sherlock BENCH_BATCHES=9 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run.sh /path/to/ripgrep/tests/data/sherlock-nul.txt 50

# Forced-text Linux profile
BENCH_PROFILE=ripgrep-linux BENCH_BATCHES=5 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run-tree.sh /path/to/linux PM_RESUME 5

# Cold-cache tree samples
BENCH_CACHE=cold BENCH_BATCHES=3 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run-tree.sh /path/to/ripgrep SearcherBuilder 1
```

### Controls

- `BENCH_BATCHES` reports mean, median, p95, minimum and maximum across
  independently timed batches.
- `BENCH_LOCALE` selects the locale; `C` is the default and `C.utf8` exercises
  locale-aware paths.
- `BENCH_CPUSET` pins commands through `taskset` for stable hybrid-core runs.
- `BENCH_CACHE=cold` evicts the corpus outside the timed region and requires one
  repeat per batch.
- Benchmark output is written to regular temporary files rather than
  `/dev/null`, preventing output shortcuts from skewing results.
- The scripts accept the legacy `ZGREP` variable as a fallback for `ZGR`.

The `ripgrep-sherlock`, `ripgrep-linux` and `ripgrep-linux-default` profiles
adapt ripgrep's literal, word, alternation, required-literal and no-literal
workload families. The default Linux profile preserves each tool's normal
binary-file behavior; the forced-text profile uses explicit text modes.

</details>

## CI and releases

[GitHub Actions](.github/workflows/ci.yml) runs Debug, ReleaseSafe and
ReleaseFast tests on Ubuntu 24.04. The ReleaseFast lane also runs deterministic
fuzzing, the greater-than-64-MiB stress suite and a correctness-checked benchmark
smoke test in `C.utf8`.

Annotated `v*` tags trigger the [release workflow](.github/workflows/release.yml).
The workflow verifies that the tag matches `src/main.zig` and `build.zig.zon`,
reruns the release gates, and publishes a stripped x86_64 GNU/Linux archive with
its SHA-256 checksum.

Release archives are dynamically linked to glibc and the PCRE2 8-bit runtime;
they are not advertised as static or universally portable Linux binaries.

## License

[MIT](LICENSE)
