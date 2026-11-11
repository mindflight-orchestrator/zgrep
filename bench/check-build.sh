#!/bin/sh
# Read compilation facts from the executable, not from the caller's environment.
set -eu

if [ "$#" -eq 0 ]; then
    echo 'usage: bench/check-build.sh ZGR [ZGRC]' >&2
    exit 2
fi

for binary do
    version=$("$binary" --version)
    build_info=$(printf '%s\n' "$version" | sed -n '/^build: /p')
    case "$build_info" in
        *' optimize=ReleaseFast backend=stage2_llvm '*|*' optimize=fast backend=stage2_llvm '*) ;;
        *)
            if [ "${BENCH_ALLOW_UNOPTIMIZED:-0}" != 1 ]; then
                printf 'benchmark requires a verified ReleaseFast LLVM binary: %s\n' "$binary" >&2
                printf 'found: %s\n' "${build_info:-build metadata unavailable}" >&2
                echo 'run: zig build -Doptimize=ReleaseFast -Dllvm=true' >&2
                echo 'for an explicitly labelled exploratory run: BENCH_ALLOW_UNOPTIMIZED=1' >&2
                exit 2
            fi
            printf 'EXPLORATORY: ReleaseFast LLVM profile not verified for %s\n' "$binary" >&2
            ;;
    esac
    printf 'binary: %s\n' "$(realpath "$binary")"
    printf '%s\n' "$version"
    sha256sum "$binary"
done
