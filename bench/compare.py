#!/usr/bin/env python3
"""Compare LLVM zgr/zgrc with installed ripgrep and GNU grep on generated ASCII."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import tempfile
import time


# Same search semantics on the generated ASCII corpus. rg needs --include-zero
# to print the zero count for the miss. Binary handling must match for all tools.
CASES = [
    ("literal miss", ["-F", "-c", "not-present-anywhere"], ["--include-zero"]),
    ("rare literal", ["-F", "-c", "rare-needle"], []),
    ("case insensitive", ["-F", "-i", "-c", "RARE-NEEDLE"], []),
    ("word literal", ["-F", "-w", "-c", "rare-needle"], []),
    ("dense literal", ["-F", "-c", "INFO"], []),
    ("dense regex", ["-E", "-c", "status=(200|500)"], []),
    ("regex suffix", ["-E", "-c", "[a-z]+-needle"], []),
    ("alternation", ["-E", "-c", "rare-needle|status=500|route=/api/item/42|latency_us=999"], []),
    ("regex no literal", ["-E", "-c", "[[:alnum:]_]{4}[[:space:]]+[[:alnum:]_]{7}"], []),
    ("sparse numbered", ["-F", "-n", "rare-needle"], []),
    ("absent output", ["-F", "-n", "not-present-anywhere"], []),
    ("sparse plain", ["-F", "rare-needle"], []),
    ("sparse word numbered", ["-F", "-w", "-n", "rare-needle"], []),
    ("sparse insensitive numbered", ["-F", "-i", "-n", "RARE-NEEDLE"], []),
    ("dense numbered", ["-F", "-n", "INFO"], []),
    ("dense plain", ["-F", "INFO"], []),
    ("regex output", ["-E", "-n", "route=/api/item/[[:digit:]]+[[:space:]]+status=500"], []),
]


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def sha256(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def executable(value):
    found = shutil.which(value)
    if found is None:
        raise ValueError(f"executable not found: {value}")
    return str(Path(found).resolve())


def command_output(command, cwd=None):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def measure(command, sink, env):
    with sink.open("wb") as output:
        start = time.perf_counter_ns()
        process = subprocess.run(command, stdout=output, stderr=subprocess.PIPE,
                                 env=env, timeout=120)
        elapsed = (time.perf_counter_ns() - start) / 1_000_000
    if process.returncode not in (0, 1) or process.stderr:
        raise RuntimeError(f"command failed: {command!r}; status={process.returncode}; "
                           f"stderr={process.stderr.decode(errors='replace')}")
    # Hashing and correctness checks are outside the timed interval.
    return elapsed, (process.returncode, sink.stat().st_size, sha256(sink))


def compare(args):
    repo = Path(__file__).resolve().parent.parent
    corpus = args.corpus.resolve(strict=True)
    if args.cpu is not None:
        os.sched_setaffinity(0, {args.cpu})
    tools = {name: executable(value) for name, value in
             (("zgr", args.zgr), ("zgrc", args.zgrc), ("ripgrep", args.rg), ("grep", args.grep))}
    subprocess.run(["sh", str(repo / "bench/check-build.sh"), tools["zgr"], tools["zgrc"]],
                   check=True)
    env = dict(os.environ, LC_ALL=args.locale, GREP_COLORS="")
    env.pop("RIPGREP_CONFIG_PATH", None)
    metadata = {}
    for name, binary in tools.items():
        metadata[name] = {"path": binary, "sha256": sha256(binary),
                          "version": command_output([binary, "--version"])}
    if "GNU grep" not in metadata["grep"]["version"]:
        raise ValueError("--grep must be GNU grep (the correctness reference)")
    if not metadata["ripgrep"]["version"].startswith("ripgrep "):
        raise ValueError("--rg must be ripgrep")
    result = {
        "status": "incomplete", "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source_commit": command_output(["git", "rev-parse", "HEAD"], cwd=repo),
        "source_changes": command_output(["git", "status", "--short", "--untracked-files=no"], cwd=repo),
        "source_inputs_sha256": {str(p.relative_to(repo)): sha256(p) for p in sorted(
            [repo / "build.zig", repo / "build.zig.zon"] +
            [p for directory in ("src", "include") for p in (repo / directory).rglob("*") if p.is_file()])},
        "runner_sha256": sha256(Path(__file__)),
        "platform": platform.platform(), "affinity": sorted(os.sched_getaffinity(0)),
        "cpu_model": next((line.split(":", 1)[1].strip() for line in
                           Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unknown"),
        "corpus": {"path": str(corpus), "bytes": corpus.stat().st_size, "sha256": sha256(corpus)},
        "tools": metadata, "locale": args.locale, "repeats": args.repeats, "warmups": 2,
        "seed": args.seed, "clock": "perf_counter_ns", "cache": "warm",
        "input_mode": args.input_mode,
        "sink": "regular temporary file, no fsync", "includes_process_startup": True,
        "exploratory_override": os.environ.get("BENCH_ALLOW_UNOPTIMIZED") == "1",
        "checks": 0, "cases": [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Preserve previous evidence; choose a new output filename for a new run.
    with args.output.open("x") as output:
        json.dump(result, output, indent=2)
    rng = random.Random(args.seed)
    try:
        with tempfile.TemporaryDirectory(prefix="zgrep-compare-") as temporary:
            sink = Path(temporary) / "output"
            for name, flags, rg_extra in CASES:
                input_flags = ["-a"] if args.input_mode == "text" else []
                commands = {tool: [binary, *input_flags, *flags, str(corpus)] for tool, binary in tools.items()}
                commands["ripgrep"] = [tools["ripgrep"], "--no-config", "--color=never", *input_flags,
                                       *rg_extra, *(flag for flag in flags if flag != "-E"), str(corpus)]
                _, expected = measure(commands["grep"], sink, env)
                samples = {tool: [] for tool in tools}
                orders = []

                def checked(tool):
                    elapsed, actual = measure(commands[tool], sink, env)
                    if actual != expected:
                        raise RuntimeError(f"GNU correctness mismatch: {name} / {tool}; "
                                           f"expected={expected!r}, actual={actual!r}")
                    result["checks"] += 1
                    return elapsed

                for tool in tools:
                    for _ in range(result["warmups"]):
                        checked(tool)
                for _ in range(args.repeats):
                    order = list(tools)
                    rng.shuffle(order)
                    orders.append(order)
                    for tool in order:
                        samples[tool].append(checked(tool))
                row = {"name": name, "commands": commands,
                       "expected": {"status": expected[0], "bytes": expected[1], "sha256": expected[2]},
                       "orders": orders, "samples_ms": samples,
                       "median_ms": {tool: statistics.median(times) for tool, times in samples.items()}}
                result["cases"].append(row)
                args.output.write_text(json.dumps(result, indent=2) + "\n")
                print(name + ": " + ", ".join(f"{tool}={ms:.3f} ms" for tool, ms in row["median_ms"].items()),
                      flush=True)
        # Resample paired rounds, separately from the measurements. Ratios > 1
        # mean the Zig executable was faster than the reference tool.
        for row in result["cases"]:
            row["speedup"] = {}
            for tool in ("zgr", "zgrc"):
                for reference in ("ripgrep", "grep"):
                    ratios = [other / own for other, own in zip(row["samples_ms"][reference], row["samples_ms"][tool])]
                    bootstrap_rng = random.Random(args.seed)
                    bootstrap = sorted(statistics.median(bootstrap_rng.choices(ratios, k=len(ratios)))
                                       for _ in range(2000))
                    row["speedup"][tool + "_vs_" + reference] = {
                        "median_paired_ratio": statistics.median(ratios),
                        "bootstrap_95_percent": [bootstrap[50], bootstrap[1949]],
                    }
        result["status"] = "passed"
    except Exception as error:
        result["status"] = "failed"
        result["error"] = str(error)
        raise
    finally:
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"passed: {len(result['cases'])} cases, {result['checks']} checked runs; {args.output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True, help="corpus from bench/generate.sh")
    parser.add_argument("--output", type=Path, required=True, help="new JSON result file (never overwritten)")
    parser.add_argument("--zgr", default=os.environ.get("ZGR", "./zig-out/bin/zgr"))
    parser.add_argument("--zgrc", default=os.environ.get("ZGRC", "./zig-out/bin/zgrc"))
    parser.add_argument("--rg", default="rg")
    parser.add_argument("--grep", default="grep")
    parser.add_argument("--repeats", type=positive, default=15)
    parser.add_argument("--seed", type=int, default=711)
    parser.add_argument("--cpu", type=int, help="pin all processes to one logical CPU")
    parser.add_argument("--locale", default="C")
    parser.add_argument("--input-mode", choices=("auto", "text"), default="auto",
                        help="binary detection for all tools (auto), or -a for all tools (text)")
    compare(parser.parse_args())
