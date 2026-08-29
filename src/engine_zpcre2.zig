const std = @import("std");
const zpcre2 = @import("zpcre2");
const locale = @import("locale.zig");

pub const ZG_REGEX_SYNTAX_BASIC: c_int = 0;
pub const ZG_REGEX_SYNTAX_EXTENDED: c_int = 1;
pub const ZG_REGEX_SYNTAX_PERL: c_int = 2;

pub const ZG_LOCALE_CLASS_ALNUM = locale.ZG_LOCALE_CLASS_ALNUM;
pub const ZG_LOCALE_CLASS_ALPHA = locale.ZG_LOCALE_CLASS_ALPHA;
pub const ZG_LOCALE_CLASS_BLANK = locale.ZG_LOCALE_CLASS_BLANK;
pub const ZG_LOCALE_CLASS_DIGIT = locale.ZG_LOCALE_CLASS_DIGIT;
pub const ZG_LOCALE_CLASS_GRAPH = locale.ZG_LOCALE_CLASS_GRAPH;
pub const ZG_LOCALE_CLASS_LOWER = locale.ZG_LOCALE_CLASS_LOWER;
pub const ZG_LOCALE_CLASS_PRINT = locale.ZG_LOCALE_CLASS_PRINT;
pub const ZG_LOCALE_CLASS_PUNCT = locale.ZG_LOCALE_CLASS_PUNCT;
pub const ZG_LOCALE_CLASS_UPPER = locale.ZG_LOCALE_CLASS_UPPER;
pub const ZG_LOCALE_CLASS_XDIGIT = locale.ZG_LOCALE_CLASS_XDIGIT;

pub const zg_initialize_locale = locale.zg_initialize_locale;
pub const zg_locale_is_utf8 = locale.zg_locale_is_utf8;
pub const zg_locale_has_simple_ascii_casefold = locale.zg_locale_has_simple_ascii_casefold;
pub const zg_locale_has_standard_ascii_classes = locale.zg_locale_has_standard_ascii_classes;
pub const zg_locale_ascii_case_literal_matches = locale.zg_locale_ascii_case_literal_matches;
pub const zg_locale_ascii_literal_word_matches = locale.zg_locale_ascii_literal_word_matches;
pub const zg_locale_class_run_matches = locale.zg_locale_class_run_matches;

pub const zg_regex = struct {
    pcre: ?zpcre2.Allocated = null,
    witness: ?zpcre2.Allocated = null,
    match_error: bool = false,
};

pub const zg_regex_worker = struct {
    regex: *const zg_regex,
};

const allocator = std.heap.c_allocator;

fn slice(ptr: [*]const u8, len: usize) []const u8 {
    return ptr[0..len];
}

fn setError(buf: [*]u8, len: usize, comptime fmt: []const u8, args: anytype) void {
    if (len == 0) return;
    const msg = std.fmt.bufPrint(buf[0 .. len - 1], fmt, args) catch {
        buf[len - 1] = 0;
        return;
    };
    buf[msg.len] = 0;
}

fn compileZpcre(
    pattern: []const u8,
    ignore_case: bool,
    dot_matches_newline: bool,
    utf: bool,
) zpcre2.Error!zpcre2.Allocated {
    return zpcre2.compileAlloc(allocator, pattern, .{
        .utf = utf,
        .caseless = ignore_case,
        .dotall = dot_matches_newline,
    });
}

pub fn zg_regex_compile(
    pcre_pattern: [*]const u8,
    pcre_pattern_len: usize,
    posix_pattern: [*]const u8,
    posix_pattern_len: usize,
    syntax: c_int,
    pcre_compatible: bool,
    ascii_witness: bool,
    posix_spans: bool,
    ignore_case: bool,
    dot_matches_newline: bool,
    line_regexp: bool,
    word_regexp: bool,
    error_buffer: [*]u8,
    error_buffer_len: usize,
) ?*zg_regex {
    _ = syntax;
    _ = pcre_compatible;
    _ = posix_spans;
    _ = line_regexp;
    _ = word_regexp;

    const regex = allocator.create(zg_regex) catch {
        setError(error_buffer, error_buffer_len, "out of memory compiling regex", .{});
        return null;
    };
    regex.* = .{};

    const pcre_bytes = slice(pcre_pattern, pcre_pattern_len);
    if (locale.zg_pattern_would_overflow(pcre_pattern, pcre_pattern_len) or
        locale.zg_pattern_would_overflow(posix_pattern, posix_pattern_len))
    {
        setError(error_buffer, error_buffer_len, "stack overflow", .{});
        allocator.destroy(regex);
        return null;
    }

    regex.pcre = compileZpcre(
        pcre_bytes,
        ignore_case,
        dot_matches_newline,
        locale.zg_locale_is_utf8(),
    ) catch |err| {
        setError(
            error_buffer,
            error_buffer_len,
            "regex error: {s}",
            .{@errorName(err)},
        );
        allocator.destroy(regex);
        return null;
    };

    if (ascii_witness) {
        regex.witness = compileZpcre(pcre_bytes, false, dot_matches_newline, false) catch null;
    }
    return regex;
}

pub fn zg_regex_uses_pcre(regex: *const zg_regex) bool {
    return regex.pcre != null;
}

pub fn zg_regex_required_literal(
    regex: *const zg_regex,
    ptr_out: [*c][*c]const u8,
    len_out: [*c]usize,
) bool {
    const compiled = if (regex.pcre) |*value| value else return false;
    if (compiled.study.req_lit_len < 3) return false;
    ptr_out.?.* = @ptrCast(&compiled.study.req_lit);
    len_out.?.* = compiled.study.req_lit_len;
    return true;
}

pub fn zg_regex_matches(regex: *zg_regex, subject: [*]const u8, subject_len: usize) bool {
    regex.match_error = false;
    const compiled = regex.pcre orelse return false;
    return compiled.isMatch(slice(subject, subject_len));
}

pub fn zg_regex_match_error(regex: *const zg_regex) bool {
    return regex.match_error;
}

pub fn zg_pcre2_version() [*:0]const u8 {
    return "10";
}

pub fn zg_regex_posix_matches(regex: *zg_regex, subject: [*]const u8, subject_len: usize) bool {
    return zg_regex_matches(regex, subject, subject_len);
}

pub fn zg_regex_pcre_find(
    regex: *zg_regex,
    subject: [*]const u8,
    subject_len: usize,
    start_offset: usize,
    match_start: *usize,
    match_end: *usize,
) bool {
    const compiled = regex.pcre orelse return false;
    const found = compiled.findFrom(slice(subject, subject_len), start_offset) orelse return false;
    match_start.* = found.start;
    match_end.* = found.end;
    return true;
}

pub fn zg_regex_find(
    regex: *zg_regex,
    subject: [*]const u8,
    subject_len: usize,
    start_offset: usize,
    match_start: *usize,
    match_end: *usize,
) bool {
    return zg_regex_pcre_find(regex, subject, subject_len, start_offset, match_start, match_end);
}

pub fn zg_regex_worker_create(regex: *const zg_regex) ?*zg_regex_worker {
    const worker = allocator.create(zg_regex_worker) catch return null;
    worker.* = .{ .regex = regex };
    return worker;
}

pub fn zg_regex_worker_matches(
    worker: *zg_regex_worker,
    subject: [*]const u8,
    subject_len: usize,
) bool {
    return zg_regex_matches(@constCast(worker.regex), subject, subject_len);
}

pub fn zg_regex_worker_ascii_witness_matches(
    worker: *zg_regex_worker,
    subject: [*]const u8,
    subject_len: usize,
) bool {
    const compiled = worker.regex.witness orelse return false;
    return compiled.isMatch(slice(subject, subject_len));
}

pub fn zg_regex_worker_posix_matches(
    worker: *zg_regex_worker,
    subject: [*]const u8,
    subject_len: usize,
) bool {
    return zg_regex_posix_matches(@constCast(worker.regex), subject, subject_len);
}

pub fn zg_regex_worker_free(worker: ?*zg_regex_worker) void {
    const value = worker orelse return;
    allocator.destroy(value);
}

pub fn zg_regex_free(regex: ?*zg_regex) void {
    const value = regex orelse return;
    if (value.pcre) |*pcre| pcre.deinit();
    if (value.witness) |*witness| witness.deinit();
    allocator.destroy(value);
}

test {
    _ = locale;
}
