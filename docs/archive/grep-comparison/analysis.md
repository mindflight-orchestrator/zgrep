Binary names changed after this note: `zgr` is the zpcre2 default and `zgrc` is
the C GNU-compat engine (the former `zgr`). The investigation below still uses
the old names.

The engine is not what is slow. `zgr-zpcre2` often never calls zpcre2 on BRE/ERE.

I cloned GNU grep and compared it with both of our shims. Isolated zpcre2 can beat C PCRE2; the grep binary is slower because the wrapper takes a different path from `pcre2_shim.c`.

## What actually runs

`matcher.zig` is shared. The C locale bench cases (`-E status=(200|500)`, inner-literal ERE, …) become `Matcher.regex`, which calls `zg_regex_matches`.

C shim: POSIX is compiled only when needed, and **match always uses PCRE2 JIT**:

```183:199:src/pcre2_shim.c
    if ((syntax == ZG_REGEX_SYNTAX_BASIC || syntax == ZG_REGEX_SYNTAX_EXTENDED)
        && (!pcre_compatible || posix_spans)) {
        regex->posix = zg_posix_compile(/* ... */);
        if (regex->posix == NULL) { /* ... */ }
        if (!pcre_compatible) return regex;
    }
```

```288:316:src/pcre2_shim.c
bool zg_regex_matches(zg_regex *regex, const uint8_t *subject, size_t subject_len) {
    int result;
    regex->match_error = false;
    if (regex->jit) {
        result = pcre2_jit_match(/* ... */);
    } else {
        result = pcre2_match(/* ... */);
    }
    /* ... */
    return result >= 0;
}
```

zpcre2 shim: POSIX is compiled for **every** BRE/ERE, then match **prefers POSIX**:

```127:141:src/engine_zpcre2.zig
    if (basic_or_extended) {
        regex.posix = compilePosix(/* ... */);
        if (regex.posix == null) {
            allocator.destroy(regex);
            return null;
        }
        if (!pcre_compatible) return regex;
    }
```

```193:200:src/engine_zpcre2.zig
pub fn zg_regex_matches(regex: *zg_regex, subject: [*]const u8, subject_len: usize) bool {
    regex.match_error = false;
    if (regex.posix != null) {
        return gnu.zg_posix_matches(regex.posix, subject, subject_len);
    }
    const compiled = regex.pcre orelse return false;
    return compiled.isMatch(slice(subject, subject_len));
}
```

Workers do the same (`zg_regex_worker_matches` → `zg_regex_matches`). So for default `-E` in `C`, `zgr-zpcre2` is running **glibc `regexec`**, not zpcre2. That matches the v0.4 numbers: literals are a tie (same Zig scanner); `status=(200|500)` hits every line and is **1.57×** slower; inner-literal looked faster because that run gave only zpcre2 a study-literal prefilter, while the C shim still returned “no required literal”.

zpcre2 is used for `-P`, and for BRE/ERE only when POSIX was not compiled. The isolated zpcre2 vs pcre2 microbench is a different program.

## GNU grep is not a PCRE2 grep

From `grep.c`:

| Matcher | Compile / execute | Used for |
|---|---|---|
| `grep` / `egrep` | `GEAcompile` / `EGexecute` | default, `-G`, `-E` |
| `fgrep` | `Fcompile` / `Fexecute` | `-F` |
| `perl` | `Pcompile` / `Pexecute` | **`-P` only** |

GNU grep never feeds BRE/ERE to PCRE2. Its default path is:

1. **kwset** (`dfamust`) — required literal skip, same idea as our prefilter
2. **GNU DFA** (`dfaexec`, optionally a superset DFA first)
3. **glibc regex** only if the DFA saw a back-reference

PCRE2 in GNU grep (`src/pcresearch.c`) is a third engine, for `-P`:

- compile + `pcre2_jit_compile`
- execute with `pcre2_match` (not `pcre2_jit_match`)
- walk the **buffer** with `rawmemchr` for newlines, then match one line
- empty-match shortcut, invalid-UTF skip, JIT-stack grow

We split records first, then match. GNU grep finds a candidate in a chunk, then snaps to the line. That is a real architectural difference, but it is **not** why `zgr-zpcre2` loses to `zgr`.

## Logical diff: grep vs us vs the two shims

```text
GNU grep -E          DFA + kwset must-literal; glibc regex only for backrefs
                     PCRE2 is not in this path

zgr -E               if PCRE-compatible → PCRE2 JIT
                     else glibc POSIX
                     optional literal / class / NFA shortcuts in matcher.zig

zgr-zpcre2 (meant)   same dispatch, zpcre2 instead of libpcre2

zgr-zpcre2 (now)     BRE/ERE → always compile POSIX
                     zg_regex_matches → POSIX first
                     zpcre2 sits unused on the hot path
```

Other shim gaps (once POSIX is no longer stealing the call):

- C has `pcre2_dfa_match` for POSIX leftmost-longest `-o`; zpcre2 has no DFA
- C keeps per-thread `pcre2_match_data`; zpcre2 workers are just a pointer
- C sets `PCRE2_MATCH_INVALID_UTF` for `-P` in UTF-8; zpcre2 only passes `utf` / `caseless` / `dotall`
- C extracts a required literal by walking the pattern; zpcre2 uses `study.req_lit`

Those matter after the dispatch bug is fixed. They are not the current 1.6× on dense ERE.


The next useful change is to make `engine_zpcre2.zig` follow `pcre2_shim.c`: compile POSIX only when `!pcre_compatible || posix_spans`, and let `zg_regex_matches` / workers call zpcre2 when `pcre != null`. Then we can re-bench `status=(200|500)` and see the real zpcre2 vs JIT gap.