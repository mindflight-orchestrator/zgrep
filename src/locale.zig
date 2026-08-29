const std = @import("std");
const builtin = @import("builtin");

pub const ZG_LOCALE_CLASS_ALNUM: u32 = 1 << 0;
pub const ZG_LOCALE_CLASS_ALPHA: u32 = 1 << 1;
pub const ZG_LOCALE_CLASS_BLANK: u32 = 1 << 2;
pub const ZG_LOCALE_CLASS_DIGIT: u32 = 1 << 3;
pub const ZG_LOCALE_CLASS_GRAPH: u32 = 1 << 4;
pub const ZG_LOCALE_CLASS_LOWER: u32 = 1 << 5;
pub const ZG_LOCALE_CLASS_PRINT: u32 = 1 << 6;
pub const ZG_LOCALE_CLASS_PUNCT: u32 = 1 << 7;
pub const ZG_LOCALE_CLASS_UPPER: u32 = 1 << 8;
pub const ZG_LOCALE_CLASS_XDIGIT: u32 = 1 << 9;

var utf8_locale = false;
var simple_ascii_casefold = false;

fn getenv(name: []const u8) ?[]const u8 {
    switch (builtin.os.tag) {
        .windows => return null,
        else => {
            const c_environ = std.c.environ;
            var count: usize = 0;
            while (c_environ[count] != null) : (count += 1) {}
            const environ: std.process.Environ = .{
                .block = .{ .slice = c_environ[0..count :null] },
            };
            return std.process.Environ.getPosix(environ, name);
        },
    }
}

fn localeName() []const u8 {
    if (getenv("LC_ALL")) |value| if (value.len != 0) return value;
    if (getenv("LC_CTYPE")) |value| if (value.len != 0) return value;
    if (getenv("LANG")) |value| if (value.len != 0) return value;
    return "C";
}

fn codesetOf(name: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return &.{};
    var codeset = name[dot + 1 ..];
    if (std.mem.indexOfScalar(u8, codeset, '@')) |at| codeset = codeset[0..at];
    return codeset;
}

fn isUtf8Locale(name: []const u8) bool {
    const codeset = codesetOf(name);
    return std.ascii.eqlIgnoreCase(codeset, "UTF-8") or std.ascii.eqlIgnoreCase(codeset, "UTF8");
}

fn isSimpleAsciiCasefoldLocale(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "C.UTF-8") or
        std.ascii.eqlIgnoreCase(name, "C.utf8") or
        std.ascii.startsWithIgnoreCase(name, "en_") or
        std.ascii.startsWithIgnoreCase(name, "nl_");
}

pub fn zg_initialize_locale() bool {
    const name = localeName();
    utf8_locale = isUtf8Locale(name);
    simple_ascii_casefold = utf8_locale and isSimpleAsciiCasefoldLocale(name);
    return utf8_locale;
}

pub fn zg_locale_is_utf8() bool {
    return utf8_locale;
}

pub fn zg_locale_has_simple_ascii_casefold() bool {
    return simple_ascii_casefold;
}

pub fn zg_locale_has_standard_ascii_classes() bool {
    return true;
}

pub fn zg_pattern_would_overflow(pattern: [*]const u8, pattern_len: usize) bool {
    if (pattern_len < 10000) return false;
    var opens: usize = 0;
    for (pattern[0..pattern_len]) |byte| {
        if (byte == '(') opens += 1;
    }
    return opens > pattern_len / 2;
}

fn asciiUpper(byte: u8) u8 {
    return std.ascii.toUpper(byte);
}

fn asciiCaseEqual(subject: []const u8, expected: u8) ?usize {
    if (subject.len == 0) return null;
    const expected_upper = asciiUpper(expected);
    if (subject[0] < 0x80) {
        if (asciiUpper(subject[0]) == expected_upper) return 1;
        return null;
    }
    if (subject.len >= 2 and expected_upper == 'I' and subject[0] == 0xc4 and subject[1] == 0xb1)
        return 2;
    if (subject.len >= 2 and expected_upper == 'S' and subject[0] == 0xc5 and subject[1] == 0xbf)
        return 2;
    return null;
}

pub fn zg_locale_ascii_case_literal_matches(
    subject: [*]const u8,
    subject_len: usize,
    pattern: [*]const u8,
    pattern_len: usize,
) bool {
    const haystack = subject[0..subject_len];
    const needle = pattern[0..pattern_len];
    if (needle.len == 0) return true;
    const first_upper = asciiUpper(needle[0]);
    const first_lower: u8 = if (first_upper >= 'A' and first_upper <= 'Z')
        first_upper + ('a' - 'A')
    else
        first_upper;
    const extra: u8 = if (first_upper == 'I') 0xc4 else 0xc5;
    const candidates = [_]u8{ first_upper, first_lower, extra };
    const candidate_count: usize = if (first_upper == 'I' or first_upper == 'S') 3 else 2;

    var candidate_index: usize = 0;
    while (candidate_index < candidate_count) : (candidate_index += 1) {
        if (candidate_index == 1 and first_lower == first_upper) continue;
        var search = haystack;
        while (std.mem.indexOfScalar(u8, search, candidates[candidate_index])) |found| {
            const at = haystack.len - search.len + found;
            const rest = haystack[at..];
            var offset: usize = 0;
            var pattern_index: usize = 0;
            while (pattern_index < needle.len and offset < rest.len) {
                const consumed = asciiCaseEqual(rest[offset..], needle[pattern_index]) orelse break;
                offset += consumed;
                pattern_index += 1;
            }
            if (pattern_index == needle.len) return true;
            search = search[found + 1 ..];
        }
    }
    return false;
}

fn isWordByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn isWordCharacter(subject: []const u8, offset: usize) bool {
    if (offset >= subject.len) return false;
    if (!utf8_locale or subject[offset] < 0x80) return isWordByte(subject[offset]);
    return false;
}

fn isWordBefore(subject: []const u8, offset: usize) bool {
    if (offset == 0) return false;
    var character_start = offset - 1;
    if (utf8_locale) {
        while (character_start != 0 and subject[character_start] & 0xc0 == 0x80) {
            character_start -= 1;
        }
    }
    return isWordCharacter(subject, character_start);
}

pub fn zg_locale_ascii_literal_word_matches(
    subject: [*]const u8,
    subject_len: usize,
    pattern: [*]const u8,
    pattern_len: usize,
) bool {
    const haystack = subject[0..subject_len];
    const needle = pattern[0..pattern_len];
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var search = haystack;
    while (std.mem.indexOf(u8, search, needle)) |found| {
        const start = haystack.len - search.len + found;
        const end = start + needle.len;
        if (!isWordBefore(haystack, start) and !isWordCharacter(haystack, end)) return true;
        search = search[found + 1 ..];
    }
    return false;
}

fn utf8Width(subject: []const u8) usize {
    return std.unicode.utf8ByteSequenceLength(subject[0]) catch 1;
}

pub fn zg_locale_class_run_matches(
    subject: [*]const u8,
    subject_len: usize,
    ascii_mask_low: u64,
    ascii_mask_high: u64,
    classes: u32,
    minimum: usize,
) bool {
    _ = classes;
    if (minimum == 0) return true;
    const haystack = subject[0..subject_len];
    var run: usize = 0;
    var offset: usize = 0;
    while (offset < haystack.len) {
        const byte = haystack[offset];
        var accepted = false;
        var width: usize = 1;
        if (byte < 0x80) {
            const mask = if (byte < 64) ascii_mask_low else ascii_mask_high;
            accepted = mask & (@as(u64, 1) << @intCast(byte & 63)) != 0;
        } else {
            width = utf8Width(haystack[offset..]);
            if (offset + width > haystack.len) width = 1;
        }
        if (accepted) {
            run += 1;
            if (run >= minimum) return true;
        } else {
            run = 0;
        }
        offset += width;
    }
    return false;
}

test "UTF-8 locale names" {
    try std.testing.expect(isUtf8Locale("C.UTF-8"));
    try std.testing.expect(isUtf8Locale("en_US.utf8"));
    try std.testing.expect(isUtf8Locale("nl_BE.UTF-8@euro"));
    try std.testing.expect(!isUtf8Locale("C"));
    try std.testing.expect(!isUtf8Locale("POSIX"));
    try std.testing.expect(isSimpleAsciiCasefoldLocale("C.utf8"));
    try std.testing.expect(isSimpleAsciiCasefoldLocale("en_US.UTF-8"));
    try std.testing.expect(!isSimpleAsciiCasefoldLocale("tr_TR.UTF-8"));
}

test "ASCII class run ignores non-ASCII bytes" {
    var masks = [_]u64{ 0, 0 };
    var byte: u8 = '0';
    while (byte <= '9') : (byte += 1) {
        masks[byte >> 6] |= @as(u64, 1) << @intCast(byte & 63);
    }
    try std.testing.expect(zg_locale_class_run_matches("status=500".ptr, 10, masks[0], masks[1], 0, 3));
    try std.testing.expect(!zg_locale_class_run_matches("status=50".ptr, 9, masks[0], masks[1], 0, 3));
    try std.testing.expect(zg_locale_class_run_matches("\xff500".ptr, 4, masks[0], masks[1], 0, 3));
}

test "pattern overflow heuristic" {
    try std.testing.expect(!zg_pattern_would_overflow("abc".ptr, 3));
    const dense = "(" ** 6000 ++ "a" ** 4000;
    try std.testing.expect(zg_pattern_would_overflow(dense.ptr, dense.len));
}
