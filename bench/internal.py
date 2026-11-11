#!/usr/bin/env python3
"""Time real Zig kernels on a resident generated ASCII corpus (Linux)."""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

CASES = [
    "nul prescan", "ascii prescan", "newline count", "literal occurrences",
    "literal line count", "literal scan count", "sparse plain formatting",
    "sparse numbered formatting", "absent line count", "word line count",
    "case-insensitive line count", "dense line count",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--baseline-library", type=Path)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="new JSON file")
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--repeats", type=int, default=15)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    if args.output.exists():
        parser.error("--output must not exist")
    if args.cpu is not None:
        os.sched_setaffinity(0, {args.cpu})
    data = args.corpus.read_bytes()
    if not data.isascii() or b"\0" in data or not data.endswith(b"\n"):
        parser.error("use the ASCII newline corpus from bench/generate.sh")
    buffer = ctypes.create_string_buffer(data)

    def grep(*flags):
        run = subprocess.run(["grep", "-a", *flags, str(args.corpus.resolve())],
                             env=dict(os.environ, LC_ALL="C"), capture_output=True, check=False)
        if run.returncode not in (0, 1) or run.stderr:
            raise RuntimeError(run.stderr.decode(errors="replace"))
        return run.stdout

    rare = int(grep("-F", "-c", "rare-needle"))
    expected = [
        len(data), 1, data.count(b"\n"), data.count(b"rare-needle"), rare, rare,
        len(grep("-F", "rare-needle")), len(grep("-F", "-n", "rare-needle")),
        int(grep("-F", "-c", "not-present-anywhere")),
        int(grep("-F", "-w", "-c", "rare-needle")),
        int(grep("-F", "-i", "-c", "RARE-NEEDLE")),
        int(grep("-F", "-c", "INFO")),
    ]
    paths = {"candidate": args.library}
    if args.baseline_library:
        paths["baseline"] = args.baseline_library
    functions, metadata = {}, {}
    for label, path in paths.items():
        library = ctypes.CDLL(str(path.resolve(strict=True)))
        function = library.measure_kernel
        function.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint]
        function.restype = ctypes.c_size_t
        functions[label] = function
        metadata[label] = {"path": str(path.resolve()),
                           "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    result = {
        "status": "incomplete", "libraries": metadata,
        "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "corpus_sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
        "affinity": sorted(os.sched_getaffinity(0)), "repeats": args.repeats,
        "warmups": 2, "seed": 711, "checks": 0,
        "method": "resident buffer, real Zig functions, FFI overhead included; "
                  "no startup or disk I/O; formatting sink discards bytes; "
                  "kernel results checked against Python counts or GNU grep",
        "cases": [{"name": name, "expected": value,
                   "samples_ms": {label: [] for label in paths}} for name, value in zip(CASES, expected)],
    }
    with args.output.open("x") as output:
        json.dump(result, output, indent=2)

    def checked(mode, label):
        start = time.perf_counter_ns()
        actual = functions[label](buffer, len(data), mode)
        elapsed = (time.perf_counter_ns() - start) / 1_000_000
        if actual != expected[mode]:
            raise RuntimeError(f"{CASES[mode]} / {label}: {actual} != {expected[mode]}")
        result["checks"] += 1
        return elapsed

    rng = random.Random(result["seed"])
    try:
        for mode in range(len(CASES)):
            for label in paths:
                for _ in range(result["warmups"]):
                    checked(mode, label)
        for _ in range(args.repeats):
            modes = list(range(len(CASES)))
            rng.shuffle(modes)
            for mode in modes:
                labels = list(paths)
                rng.shuffle(labels)
                for label in labels:
                    result["cases"][mode]["samples_ms"][label].append(checked(mode, label))
        for row in result["cases"]:
            row["median_ms"] = {label: statistics.median(samples)
                                for label, samples in row["samples_ms"].items()}
            print(row["name"], row["median_ms"], flush=True)
        result["status"] = "passed"
    except Exception as error:
        result["status"] = "failed"
        result["error"] = str(error)
        raise
    finally:
        args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
