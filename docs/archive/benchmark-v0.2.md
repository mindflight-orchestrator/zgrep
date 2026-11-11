# zgrep v0.2 — small comparative benchmark

[English](benchmark-v0.2.md) | [Français](benchmark-v0.2.fr.md)

> This benchmark predates the executable rename to `zgr`. The results remain a
> historical record; the replay command below uses the current name.

Measurement captured on 2026-08-25 at 10:59 CEST on Linux 6.8.0 x86_64, with
an Intel Core i9-13900KF (32 logical CPUs), Zig 0.16.0, GNU grep 3.11 and
ripgrep 15.2.0. The corpus was `/usr/src/linux-headers-6.8.0-137`: 16,280 files
and 72,622,832 bytes.

## Compared artifacts

- zgrep v0.2, implementation `664e71a`:
  `a8b945c0aa73fce524f594a97da2e5ff83cbf5dc6459192b5ec422e17f31ee66`;
- baseline before the exact measurement, commit `7179e03`:
  `272c95ba4bbed93a02524c523b93dfc5b7f1d3cccc5d62f22c78f33a33a390cf`;
- ripgrep 15.2.0, revision `e89fff89ac`.

## Method

- warm cache, `LC_ALL=C`, `taskset -c 0-15`;
- 9 interleaved batches of 5 runs per tool and mode;
- median reported in milliseconds per run;
- stdout redirected to a regular file, never `/dev/null`;
- before each measurement, sorted zgrep and ripgrep output was compared with
  GNU grep; zgrep's exact GNU traversal order was covered separately by the
  recursive stress suite.

The three workload families were dense literal `CONFIG_`, sparse literal
`PM_RESUME`, and a regex without a literal:
`[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}`.
The benchmark ran recursive list (`-r -l`) and regular output (`-r -n`) modes.

## Medians

| Workload | Mode | zgrep v0.2 | baseline `7179e03` | ripgrep |
|---|---|---:|---:|---:|
| dense literal | list | 15.718 | 15.741 | 18.036 |
| dense literal | output | 19.056 | 22.773 | 20.366 |
| sparse literal | list | 15.565 | 15.443 | 15.419 |
| sparse literal | output | 15.501 | 15.431 | 15.297 |
| regex without a literal | list | 19.975 | 19.617 | 21.129 |
| regex without a literal | output | 20.166 | 20.225 | 21.421 |

On the primary target, dense literal output, v0.2 improved on the baseline by
16.3% and led ripgrep by 6.4% while preserving GNU traversal order. The sparse
and no-literal controls remained close to the baseline; this small sample does
not support universal claims across machines, file systems or cold caches.

To replay the current public profile without the A/B baseline:

```sh
BENCH_PROFILE=ripgrep-linux-default BENCH_BATCHES=9 BENCH_CPUSET=0-15 \
  BENCH_LOCALE=C ZGR=./zig-out/bin/zgr \
  bench/run-tree.sh /usr/src/linux-headers-6.8.0-137 PM_RESUME 5
```
