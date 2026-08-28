const std = @import("std");

pub const Rule = struct {
    pattern: []const u8,
    include: bool,
};

pub const Filters = struct {
    rules: []const Rule = &.{},
    exclude_dirs: []const []const u8 = &.{},

    pub fn allowsFile(self: Filters, name: []const u8) bool {
        var allowed = self.rules.len == 0 or !self.rules[0].include;
        for (self.rules) |rule| {
            if (pathGlobMatches(rule.pattern, name)) allowed = rule.include;
        }
        return allowed;
    }

    pub fn allowsDir(self: Filters, name: []const u8) bool {
        for (self.exclude_dirs) |pattern| {
            if (pathGlobMatches(stripTrailingSlashes(pattern), name)) return false;
        }
        return true;
    }
};

pub fn stripTrailingSlashes(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') end -= 1;
    return path[0..end];
}

fn pathGlobMatches(pattern: []const u8, name: []const u8) bool {
    if (globMatches(pattern, name)) return true;
    const base = std.fs.path.basename(name);
    if (base.len != name.len and globMatches(pattern, base)) return true;
    var index: usize = 0;
    while (index < name.len) : (index += 1) {
        if (name[index] == '/' and index + 1 < name.len and name[index + 1] != '/') {
            if (globMatches(pattern, name[index + 1 ..])) return true;
        }
    }
    return false;
}

pub fn globMatches(pattern: []const u8, name: []const u8) bool {
    var pattern_index: usize = 0;
    var name_index: usize = 0;
    var star_pattern: ?usize = null;
    var star_name: usize = 0;

    while (name_index < name.len) {
        if (pattern_index < pattern.len) {
            if (pattern[pattern_index] == '*') {
                while (pattern_index < pattern.len and pattern[pattern_index] == '*')
                    pattern_index += 1;
                if (pattern_index == pattern.len) return true;
                star_pattern = pattern_index;
                star_name = name_index;
                continue;
            }
            if (pattern[pattern_index] == '?') {
                pattern_index += 1;
                name_index += 1;
                continue;
            }
            if (pattern[pattern_index] == '[') {
                if (matchClass(pattern, pattern_index, name[name_index])) |class| {
                    if (class.matched) {
                        pattern_index = class.next;
                        name_index += 1;
                        continue;
                    }
                } else if (name[name_index] == '[') {
                    pattern_index += 1;
                    name_index += 1;
                    continue;
                }
            } else {
                const expected = if (pattern[pattern_index] == '\\' and pattern_index + 1 < pattern.len) escaped: {
                    pattern_index += 1;
                    break :escaped pattern[pattern_index];
                } else pattern[pattern_index];
                if (name[name_index] == expected) {
                    pattern_index += 1;
                    name_index += 1;
                    continue;
                }
            }
        }

        const retry_pattern = star_pattern orelse return false;
        star_name += 1;
        if (star_name > name.len) return false;
        pattern_index = retry_pattern;
        name_index = star_name;
    }
    while (pattern_index < pattern.len and pattern[pattern_index] == '*') pattern_index += 1;
    return pattern_index == pattern.len;
}

const ClassResult = struct {
    matched: bool,
    next: usize,
};

fn matchClass(pattern: []const u8, start: usize, byte: u8) ?ClassResult {
    var index = start + 1;
    if (index >= pattern.len) return null;
    const inverted = pattern[index] == '!' or pattern[index] == '^';
    if (inverted) index += 1;

    var matched = false;
    var has_member = false;
    if (index < pattern.len and pattern[index] == ']') {
        matched = byte == ']';
        has_member = true;
        index += 1;
    }
    while (index < pattern.len and pattern[index] != ']') {
        if (pattern[index] == '[' and index + 2 < pattern.len and pattern[index + 1] == ':') {
            const class_end = std.mem.find(u8, pattern[index + 2 ..], ":]") orelse return null;
            const class_name_start = index + 2;
            const class_name_end = class_name_start + class_end;
            matched = matched or namedClassMatches(pattern[class_name_start..class_name_end], byte);
            has_member = true;
            index = class_name_end + 2;
            continue;
        }
        const first = classByte(pattern, &index);
        has_member = true;
        if (index + 1 < pattern.len and pattern[index] == '-' and pattern[index + 1] != ']') {
            index += 1;
            const last = classByte(pattern, &index);
            if (first <= byte and byte <= last) matched = true;
        } else if (byte == first) {
            matched = true;
        }
    }
    if (index >= pattern.len or pattern[index] != ']' or !has_member) return null;
    return .{ .matched = if (inverted) !matched else matched, .next = index + 1 };
}

fn namedClassMatches(name: []const u8, byte: u8) bool {
    if (std.mem.eql(u8, name, "alnum")) return std.ascii.isAlphanumeric(byte);
    if (std.mem.eql(u8, name, "alpha")) return std.ascii.isAlphabetic(byte);
    if (std.mem.eql(u8, name, "blank")) return byte == ' ' or byte == '\t';
    if (std.mem.eql(u8, name, "cntrl")) return std.ascii.isControl(byte);
    if (std.mem.eql(u8, name, "digit")) return std.ascii.isDigit(byte);
    if (std.mem.eql(u8, name, "graph")) return std.ascii.isGraphical(byte);
    if (std.mem.eql(u8, name, "lower")) return std.ascii.isLower(byte);
    if (std.mem.eql(u8, name, "print")) return std.ascii.isPrint(byte);
    if (std.mem.eql(u8, name, "punct")) return std.ascii.isPunctuation(byte);
    if (std.mem.eql(u8, name, "space")) return std.ascii.isWhitespace(byte);
    if (std.mem.eql(u8, name, "upper")) return std.ascii.isUpper(byte);
    if (std.mem.eql(u8, name, "xdigit")) return std.ascii.isHex(byte);
    return false;
}

fn classByte(pattern: []const u8, index: *usize) u8 {
    if (pattern[index.*] == '\\' and index.* + 1 < pattern.len) index.* += 1;
    const result = pattern[index.*];
    index.* += 1;
    return result;
}

test "glob wildcards and classes" {
    try std.testing.expect(globMatches("*.c", ".hidden.c"));
    try std.testing.expect(globMatches("file-??.[ch]", "file-01.c"));
    try std.testing.expect(globMatches("file-[!0-3].c", "file-7.c"));
    try std.testing.expect(!globMatches("file-[!0-3].c", "file-2.c"));
    try std.testing.expect(globMatches("literal\\*", "literal*"));
    try std.testing.expect(globMatches("file[[:digit:]].c", "file7.c"));
    try std.testing.expect(!globMatches("file[[:digit:]].c", "filex.c"));
    try std.testing.expect(!globMatches("*.c", "file.h"));
}

test "path globs match suffixes and trailing slashes" {
    try std.testing.expect(pathGlobMatches("a", "x/a"));
    try std.testing.expect(pathGlobMatches("x/a", "x/a"));
    try std.testing.expect(pathGlobMatches("./x", "./x"));
    try std.testing.expect(pathGlobMatches("x", "./x"));
    try std.testing.expectEqualStrings("dir", stripTrailingSlashes("dir/"));
    const filters: Filters = .{ .exclude_dirs = &.{"dir/"} };
    try std.testing.expect(!filters.allowsDir("dir"));
    try std.testing.expect(!filters.allowsDir("x/dir"));
}

test "ordered file rules use the last match" {
    const rules = [_]Rule{
        .{ .pattern = "*.c", .include = false },
        .{ .pattern = "keep.c", .include = true },
    };
    const filters: Filters = .{ .rules = &rules };
    try std.testing.expect(filters.allowsFile("keep.c"));
    try std.testing.expect(!filters.allowsFile("other.c"));
    try std.testing.expect(filters.allowsFile("file.h"));

    const include_first = [_]Rule{
        .{ .pattern = "*.c", .include = true },
        .{ .pattern = "skip.c", .include = false },
    };
    const restrictive: Filters = .{ .rules = &include_first };
    try std.testing.expect(restrictive.allowsFile("keep.c"));
    try std.testing.expect(!restrictive.allowsFile("skip.c"));
    try std.testing.expect(!restrictive.allowsFile("file.h"));
}
