# Rebuilt v0.4.0 output baseline — 2026-11-01

[Revised 0.4.1/0.4.2 plan](../output-optimization-plan.md) · [Adversarial review](../output-optimization-review-2026-11-01.md)

This baseline was built from unchanged v0.4.0 sources. It supersedes the historical 0.3.x executables as the source-version reference, while retaining those earlier measurements separately. No 0.4.1 or 0.4.2 change or full release qualification has been performed. Normalized stderr was not compared with GNU grep, and the `-I` stdin, stdout/stderr ordering and SIGPIPE behaviors found in the second review round are not covered by these probes.

## Build and artifact identity

- Source tag `v0.4.0`, commit `50f7533649211f87b573826784172e61c71a9830`, exported with `git archive` to a scratch directory; no source edits.
- Zig 0.16.0, `-Doptimize=ReleaseFast`, native target. Build/install/cache paths were isolated in `/tmp`.
- Local `../zpcre2` commit `b93f4d8d999f1f000ecc3644c844294802ba78bb`, exported and fetched locally. Resulting package hash exactly matched `zpcre2-0.1.0-inU7b6KUBwChJsSYFblMFLP_583TLP-QpqI4KENIYXlD`.
- A sandbox cache restriction required the build to run with execution escalation. No installed binary was replaced. Syscall tracing later succeeded with the required ptrace execution authority.

| Binary | Reported version | SHA-256 |
|---|---|---|
| zgr | 0.4.0 | `706eae7cda893743dcb5e35af14e08fb6350d5918252d70938b6ac1259d02113` |
| zgrc | 0.4.0 | `a84e1579c5a69293fc7ab3e3536289daeefad8756eb6f1a7941b0b252f9c666c` |

[provenance.json](provenance.json) records the original binary paths, compiler, CPU, build identities and limits. These paths are historical locations in `/tmp`, not durable artifact storage. This archive preserves measurements, scripts and hashes; compiled executables and the 134 MiB corpus are not copied into documentation. Preserve or rebuild the matching baseline before the final paired comparison.

## File-output measurements

Generator: [generate-corpus-original.sh](generate-corpus-original.sh), 1,500,000 lines, 140684742 bytes. Corpus SHA-256: `77d7d8cf9ca95b1668a4cf87961ef4bf1e6898d4065b4c440ea9a0ab05742072`.

Intel Core i9-13900KF, unrestricted CPU affinity, `LC_ALL=C`, warm cache. Each case performs one warm-up/correctness pass and seven randomized timed runs per tool. Stdout goes to a regular file truncated for each run; timing includes process launch/wait and cached writes, without `fsync`. Every scenario matched GNU grep's stdout hash and exit status; this probe did not compare normalized stderr.

Median wall milliseconds:

| Workload | zgr 0.4.0 | zgrc 0.4.0 | GNU grep |
|---|---:|---:|---:|
| all plain | 71.489 | 73.846 | 83.746 |
| all forced text | 66.135 | 67.915 | 88.375 |
| dense plain | 94.199 | 104.596 | 101.283 |
| all numbered | 93.831 | 88.789 | 135.020 |
| all colored | 145.166 | 153.790 | 240.669 |
| sparse plain | 10.192 | 10.603 | 49.055 |

[file-results.json](file-results.json) retains all individual wall/user/system/RSS samples, arguments, output sizes and hashes. User/system medians are separate statistics and must not be added to derive a phase breakdown. Peak RSS includes input mappings and can include inherited launcher high-water state; it is not heap-only memory.

[benchmark-file-original.py](benchmark-file-original.py) is an exact copy of the runner used. It hardcodes the scratch build/source/evidence paths in `provenance.json` and recreates its output directory contents. Treat it as the original experimental recipe. For final comparison, use a separately adapted runner with explicit immutable baseline/candidate paths and new output destinations; do not overwrite this archive or install the candidate to run a benchmark.

## Slow stdin to a pseudo-terminal

The child reads a pipe kept open while two complete matching records are sent separately. Stdout is a PTY with `OPOST` disabled; the parent waits up to 200 ms for output after each input record. No screen renderer is involved.

- zgr 0.4.0 default: neither record appeared in the two observation windows; both appeared after EOF.
- zgr 0.4.0 with `--line-buffered`: each record appeared before further input/EOF.
- GNU grep default and `--line-buffered`: each record appeared before further input/EOF.

[live-tty-results.json](live-tty-results.json) preserves the observed bytes, statuses and observation durations. [benchmark-live-tty-original.py](benchmark-live-tty-original.py) is the exact runner, with its original scratch paths. This is a behavioral probe, not a latency distribution or terminal rendering benchmark.

## Syscall observation

[syscalls-plain.txt](syscalls-plain.txt) records **537 `writev` calls** for `zgr -F INFO` selecting all 1.5 million records to a regular file. The traced command was:

```sh
strace -f -c -e trace=write,writev -o /tmp/zgr-plan-review-evidence/syscalls-plain.txt \
  env LC_ALL=C /tmp/zgr-plan-review-v040/bin/zgr -F INFO \
  /tmp/zgr-plan-review-evidence/corpus.log > /tmp/zgr-plan-review-evidence/traced.out
```

The temporary traced output file was removed after capturing the summary. Do not use traced durations as uninstrumented performance measurements.

## Reproduction and limits

Regenerate the corpus with the archived generator, then verify its size and hash before comparison:

```sh
sh generate-corpus-original.sh /tmp/zgr-comparison-corpus.log 1500000
sha256sum /tmp/zgr-comparison-corpus.log
```

Rebuild the exact source and dependency revisions with Zig 0.16.0 ReleaseFast if scratch artifacts have expired. Record the resulting hashes and build/environment differences. Rerun baseline and candidate together: archived historical timings alone are not a valid performance-gain denominator.

The complete project test suite was not run during this review. These ASCII warm-cache file-output and small PTY probes do not establish cold-cache, Unicode, recursive ordering, cancellation, or full GNU compatibility. The [revised plan](../output-optimization-plan.md) defines the additional qualification matrix and staged acceptance gates.
