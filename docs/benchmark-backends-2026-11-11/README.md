# Evidence — Zig backends and LLVM versus Rust/C

Collected locally on 11 November 2026. Read the
[report](../benchmark-backends.md) or [French report](../benchmark-backends.fr.md)
for conditions, conclusions and limits.

| Files | Purpose |
|---|---|
| `metadata.json` | Original baseline commit, dependency commit, compiler versions and host |
| `build-configuration.patch` | Isolated experiment's backend selector and local dependency path |
| `zig-017-compatibility.patch` | Isolated Zig 0.17 syntax/API changes, including zpcre2 |
| `builds.py`, `builds-017.py`, `*-build.log` | Original build attempts and final compiler commands |
| `benchmark.py`, `benchmark-results.json` | Four-backend runtime comparison on 100,000 lines |
| `compile-benchmark.py`, `compile-results.json` | Three controlled zgr compilations per variant |
| `recompile-validation.json` | Correctness and identity checks of the twelve recompiles |
| `kernels/` | Isolated code-generation evidence: source, driver, assembly, samples |
| `comparison-llvm-rust-c.json` | Current LLVM candidate versus installed ripgrep and GNU grep, 1,000,000 lines |
| `llvm-candidate-build.log`, `comparison-llvm-rust-c.log` | Candidate compilation commands and comparison output |
| `validation.log`, `profile-validation.json` | Unit/differential checks and build-profile rejection checks |
| `smoke-utf8.json`, `smoke-utf8.log`, `shell-smoke.log` | Smaller local checks of the CI comparison and existing launcher |

The original experiment's raw files are preserved unchanged. The scripts
`builds.py` and `builds-017.py` are historical orchestration records, including
initial failures and the corrected 0.17 invocation. They contain temporary
absolute paths and are not supported drop-in build commands. Reconstruct the
recorded source/dependency commits in isolated copies, apply the recorded
patches, and adapt those paths before repeating that experiment. The final
commands are recorded in the build logs and compilation JSON. The kernel
script also writes generated artifacts beside itself; copy it to a scratch
directory before rerunning it. It assumes `zig-0.16` and logical CPU 2.

For the maintained comparison, use `../../bench/compare.py` and the reproduction
commands in the report. The candidate JSON records a baseline commit **plus
local changes**, per-source SHA-256 values, runner hash, executable hashes and
actual version output. The baseline commit alone does not contain those changes.

The temporary build paths describe where the experiment ran, not durable binary
downloads. Executables, caches and large generated corpora are not archived.
Both corpora can be regenerated using `bench/generate.sh` from the baseline;
their identities are:

| Profile | Lines | Bytes | SHA-256 |
|---|---:|---:|---|
| Backend comparison | 100,000 | 9,378,980 | `1dcecb7edb774134592782760c18b6d8f09fc91b2cc9f6463bfd85cc77b75c45` |
| LLVM/Rust/C comparison | 1,000,000 | 93,789,827 | `da9fd9c2df9698ffcbeac1693c0fdf72b9357ff50fc0234c4e1d1f3f13797a3b` |

The two experiments differ in corpus size and candidate instrumentation; do
not combine their absolute timings into a single ranking. Tests and metadata
are local evidence, not proof of a completed GitHub release.
