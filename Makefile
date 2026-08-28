# Thin POSIX wrapper around `zig build`.
# Build as a regular user, then install with `sudo make install`.
# Do not run `zig` as root: that would write caches owned by root.

PREFIX ?= /usr/local
DESTDIR ?=
OPTIMIZE ?= ReleaseFast
ZIG ?= zig
BIN := zig-out/bin/zgr

.PHONY: all build install uninstall test clean

all: build

build:
	$(ZIG) build -Doptimize=$(OPTIMIZE)

install:
	@test -x "$(BIN)" || { echo 'zgr: run `make` before `make install`' >&2; exit 1; }
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 755 "$(BIN)" "$(DESTDIR)$(PREFIX)/bin/zgr"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/zgr"

test:
	$(ZIG) build test -Doptimize=$(OPTIMIZE)

clean:
	rm -rf zig-out .zig-cache
