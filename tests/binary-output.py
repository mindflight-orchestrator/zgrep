#!/usr/bin/env python3
"""Compare literal output, diagnostics and status at GNU binary-block boundaries."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def fixtures():
    block = 96 * 1024
    for size in [0, 1, block - 1, block, block + 1, 3 * block + 17]:
        data = (b"x\n" * (size // 2 + 1))[:size]
        yield f"text-{size}", data
        if size >= 7:
            yield f"tail-{size}", data[:-7] + b"needle\n"
    for end in [block - 1, block, block + 1, 2 * block - 1, 2 * block, 2 * block + 1]:
        for nul in [0, 31, block - 1, block, block + 1, 2 * block - 1, 2 * block, 2 * block + 1, 3 * block - 1]:
            data = bytearray(b"x\n" * (3 * block // 2))
            data[:7] = b"needle\n"
            data[end - 7:end + 1] = b"\nneedle\n"
            data[-7:] = b"needle\n"
            data[nul] = 0
            yield f"end-{end}-nul-{nul}", bytes(data)
    for nul in [block - 1, block, block + 1, 2 * block + 1]:
        for first_match in [True, False]:
            data = bytearray(b"x" * (3 * block + 17))
            if first_match:
                data[:7] = b"needle "
            else:
                data[-7:] = b" needle"
            data[nul] = 0
            yield f"long-{nul}-{first_match}", bytes(data)
    padding = b"x\n" * block
    for name, prefix in [
        ("valid-utf8", "café needle\n".encode()),
        ("invalid-selected", b"needle\xff\n"),
        ("invalid-unselected", b"other\xff\n"),
        ("rejected-word", b"needlex\n"),
    ]:
        for tail in [b"needle\n", b"needle\0\n", b"other\0\n"]:
            yield f"{name}-{tail.hex()}", prefix + padding + tail
    yield "late-nul-no-later-match", b"needle\n" + padding + b"other\0\n"
    yield "no-match", b"other\0\n" + padding
    yield "unterminated", padding + b"needle"
    yield "nul-records", padding.replace(b"\n", b"\0") + b"needle\0tail"


def run(binary, flags, path, locale, redirected=False):
    env = dict(os.environ, LC_ALL=locale, GREP_COLORS="")
    with path.open("rb") as source:
        command = [str(binary), *flags, "needle"]
        if not redirected:
            command.append(str(path))
        result = subprocess.run(command, stdin=source if redirected else subprocess.DEVNULL,
                                capture_output=True, env=env, timeout=10)
    stderr = result.stderr.replace((str(binary) + ":").encode(), b"PROG:")
    stderr = stderr.replace((Path(binary).name + ":").encode(), b"PROG:")
    return result.returncode, result.stdout, stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    candidate = args.candidate.resolve(strict=True)
    grep = Path(shutil.which("grep"))
    cases = [
        ["-F"], ["-F", "-n", "-b"], ["-F", "-w", "-n"], ["-F", "-i", "-n"],
        ["-a", "-F", "-n"], ["-I", "-F", "-n"], ["-z", "-F", "-n"],
    ]
    checks = 0
    with tempfile.TemporaryDirectory(prefix="zgrep-binary-tests-") as directory:
        path = Path(directory) / "input"
        for name, data in fixtures():
            path.write_bytes(data)
            for locale in ["C", "C.UTF-8"]:
                for flags in cases:
                    expected = run(grep, flags, path, locale)
                    actual = run(candidate, flags, path, locale)
                    if actual != expected:
                        raise AssertionError((name, locale, flags,
                                              [(len(x) if isinstance(x, bytes) else x) for x in expected],
                                              [(len(x) if isinstance(x, bytes) else x) for x in actual]))
                    checks += 1
            # Redirected regular stdin follows its existing streaming path.
            flags = ["-F", "-n", "-b"]
            assert run(candidate, flags, path, "C", True) == run(grep, flags, path, "C", True), name
            checks += 1
    print(f"binary output: {checks} GNU comparisons passed", flush=True)


if __name__ == "__main__":
    main()
