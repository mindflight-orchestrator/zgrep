# Historical 0.3.x output measurements — 2026-11-01

[Plan for 0.4.1 (responsiveness) and 0.4.2 (optimization)](../output-optimization-plan.md)

A later review rebuilt the real v0.4.0 and archived [new measurements, raw samples and successful syscall tracing](../baseline-output-v0.4.0-2026-11-01/README.md). The observations and limitations below describe only this earlier 0.3.x session.

**Final comparison: rebuilt 0.4.0 baseline versus 0.4.1 and 0.4.2 candidates.** The historical 0.3.x executable measurements below are supplementary and must not be relabeled as 0.4.0.

## Artifact identity

Source HEAD at inspection: `50f7533649211f87b573826784172e61c71a9830`; manifest version 0.4.0. No tracked changes were present; unrelated `.cursor/` was untracked.

| Artifact | Reported version | SHA-256 |
|---|---|---|
| `/home/dlamotte/.local/bin/zgr` | 0.3.0 | `b72bbc31d602cc270e70ae2ea5f4326688049642c081d5642a938c6030f54dcb` |
| Existing `zig-out/bin/zgr` | 0.3.1 | `3797160790268324f309dc73839bf7b0edc6b0917bd4f145335027b75f2d9020` |

GNU grep 3.11; available compiler Zig 0.16.0; Intel Core i9-13900KF, 32 logical CPUs; Linux 6.8.0-147-generic x86_64. The build configuration of these existing binaries was not independently established. The existing zig-out binary was not rebuilt or proven to match source HEAD. Do not label its timings as a current-source baseline.

## Installed zgr versus grep

1,500,000 generated ASCII log lines, 140,684,742 bytes (134.17 MiB). Recursive corpus: 1,024 files containing the same first 32,768 bytes of the generated corpus (32 MiB total); this is synthetic and not a real source tree. `LC_ALL=C`, warm cache, unrestricted CPU use, regular-file output, one warm-up and nine randomized timed runs per candidate. Times are median wall milliseconds. All 11 cases matched grep's exit status and output; recursive output was compared after sorting lines, so traversal ordering was not checked.

| Workload | grep ms | Installed zgr ms | grep / zgr |
|---|---:|---:|---:|
| literal miss | 16.277 | 7.083 | 2.30x |
| rare literal count | 47.059 | 7.236 | 6.50x |
| dense literal count | 59.627 | 7.787 | 7.66x |
| case-insensitive count | 41.529 | 7.811 | 5.32x |
| dense ERE count | 98.219 | 8.621 | 11.39x |
| inner-literal ERE count | 120.239 | 13.668 | 8.80x |
| no-literal ERE count | 120.527 | 19.795 | 6.09x |
| sparse line output | 56.311 | 13.366 | 4.21x |
| dense line output | 98.509 | 96.550 | 1.02x |
| recursive rare count | 15.011 | 10.911 | 1.38x |
| recursive miss | 21.289 | 19.945 | 1.07x |

The exact runner is saved as [benchmark-installed-original.py](benchmark-installed-original.py). It hardcodes the original installed binary, generator path and `/tmp/bench-installed-zgr-results.json` destination; it creates and removes its own corpus. Do not reinstall a candidate to reuse it: copy/adapt the runner to accept an explicit candidate path and separate results destination for the final comparison. The generated workloads and exact flags are in the runner. [installed-results.json](installed-results.json) retains all saved medians and min/max ranges.

## Exploratory dense output to a regular file

Same generator and size, but pattern `INFO` selects every line. One warm-up and seven timed runs in randomized order, median wall milliseconds; regular output file truncated per run. These measurements are separate from the installed comparison above, whose dense pattern was `status=200` and selected fewer lines.

| Command (corpus operand omitted) | Median ms |
|---|---:|
| Installed zgr `-F INFO` | 73.59 |
| Existing zig-out zgr `-F INFO` | 73.31 |
| GNU grep `-F INFO` | 92.21 |
| Existing zig-out zgr `-F -m 2000000 INFO` | 86.28 |
| cat (all bytes) | 47.47 |
| Existing zig-out zgr `-F -n INFO` | 92.59 |
| Existing zig-out zgr `-F -n -m 2000000 INFO` | 94.40 |

`-m 2000000` exceeds the corpus record count. The inspected source excludes max-count requests from parallel discovery, but the measured existing executable is not proven to match that source. This is not a controlled internal A/B or proof that the metadata path is the bottleneck. `cat` is an output reference, not an equivalent search implementation or guaranteed lower bound.

## Exploratory pseudo-terminal output

Three runs per command, randomized order, `LC_ALL=C`. Newly generated corpus was already in cache. Child stdout attached to a PTY; output postprocessing disabled (`OPOST` cleared); parent immediately drained the master in 65,536-byte reads until EOF/EIO. Time starts before spawning the child. No screen rendering occurs. Output byte counts were measured, not byte-for-byte correctness checked in this probe.

| Existing command (corpus omitted) | First-byte median ms | Total median ms | Output bytes |
|---|---:|---:|---:|
| zig-out zgr `-F INFO` | 10.14 | 246.62 | 140684742 |
| zig-out zgr `-F -n INFO` | 11.76 | 281.98 | 151573638 |
| GNU grep `-F INFO` | 0.87 | 939.86 | 140684742 |
| zig-out zgr `--line-buffered -F INFO` | 10.23 | 991.57 | 140684742 |

## Limits and final comparison protocol

- Individual run samples were not retained. The first benchmark has medians and ranges; exploratory probes have only the medians transcribed above. Their inline scripts were not preserved. Machine-readable summaries are in [environment-and-exploratory-results.json](environment-and-exploratory-results.json).
- Temporary corpora were removed and their hashes were not captured. Regenerate from the archived source's `bench/generate.sh`, then record the corpus hash and retain one immutable corpus for the before/after pair.
- Rebuild unmodified 0.4.0 source (local tag `v0.4.0`, commit `50f7533649211f87b573826784172e61c71a9830`) using Zig 0.16.0 with `zig build -Doptimize=ReleaseFast`, archive both engine binaries outside `zig-out` before rebuilding, and record hashes, source commit and build command. Do not use historical times as the sole denominator for a gain claim: rerun the archived 0.4.0 baseline and candidate (0.4.1 or 0.4.2) together on this machine.
- Reuse exact command flags, locale, CPU policy, output destination type, randomized order, warm-up and repetition count. Keep the installed 0.3.0 comparison separate from the source-before/source-after comparison. Avoid `/dev/null` as the sole output benchmark.
- Extend the controlled matrix to numbered/color output, sparse/dense matches, fast and throttled pipes, and PTY first-result latency. Preserve output bytes and exit statuses; test ordering without sorting when qualifying correctness.
- Capture median, range, first-byte latency, CPU time and peak RSS for baseline and candidate. Record noise and pre-existing failures. PTY results cannot establish actual terminal rendering performance.
- `strace -f -c -e trace=write,writev` failed with `PTRACE_TRACEME: Operation not permitted`; no syscall counts were collected. No CPU-time or peak-memory measurements were collected either.
- The initial comparison against `/usr/bin/zgrep` was for the wrong tool and is intentionally excluded.
