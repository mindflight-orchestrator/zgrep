# Zig backends and Rust/C comparison — 11 November 2026

[Français](benchmark-backends.fr.md) | [Evidence index](benchmark-backends-2026-11-11/README.md)

The measured runtime-oriented profile is **Zig 0.16.0, ReleaseFast, LLVM**.
Zig's own x86 backend compiled much faster in this experiment but produced
substantially slower executables. The subsequent LLVM comparison beats GNU
grep in all 12 measured cases; ripgrep retains an advantage in several literal
searches and sparse numbered output.

## Build configuration

```sh
zig build -Doptimize=ReleaseFast -Dllvm=true -Dcpu=native
zig-out/bin/zgr --version
```

Bare `zig build` defaults to Debug in this repository; `make` defaults to
ReleaseFast. Previous benchmark scripts ran existing executables without
checking their build configuration. Their names alone cannot establish the
mode used in historical results.

ReleaseFast enables optimization and disables runtime safety checks by default.
This trades build time for runtime performance, with correctness checked
separately. [Zig 0.16 build modes](https://ziglang.org/documentation/0.16.0/#Build-Mode).

The new project option `-Dllvm=true` selects LLVM for executables and Zig tests;
direct compiler invocations use `-fllvm`. `-Dllvm=false` selects Zig's own
backend. Independently, `-Dcpu=native` selects the host CPU instruction set;
such binaries are not necessarily portable to older processors.

Both backends produce native machine code. There is no LLVM virtual machine
at runtime. Zig's 0.15.1 release notes describe the x86 backend's faster builds,
slower emitted code and development focus. That historical context is checked
against local 0.16.0 and 0.17.0 measurements below.
[Official x86 backend notes](https://ziglang.org/download/0.15.1/release-notes.html#x86-Backend).

No flag guarantees the fastest possible program. LTO, PGO and other CPU targets
were not compared here. ReleaseFast already strips symbols in this project;
stripping alone does not optimize search loops.

## Experiment 1: Zig 0.16/0.17 with both backends

Baseline commit: `a373c95b99e1c5fd9f5a8b7001c82a296db96d88`.
Pinned zpcre2: `b93f4d8d999f1f000ecc3644c844294802ba78bb`.
Separate copies built both `zgr` and `zgrc` for every variant. Local commands
`zig-0.16 version` and `zig-0.17 version` reported `0.16.0` and `0.17.0`.
The latter required isolated syntax/API changes preserved in the
[compatibility patch](benchmark-backends-2026-11-11/zig-017-compatibility.patch).
This experiment does not qualify a project migration; the repository and CI
remain on Zig 0.16.0.

Selected `zgr` medians, lower is faster:

| Variant | zgr compilation (s) | Rare literal (ms) | Dense regex (ms) |
|---|---:|---:|---:|
| Zig 0.16 LLVM | 5.82 | 1.566 | 2.374 |
| Zig 0.16 native | 0.26 | 119.094 | 177.870 |
| Zig 0.17 LLVM | 5.92 | 1.406 | 2.559 |
| Zig 0.17 native | 0.26 | 120.347 | 182.325 |

Compilation uses three `build-exe` invocations per variant, fresh local caches,
prepared global infrastructure caches and `-j2`, in sequential randomized order.
It excludes build-runner compilation and `translate-c`. Initial complete builds
had unequal cache preparation and are not a valid compilation comparison.
Short durations are rounded because of process-wait timing granularity.

Runtime uses 100,000 ASCII lines (9,378,980 bytes), locale C, logical CPU 2 on
an i9-13900KF, warm data and output to a regular file. Two warmups and fifteen
randomized paired rounds per case passed all 1,360 output/status checks across
both executables and ten cases. These results strongly favor LLVM over Zig's
own backend, but do not establish a general 0.17 LLVM improvement over 0.16 LLVM.
Small launch-dominated measurements and workload differences limit that claim.
All twelve recompiles passed a rare-literal check; LLVM executable hashes were
reproduced, while native-backend hashes were not all reproduced.

Evidence: [runtime](benchmark-backends-2026-11-11/benchmark-results.json),
[compilation](benchmark-backends-2026-11-11/compile-results.json),
[recompilation checks](benchmark-backends-2026-11-11/recompile-validation.json).

## Explaining the code-generation gap

Two Zig 0.16 kernels isolate `isAscii` from `src/matcher.zig` and a first-NUL
search using `std.mem.findScalar`. They use the same C driver and already
allocated 9,378,980-byte buffer, with no timed disk I/O, two warmups and fifteen
samples.

| Kernel | LLVM (ms) | Native backend (ms) |
|---|---:|---:|
| ASCII check | 0.224 | 13.441 |
| Absent NUL search | 0.143 | 10.488 |

LLVM's `is_ascii` assembly uses `vmovdqu` and `vpmovmskb` for 32-byte groups.
The native backend spills vectors to the stack and uses per-byte comparisons
to construct the mask. Vector source code therefore does not guarantee equal
machine-code quality across backends. This establishes a concrete mechanism
in search primitives, without attributing the entire application's slowdown
to these two kernels; that would require full profiling.
[Kernel sources, assembly and measurements](benchmark-backends-2026-11-11/kernels/).

## Experiment 2: LLVM candidate versus Rust and C tools

**Follow-up audit clarification:** this capture passed `-a` only to ripgrep.
Binary detection therefore added work to `zgr` for line-output cases; its `-c`
path already skips that prescan. Raw evidence is unchanged. The [focused audit
(French)](performance-audit.fr.md) records new measurements with equivalent
options (`auto` or `-a` for every tool).
Its opening section now records the retained adaptive-counting optimization,
including comparisons with Rust/C and measured secondary regressions.

The candidate uses the baseline commit plus the local benchmark/build-metadata
changes. Compilation-input hashes are recorded in the JSON. It is not a new
published tag.

| Tool | Version / build |
|---|---|
| zgr | 0.4.1, Zig 0.16.0, ReleaseFast, stage2_llvm, raptorlake CPU, zpcre2 |
| zgrc | 0.4.1, same Zig profile, C PCRE2/glibc engine |
| ripgrep | Installed Rust executable, 15.2.0, revision e89fff89ac, runtime AVX2 |
| GNU grep | Installed C executable, 3.11, correctness reference |

`zgrc` is Zig with a C engine; GNU grep is the external C reference. The original
build flags of ripgrep and GNU grep are unknown here. This compares different
tools and algorithms, rather than isolating programming-language performance.

The generated corpus contains 1,000,000 lines and **93,789,827 bytes**. Locale C,
logical CPU 2, two warmups, fifteen randomized rounds, seed 711. All child threads
inherit the CPU affinity, so this does not measure multi-core throughput.
Timing includes process startup and regular-file output without `fsync`, using
warm data; it does not measure cold storage or terminal rendering.

Medians in milliseconds, lower is faster:

| Case | zgr LLVM | zgrc LLVM | ripgrep (Rust) | GNU grep (C) |
|---|---:|---:|---:|---:|
| Literal miss | 15.655 | 16.246 | 13.980 | 25.659 |
| Rare literal | 15.948 | 16.495 | 14.069 | 36.450 |
| Case insensitive | 15.306 | 13.570 | 15.219 | 35.036 |
| Word literal | 15.815 | 16.393 | 13.732 | 35.793 |
| Dense regex | 29.140 | 28.996 | 63.717 | 90.879 |
| Regex suffix | 13.940 | 13.737 | 13.652 | 43.443 |
| Alternation | 33.311 | 33.301 | 33.286 | 119.999 |
| Regex no literal | 33.783 | 33.587 | 62.111 | 58.814 |
| Sparse numbered | 19.392 | 16.465 | 13.131 | 39.317 |
| Dense numbered | 58.144 | 58.336 | 165.480 | 89.624 |
| Dense plain | 44.538 | 44.658 | 83.510 | 56.999 |
| Regex output | 24.902 | 33.628 | 54.199 | 86.136 |

All **816 checked runs**, including 720 timed runs, matched GNU grep in exit
status, output size and output SHA-256. Exact commands, executable hashes,
samples and bootstrap 95% intervals of paired ratios are in
[comparison-llvm-rust-c.json](benchmark-backends-2026-11-11/comparison-llvm-rust-c.json).
Ratios above 1 favor the Zig executable. Median paired ratios need not equal
ratios of the displayed medians. Tiny differences do not justify ranking tools.

## Reproduction and release checks

On Linux with Python 3.11+, Zig 0.16.0, GNU grep, ripgrep and project dependencies:

```sh
zig build -Doptimize=ReleaseFast -Dllvm=true -Dcpu=native
zig build test -Doptimize=ReleaseFast -Dllvm=true
bench/generate.sh /tmp/zgrep-comparison.txt 1000000
python3 bench/compare.py --corpus /tmp/zgrep-comparison.txt \
  --cpu 2 --repeats 15 --output /tmp/zgrep-comparison.json
```

Choose an available CPU and a new JSON filename for each run. Omit `--cpu` to
retain existing affinity; use `--zgr`, `--zgrc`, `--rg`, `--grep` to select
binaries. This comparator covers the generated newline ASCII profile; separate
tests and scripts cover trees, NUL records, Unicode and streaming.

`--version` now reports the actual Zig version, optimization mode, backend and
CPU model. Benchmark launchers require ReleaseFast + LLVM. Explicit
`BENCH_ALLOW_UNOPTIMIZED=1` exploration prints a warning and is recorded in
JSON. Existing result files are preserved.

CI and release packaging explicitly build with LLVM and compare all four tools
on 100,000 lines with three rounds. Release archives include `benchmark.json`.
Incorrect output blocks packaging; timing has no release threshold on a shared
runner.

Local validation passed: 82/82 unit tests, CLI and streaming differentials,
59 regex cases, 141 locale cases, build-profile checks, a three-round C.utf8
comparison and the existing shell benchmark. Logs are archived with the data.
The modified GitHub workflows have not been run remotely during this research.
These results establish local validation; no tag, push or publication was made
for this work.
