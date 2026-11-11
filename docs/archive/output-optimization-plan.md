# zgr 0.4.1 / 0.4.2 — responsiveness, compatibility and output optimization

Revised 2026-11-01 following the [adversarial review](output-optimization-review-2026-11-01.md), including its second round (§8–§14), then corrected on 2026-11-02 by a third round of probes (§15–§20 of the review). Both bulk throughput and terminal responsiveness are priorities, but they are delivered separately. The reference for 0.4.1 is **GNU grep 3.11**, the locally installed version that also drives the differential tests.

Baseline: **v0.4.0**, commit `50f7533649211f87b573826784172e61c71a9830`. Use the [rebuilt 0.4.0 measurements and provenance](baseline-output-v0.4.0-2026-11-01/README.md). The [older 0.3.x measurements](baseline-output-2026-11-01/README.md) are supplementary only.

## 0. Release split

The user-visible defect is a compatibility bug, not a throughput problem: `tail -f log | zgr ERROR` shows nothing on a terminal until EOF, and `-I` on stdin never streams at all. It must not wait for the full optimization matrix.

- **0.4.1 — responsiveness and compatibility** (§2): stdin/TTY flushing, the `-I` stdin path, stdout/stderr ordering and the SIGPIPE decision. Qualified by correctness gates, the behavioral probes and a non-regression throughput check (§5), not by a 10% gain requirement.
- **0.4.2 — output optimization** (§3–§4): spans, discarded discovery work, regular-file and recursive latency barriers, specialization and the optional writer pipeline, each under the full acceptance matrix.

Each release applies to both `zgr` and `zgrc`. Timebox each 0.4.2 optimization; if it has not met its declared target within that budget, drop it rather than widening the scope or the acceptance criteria.

## 1. Establish costs and preserve a reproducible baseline

The reviewed source was rebuilt with Zig 0.16.0 ReleaseFast and the exact local zpcre2 dependency. Six file-output scenarios matched GNU grep's stdout and exit status. For 1.5 million lines (134.17 MiB), plain output took 71.489 ms; tracing recorded only 537 `writev` calls. Buffered vectored writes already exist. The complete project test suite has not yet been run for this baseline.

Sections marked *0.4.2* below are not prerequisites of 0.4.1, which only needs the baseline binaries, the test status and the behavioral probes.

Before any change:

- Keep immutable baseline binaries for both engines, source/dependency/compiler identities, build commands and hashes. Regenerate the saved corpus and verify its SHA-256. The archived scripts preserve the original probes; adapt a separate comparison runner to explicit baseline/candidate paths and separate results directories rather than installing either binary.
- The runner must refuse to start unless each binary's `--version` and SHA-256 match the declared identity. The working tree's `zig-out/bin/zgr` currently reports **0.3.1**; a previous session already measured the wrong executables.
- Complete the baseline correctness gates and record individual pre-existing failures, especially the experimental zpcre2/GNU lanes. A pre-existing failure is not permission to accept a new or changed failure.
- *0.4.2:* Profile binary/locale prescans, match discovery, metadata allocation and cap fallback, formatting, copying, and output. Capture work discarded by fallback and time until the first complete result. Keep diagnostic instrumentation out of acceptance timing; overlapping worker CPU times are not additive wall-time phases.
- Inspect regular-file, stdin/FIFO, context and recursive paths separately. `scanRegularBuffer` performs binary prescans; `parallelSelectedOutput` and `parallelSparseContextOutput` wait for discovery; recursion has its own capture and ordered output pipelines, including a 16 MiB payload budget. On stdin, `requiresBufferedScan` (`-I`, `src/main.zig:1946`) reads the whole input with `allocRemaining(.unlimited)` before scanning.
- Compare normalized stderr and exit status against GNU grep, not only stdout. The 0.4.0 baseline did not.

Do not treat every formatter call as a syscall, assume larger buffers help, or infer the cost of parsing by subtracting `cat` timings. Scope remains output behavior and its scheduling; regex semantics are not redesigned.

## 2. 0.4.1 — responsiveness and compatibility

Introduce an internal output policy shared consistently by all relevant paths; no new CLI option is required. Reference behavior is GNU grep 3.11; where this plan is deliberately stricter than GNU, say so in the release notes.

**Flush rule.** "Before a potentially blocking read" cannot be detected in advance. Use a concrete rule: when stdout is a TTY and the input is not a regular file, flush complete buffered output before every input read. `takeDelimiter` refills internally, so the rule lives in a reader wrapper (`scanner.InputReader`) rather than at each call site. This costs at most one `writev` per input read. Completion of each file operand must flush any remaining output on a TTY. A first-result-only flush is insufficient. Do not add a timer thread or a general asynchronous writer merely to flush output.

- `--line-buffered`: flush every completed output record, including context, as it becomes safe to emit. Preserve its behavior with a producer that keeps stdin/FIFO open.
- NUL-delimited output (`-z`): GNU 3.11 and zgr 0.4.0 both emit each record immediately with `--line-buffered`. Without it, GNU holds NUL records on a terminal until EOF because its stdio only flushes at a newline. zgr applies the flush rule regardless and is deliberately stricter here.
- Regular files and recursion are out of 0.4.1. On a 134 MiB file the first result reaches a PTY in 11–13 ms (under 4 ms for GNU) and on a 2,000-file tree in 52 ms (1.4 ms for GNU). These barriers are not a visible defect at that size and removing them is the riskiest change on the list; 0.4.2 must measure slow regexes, cold disks and multi-GiB inputs before touching them.

**`-I` on non-regular input.** The buffered path cannot stream and has unbounded memory, on stdin and on FIFO or device operands alike: `zgr --line-buffered -I x` on a slow producer prints nothing before EOF, and `yes needle | zgr -I needle | head -1` never terminates. Replace it with a streaming path. GNU decides per read and never looks ahead: text already printed stays, the search then stops with status 1 and prints a count of 0 under `-c`. zgr stops reading at that point whereas GNU drains its input; the bytes are identical but a producer sees the pipe close earlier.

**Binary boundaries.** GNU 3.11 classifies input per 96 KiB buffer; zgr 0.4.0 used 256 KiB, which changes stdout for any NUL beyond 96 KiB (NUL at 100 KiB: 0 lines against 14,043). Use 96 KiB for regular files and for read boundaries on streams. On pipes the result still depends on how the producer's writes are timed, for GNU as well. A match after a late NUL must report `binary file matches` instead of silently stopping.

**stdout/stderr ordering.** GNU interleaves results and diagnostics on every kind of stdout (terminal, file and pipe), because `error()` flushes stdout first. zgr must flush stdout before every diagnostic, whatever stdout is, and flush stderr after it, so that no diagnostic is lost when SIGPIPE ends the process. A failing stderr must not stop the search.

**SIGPIPE.** On early consumer closure, zgr 0.4.0 prints `zgr: write error: Broken pipe` and exits 2, whereas GNU is terminated by SIGPIPE silently (shell status 141). Zig 0.16's `std.Io.Threaded` replaces the SIGPIPE disposition (`std/Io/Threaded.zig:1661`). Reinstall the inherited disposition from `Threaded.old_sig_pipe` at startup. This relies on a Zig 0.16 internal and must be rechecked on compiler upgrades. A parent that ignores SIGPIPE must still get the diagnostic and status 2.

Any change to automatic TTY timing must be documented as observable 0.4.1 behavior, with explicit throughput measurements (§5). The behavioral gate lives in `tests/streaming.py`, run for both engines.

## 3. 0.4.2 — optimize the measured hot path in small steps

**Declare targets before implementing.** After profiling, and before writing code, this document must state for each retained target: the workload, the metric (wall or CPU), the expected gain and the timebox. Adding or changing a target after measuring is not allowed. None of these has been fixed yet. Starting points, from the 0.4.0 baseline medians (7 unpaired runs; "within noise" means the bootstrap 95% interval of the difference includes zero):

| Candidate target | Evidence | Note |
|---|---|---|
| `zgrc` dense plain | 104.6 ms vs GNU 101.3 ms | Within noise (−2.3 to +17.7%): not established as slower |
| CPU efficiency of dense output | zgr CPU (user + sys median) 132 ms vs GNU 84 ms (all plain), 166 vs 101 (dense plain) | Becomes wall time on loaded or small-core machines |
| Binary NUL prescan | CPU 132 ms vs 96 ms with `-a`; wall 71.5 vs 66.1 ms | Target CPU: the wall delta is within noise (−4 to +16.3%) and capped below the 10% gate. Confirm `-a` changes nothing else on this path |
| Colored output | 145.2 ms | Includes re-matching for highlighting |
| Numbered output | 93.8 ms vs 71.5 ms plain | Formatting cost |
| Plain full-line literal spans | 71.5 ms; historical `cat` ≈ 47 ms | Closest to its bound; least headroom |

Apply and measure each change independently; retain a no-optimization comparison path in the benchmark experiment.

**Bounded spans.** Start with plain full-line literal output on memory-mapped input. Merge adjacent records only when each is actually eligible for emission, after binary/UTF-8 suppression decisions. Keep a constant-size current-span descriptor and flush by the existing 256 KiB output budget; a run covering the whole file must not delay output until EOF. Longer records may be transferred in pieces without changing bytes or record-level flush semantics. Initially exclude prefixes, colors, context, `-o`, inversion, maximum-count mode and explicit line buffering. Preserve original delimiters and synthesize the final missing terminator exactly as before. Keep skipped records out of spans.

State explicitly whether spans are copied into the output buffer or passed directly to `writev` from the mapping (`std.Io.Writer` forwards large slices to `drain` without copying). The zero-copy option avoids a memcpy but changes the failure mode when the input is truncated during the scan (log rotation): `writev` returns `EFAULT` instead of the process receiving `SIGBUS`. Test truncation either way.

**Discarded discovery work.** Measure the 65,536-record per-chunk cap before changing it. Emission-only batching does not remove allocations and rescans already performed. Compare bounded ordered chunks, early density fallback and span-based descriptions only where their eligibility is proven. Retain a change only when it passes the acceptance matrix; simply raising the cap is not an accepted solution. Fallback after partial emission must resume from an exact cursor, or be disallowed; never replay output already emitted.

**Specialized output.** Profile runtime option checks and inspect optimized code before adding Zig `comptime` variants. Start with plain and common numbered output only if measurements justify them. Preserve the shared complex formatter; avoid a flag-combination explosion. Measure executable size and instruction/cache effects where available. Colored output performs matching for highlighting as well as formatting and needs its own cost breakdown.

For these literal paths, total work still includes O(input bytes + output bytes). Coalescing can reduce per-record overhead from the number of emitted records to the number of emitted spans, but does not eliminate required scanning or output.

## 4. Optional writer-pipeline experiment (0.4.2)

This is not a mandatory deliverable. Attempt it only after profiling shows a remaining opportunity to overlap useful parsing with output, and after accounting for the existing recursive queues and capture buffers. Do not infer a gain merely because the sink blocks.

- Limit the initial experiment to eligible bulk output. Use one owner of the final writer and a fixed pool of four 256 KiB blocks. The 1 MiB payload budget includes queued, producer-held and writer-held blocks. Report total additional memory, including synchronization and thread stack, and cumulative memory with existing capture buffers.
- Preserve output order and block ownership. Copied data must remain valid until drained; descriptors referencing mapped input require the mapping to outlive all consumers. Handle records larger than a block without unbounded queue growth.
- Transfer any buffered output in order before changing writer ownership. Propagate short-write handling and the original write error; return success only after the last write/flush and worker completion.
- Define normal completion, producer failure, consumer failure, cancellation and teardown. Wake blocked queue operations and distinguish queue cancellation from a writer blocked in the OS. Specify how supported cancellation reaches that write; `join` alone is not a cancellation mechanism. Never replay already emitted data or silently turn an external write failure into an internal capture-buffer fallback.
- Keep synchronous behavior for interactive and explicit line-buffered output. Preserve `-m`/stdin positioning and early termination by excluding unsupported combinations before emission.

The experiment must satisfy all correctness and resource gates below. If it cannot demonstrate a gain without synchronization complexity or regressions, omit it.

## 5. Qualification and release gates

**Statistics.** The 0.4.0 samples show a 7.8–25% min–max spread over 7 runs (158.6% for one `zgrc -a` case). Medians of 2×9 runs cannot reliably detect a 5% regression, especially on ~10 ms workloads where 5% is ≈0.5 ms of process-launch jitter.

- Run baseline and candidate as interleaved randomized pairs in the same session, after warm-up. Use enough runs per workload to bound the confidence interval below the decision threshold (in practice many more than nine for sub-20 ms cases), in at least two independent batches.
- Decide on a confidence interval of the paired difference (bootstrap) or a paired rank test (Wilcoxon signed-rank), not on median comparison alone. Report hardware instruction counts (`perf stat`) as a lower-noise secondary metric where available.
- Save individual samples, exact commands, corpus/output hashes, statuses, stderr and environment. Analyze each workload separately; repeat noisy cases instead of accepting a favorable aggregate.

**CPU topology.** The i9-13900KF mixes performance and efficiency cores, and baseline runs used unrestricted affinity, which can produce bimodal timings. Record the CPU governor, and run every comparison both unrestricted and restricted to a small core set (`taskset`, after checking with `lscpu -e` which logical CPUs are hyperthread siblings), because chunking and parallel thresholds are effectively tuned for 32 threads. Results from a single machine must be reported as such.

**Acceptance criteria.**

- 0.4.1: no new correctness failures; the behavioral probes of §2 pass; no repeatable throughput regression above 5% (as defined by the statistics above) when stdout is not a terminal. On a terminal with non-regular input, the flush rule is the fix itself and stays on by default; the bar is to remain no slower than GNU grep.
- 0.4.2: at least 10% improvement in the **pre-declared** target workloads (§3), confirmed by the confidence interval in both batches. Reject repeatable regressions above 5% in non-target workloads, including sparse searches. Do not hide CPU or memory growth behind wall-time gains.
- For a writer pipeline, require gains on at least two distinct representative dense workloads, including one with output formatting, in both batches; duplicated all-match cases do not count as distinct coverage. Require no new correctness failures, bounded resource use and cancellation completion.

**Measurements.** Wall time, user/system CPU, first complete result, subsequent-result latency, peak RSS and additional buffering. RSS includes mapped input (154 MiB vs 18 MiB for GNU in the baseline) and is not a heap-only measurement. Report binary-size changes for specialization. Separate cached file writes, pipe throughput and PTY transport from durable disk throughput and actual terminal rendering. Include at least one cold-cache case.

**Workload matrix.** Cover 0%, sparse, alternating, clustered and 100% matches; short and very long records; realistic source trees; plain, numbered, colored, context and only-matching output. Include sizes just below/above 64 MiB, counts around the actual per-chunk metadata cap, and recursive trees below/above the 512-file pipeline threshold. Include late matches and uneven file/chunk sizes.

**Sinks and edge cases.**

- Regular-file sinks, fast and throttled pipes, PTYs, and a slow stdin/FIFO producer that stays open, with and without `-I`, `-z`, context and `-c`.
- An infinite producer with early consumer closure (`yes … | zgr … | head -1`, including `-I`) must terminate with the chosen SIGPIPE behavior and bounded memory.
- stdout/stderr ordering on a TTY with a missing file between two matching files.
- Stalled reader plus cancellation, partial/final write errors, stdout closed (`>&-`), `/dev/full`.
- Input identical to output (`zgr x f >> f`, `stdout_identity`), input truncated or growing during the scan.
- Missing final terminators, NUL records, invalid UTF-8, binary modes, chunk boundaries, maximum-count behavior and seekable-stdin position.
- Verify exact bytes and ordering without sorting away differences. Use fixed timeouts to detect hangs. Apply C and available UTF-8 locales where relevant.

**Build and tests.** Build both engines with Zig 0.16.0 ReleaseFast. Run `zig build test`, `zig build test-zpcre2`, and explicitly run CLI differential and stress scripts against both `zgr` and `zgrc` (the standard test/stress targets primarily qualify `zgrc`). Record the experimental `test-zpcre2-gnu` failures individually before and after; `tests/regex-semantics.sh` and `tests/locale-semantics.sh` stop at their first failure, so a complete inventory first needs them to continue past it. Use ReleaseSafe for new ownership/concurrency tests if the optional pipeline is attempted.

**Versioning.** Update `src/main.zig` and `build.zig.zon` together (0.4.1, then 0.4.2) only when delivering the retained changes. Verify both `--version` outputs and publish measured limits in release notes. No installation, tag creation or remote publication is authorized by this plan.

## Evidence

- [Adversarial review and corrections](output-optimization-review-2026-11-01.md)
- [Rebuilt v0.4.0 baseline, raw samples, scripts and provenance](baseline-output-v0.4.0-2026-11-01/README.md)
- [Historical 0.3.x observations](baseline-output-2026-11-01/README.md)

Preserve unrelated `.cursor/` files.
