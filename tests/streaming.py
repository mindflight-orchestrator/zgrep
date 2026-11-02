#!/usr/bin/env python3
"""Differential checks for output timing, ordering and early termination.

Each case runs GNU grep and the candidate against the same input. Slow-input
cases compare what became visible after every separately delivered chunk, so a
result that only appears at EOF fails even when the final bytes are identical.
"""
import os
import pty
import resource
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import tty

CANDIDATE = os.path.realpath(sys.argv[1])
PROGRAM = os.path.basename(CANDIDATE)
GNU = shutil.which("grep")
ENV = dict(os.environ, LC_ALL="C")
ENV.pop("GREP_COLORS", None)
WINDOW = 0.25
failures = []


def normalize_stderr(data, binary):
    prefix = os.path.basename(binary).encode()
    data = data.replace(binary.encode() + b":", prefix + b":")
    return data.replace(prefix + b":", b"PROG:")


def run_slow(binary, args, chunks, mode):
    read_end, write_end = os.pipe()
    if mode == "pty":
        master, slave = pty.openpty()
        attrs = tty.tcgetattr(slave)
        attrs[1] &= ~1  # OPOST: keep the exact output bytes.
        tty.tcsetattr(slave, tty.TCSANOW, attrs)
    else:
        master, slave = os.pipe()
    process = subprocess.Popen(
        [binary] + args,
        stdin=read_end,
        stdout=slave,
        stderr=subprocess.PIPE,
        env=ENV,
        preexec_fn=lambda: signal.signal(signal.SIGPIPE, signal.SIG_IGN),
    )
    os.close(read_end)
    os.close(slave)
    os.set_blocking(master, False)

    def drain(duration):
        deadline = time.monotonic() + duration
        received = b""
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                continue
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            received += data
        return received

    stages = []
    old_handler = signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    for chunk in chunks:
        try:
            os.write(write_end, chunk)
        except BrokenPipeError:
            pass
        stages.append(drain(WINDOW))
    signal.signal(signal.SIGPIPE, old_handler)
    os.close(write_end)
    tail = drain(0.2)
    try:
        status = process.wait(5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        status = "timeout"
    errors = process.stderr.read()
    process.stderr.close()
    tail += drain(0.01)
    os.close(master)
    return stages, tail, status, normalize_stderr(errors, binary)


def check_slow(name, args, chunks, modes=("pty", "pipe"), expected=None):
    for mode in modes:
        want = expected or run_slow(GNU, args, chunks, mode)
        got = run_slow(CANDIDATE, args, chunks, mode)
        if got != want:
            got = run_slow(CANDIDATE, args, chunks, mode)  # one retry for scheduling noise
        if got != want:
            failures.append(f"{name} [{mode}]\n  gnu: {want}\n  got: {got}")


def run_shell(binary, script, cwd):
    # The inner timeout also reaps pipeline members; a hung search must not keep
    # consuming an infinite producer after this check has failed.
    result = subprocess.run(
        ["timeout", "-k", "1", "10", "bash", "-c", script, "bash", binary],
        cwd=cwd,
        env=ENV,
        capture_output=True,
        preexec_fn=lambda: resource.setrlimit(resource.RLIMIT_AS, (4 << 30, 4 << 30)),
    )
    return (
        result.returncode,
        normalize_stderr(result.stdout, binary),
        normalize_stderr(result.stderr, binary),
    )


def check_shell(name, script, cwd):
    want = run_shell(GNU, script, cwd)
    got = run_shell(CANDIDATE, script, cwd)
    if got != want:
        failures.append(f"{name}\n  gnu: {want}\n  got: {got}")


A = b"needle a\n"
B = b"needle b\n"
X = b"other\n"
TERMINAL_ONLY = ("pty",)

check_slow("default", ["needle"], [A, B])
check_slow("regex", ["-E", "need(le)"], [A, B])
check_slow("line numbers", ["-n", "needle"], [A, B], TERMINAL_ONLY)
check_slow("only matching", ["-o", "needle"], [A, B], TERMINAL_ONLY)
check_slow("color", ["--color=always", "needle"], [A, B], TERMINAL_ONLY)
check_slow("after context", ["-A1", "needle"], [A, X, X, B], TERMINAL_ONLY)
check_slow("before context", ["-B1", "needle"], [X, A, X], TERMINAL_ONLY)
check_slow("partial record", ["needle"], [b"need", b"le a\n"], TERMINAL_ONLY)
check_slow("line buffered", ["--line-buffered", "needle"], [A, B])
check_slow("line buffered context", ["--line-buffered", "-A1", "needle"], [A, X, X, B])
check_slow("NUL records line buffered", ["-z", "--line-buffered", "needle"], [b"needle a\0", b"needle b\0"])
check_slow("max count", ["-m1", "needle"], [A, B])
check_slow("count", ["-c", "needle"], [A, B])
check_slow("files with matches", ["-l", "needle"], [A, B])
check_slow("quiet", ["-q", "needle"], [A, B])

check_slow("-I line buffered", ["-I", "--line-buffered", "needle"], [A, B])
check_slow("-I terminal", ["-I", "needle"], [A, B], TERMINAL_ONLY)
check_slow("-I regex", ["-I", "--line-buffered", "-E", "need(le)"], [A, B])
check_slow("-I context", ["-I", "--line-buffered", "-A1", "needle"], [A, X, B])
check_slow("-I first NUL", ["-I", "--line-buffered", "needle"], [b"x\0\n", A])
check_slow("-I late NUL", ["-I", "--line-buffered", "needle"], [A, b"x\0needle\n", B])
# zgr stops reading at the NUL while GNU drains its input, so a count on a pipe
# may arrive earlier than GNU's; the terminal comparison still covers its bytes.
check_slow("-I late NUL count", ["-I", "-c", "needle"], [A, b"x\0needle\n", B], TERMINAL_ONLY)
check_slow("-I late NUL quiet", ["-I", "-q", "absent"], [A, b"x\0needle\n", B])
check_slow("-I late NUL without match", ["-I", "-L", "absent"], [A, b"x\0needle\n", B])

check_slow("late NUL later match", ["--line-buffered", "needle"], [A, b"x\0needle\n", B])
check_slow("late NUL no later match", ["--line-buffered", "needle"], [A, b"x\0other\n"])
check_slow("literal late NUL later match", ["needle"], [A, b"x\0needle\n", B], TERMINAL_ONLY)
check_slow("regex late NUL later match", ["-E", "need(le)"], [A, b"x\0needle\n", B], TERMINAL_ONLY)
check_slow("context late NUL later match", ["--line-buffered", "-A1", "needle"], [A, b"x\0needle\n", B])

# GNU keeps -z output in stdio until EOF on a terminal; zgr deliberately shows
# every complete NUL record as well.
check_slow(
    "terminal NUL records",
    ["-z", "needle"],
    [b"needle a\0", b"needle b\0"],
    TERMINAL_ONLY,
    ([b"needle a\0", b"needle b\0"], b"", 0, b""),
)

with tempfile.TemporaryDirectory(prefix="zgr-streaming.") as directory:
    with open(f"{directory}/a", "wb") as handle:
        handle.write(b"x a\n")
    with open(f"{directory}/b", "wb") as handle:
        handle.write(b"x b\n")
    with open(f"{directory}/bin", "wb") as handle:
        handle.write(b"x\0y\n")
    with open(f"{directory}/big", "wb") as handle:
        handle.write(b"needle\n" * 400000)
    for kib in (90, 100, 192, 200, 260, 300, 400):
        with open(f"{directory}/nul{kib}", "wb") as handle:
            handle.write(b"needle\n" * (kib * 1024 // 7) + b"\0\n" + b"needle\n" * 10)

    check_shell("merged order, missing file", '"$1" x a gone b > out 2>&1; s=$?; cat out; exit $s', directory)
    check_shell("merged order, binary file", '"$1" x a bin b > out 2>&1; s=$?; cat out; exit $s', directory)
    check_shell("piped order, missing file", '"$1" x a gone b 2>&1 | cat', directory)
    check_shell(
        "default SIGPIPE",
        'yes needle | timeout 5 "$1" needle 2>err | head -1; s=("${PIPESTATUS[@]}"); cat err; echo "${s[1]}"',
        directory,
    )
    check_shell(
        "default SIGPIPE with -I",
        'yes needle | timeout 5 "$1" -I needle 2>err | head -1; s=("${PIPESTATUS[@]}"); cat err; echo "${s[1]}"',
        directory,
    )
    check_shell(
        "ignored SIGPIPE",
        "trap '' PIPE; \"$1\" needle big 2>err | head -1; s=(\"${PIPESTATUS[@]}\"); cat err; echo \"${s[0]}\"",
        directory,
    )
    check_shell(
        "diagnostic survives early closure",
        '"$1" needle gone big 2>err | head -1; s=("${PIPESTATUS[@]}"); cat err; echo "${s[0]}"',
        directory,
    )
    check_shell(
        "FIFO operand with -I",
        'timeout 5 bash -c "\\"$1\\" -I needle <(yes needle) | head -1"; echo $?',
        directory,
    )
    check_shell(
        "/dev/stdin operand with -I",
        'yes needle | timeout 5 "$1" -I needle /dev/stdin | head -1; s=("${PIPESTATUS[@]}"); echo "${s[1]}"',
        directory,
    )
    check_shell("closed stdout", '"$1" x a >&- 2>err; s=$?; cat err; exit $s', directory)
    check_shell("full device", '"$1" x a >/dev/full 2>err; s=$?; cat err; exit $s', directory)
    check_shell("closed stderr keeps results", '"$1" x gone a 2>&-', directory)
    for kib in (90, 100, 192, 200, 260, 300, 400):
        file = f"nul{kib}"
        for options in ("", "-I", "-n", "-E", "-I -E", "-c", "-I -c", "-m3", "-A1", "-I -A1"):
            pattern = "need(le)" if "-E" in options else "needle"
            check_shell(
                f"NUL at {kib} KiB [{options}] operand",
                f'"$1" {options} "{pattern}" {file} 2>err | sha256sum; s=("${{PIPESTATUS[@]}}"); cat err; echo "${{s[0]}}"',
                directory,
            )
            check_shell(
                f"NUL at {kib} KiB [{options}] redirected",
                f'"$1" {options} "{pattern}" < {file} 2>err | sha256sum; s=("${{PIPESTATUS[@]}}"); cat err; echo "${{s[0]}}"',
                directory,
            )

if failures:
    print(f"{PROGRAM} streaming failures: {len(failures)}", file=sys.stderr)
    for failure in failures:
        print(failure, file=sys.stderr)
    sys.exit(1)
print(f"{PROGRAM} streaming differentials passed")
