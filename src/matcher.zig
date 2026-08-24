const std = @import("std");
const c = @import("pcre2");
const options = @import("options.zig");

pub const Match = struct {
    start: usize,
    end: usize,
};

pub const Matcher = union(enum) {
    literal: Literal,
    alternation: LiteralAlternation,
    regex: Regex,
    posix_regex: Regex,

    pub fn init(
        allocator: std.mem.Allocator,
        pattern: []const u8,
        mode: options.Mode,
        ignore_case: bool,
        line_regexp: bool,
        word_regexp: bool,
        only_matching: bool,
        dot_matches_newline: bool,
        error_buffer: []u8,
    ) !Matcher {
        if (mode == .fixed) {
            return .{ .literal = Literal.init(pattern, ignore_case, line_regexp, word_regexp) };
        }
        if (isLiteralPattern(pattern, mode)) {
            return .{ .literal = Literal.init(pattern, ignore_case, line_regexp, word_regexp) };
        }
        if (mode == .extended) {
            if (try LiteralAlternation.init(
                allocator,
                pattern,
                ignore_case,
                line_regexp,
                word_regexp,
            )) |alternation| return .{ .alternation = alternation };
        }

        const translated = try translatePattern(allocator, pattern, mode, line_regexp, word_regexp);
        defer allocator.free(translated);
        const pcre_compatible = posixPatternIsPcreCompatible(pattern, mode);
        const regex = c.zg_regex_compile(
            translated.ptr,
            translated.len,
            pattern.ptr,
            pattern.len,
            switch (mode) {
                .basic => c.ZG_REGEX_SYNTAX_BASIC,
                .extended => c.ZG_REGEX_SYNTAX_EXTENDED,
                .fixed, .perl => c.ZG_REGEX_SYNTAX_PERL,
            },
            pcre_compatible,
            only_matching and posixPatternNeedsLongestEngine(pattern, mode),
            ignore_case,
            dot_matches_newline,
            line_regexp,
            word_regexp,
            error_buffer.ptr,
            error_buffer.len,
        ) orelse return error.InvalidRegex;
        const prefilter = if (!ignore_case and mode == .extended)
            if (requiredLiteralEre(pattern)) |literal| Literal.init(literal, false, false, false) else null
        else
            null;
        const value: Regex = .{ .compiled = regex, .prefilter = prefilter };
        return if (c.zg_regex_uses_pcre(regex))
            .{ .regex = value }
        else
            .{ .posix_regex = value };
    }

    pub fn deinit(self: *Matcher) void {
        switch (self.*) {
            .literal => {},
            .alternation => |*alternation| alternation.deinit(),
            .regex => |*regex| c.zg_regex_free(regex.compiled),
            .posix_regex => |*regex| c.zg_regex_free(regex.compiled),
        }
    }

    pub fn matches(self: *const Matcher, line: []const u8) bool {
        return switch (self.*) {
            .literal => |*literal| literal.matches(line),
            .alternation => |*alternation| alternation.matches(line),
            .regex => |*regex| regex.matches(line),
            .posix_regex => |*regex| regex.matchesPosix(line),
        };
    }

    pub fn find(self: *const Matcher, line: []const u8, start: usize) ?Match {
        return switch (self.*) {
            .literal => |*literal| literal.findMatch(line, start),
            .alternation => |*alternation| alternation.find(line, start),
            .regex => |*regex| regex.find(line, start),
            .posix_regex => |*regex| regex.find(line, start),
        };
    }
};

pub const LiteralAlternation = struct {
    literals: []Literal,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        pattern: []const u8,
        ignore_case: bool,
        whole_line: bool,
        word: bool,
    ) !?LiteralAlternation {
        var count: usize = 1;
        var part_start: usize = 0;
        for (pattern, 0..) |byte, index| {
            if (byte == '|') {
                if (index == part_start) return null;
                count += 1;
                part_start = index + 1;
                continue;
            }
            if (byte == '\\' or byte == '[' or byte == ']' or byte == '.' or byte == '^' or
                byte == '$' or byte == '*' or byte == '(' or byte == ')' or byte == '{' or
                byte == '}' or byte == '+' or byte == '?') return null;
        }
        if (count == 1 or part_start == pattern.len) return null;

        const literals = try allocator.alloc(Literal, count);
        errdefer allocator.free(literals);
        var iterator = std.mem.splitScalar(u8, pattern, '|');
        var index: usize = 0;
        while (iterator.next()) |part| : (index += 1) {
            literals[index] = .init(part, ignore_case, whole_line, word);
        }
        return .{ .literals = literals, .allocator = allocator };
    }

    pub fn deinit(self: *LiteralAlternation) void {
        self.allocator.free(self.literals);
    }

    pub fn matches(self: *const LiteralAlternation, line: []const u8) bool {
        for (self.literals) |*literal| {
            if (literal.matches(line)) return true;
        }
        return false;
    }

    pub fn find(self: *const LiteralAlternation, line: []const u8, start: usize) ?Match {
        var best: ?Match = null;
        for (self.literals) |*literal| {
            const candidate = literal.findMatch(line, start) orelse continue;
            if (best == null or candidate.start < best.?.start or
                (candidate.start == best.?.start and candidate.end > best.?.end)) best = candidate;
        }
        return best;
    }
};

pub const Regex = struct {
    compiled: *c.zg_regex,
    prefilter: ?Literal,

    pub fn matches(self: *const Regex, line: []const u8) bool {
        if (self.prefilter) |*prefilter| {
            if (prefilter.find(line, 0) == null) return false;
        }
        return self.matchesFull(line);
    }

    pub fn matchesFull(self: *const Regex, line: []const u8) bool {
        return c.zg_regex_matches(self.compiled, line.ptr, line.len);
    }

    pub fn matchesPosix(self: *const Regex, line: []const u8) bool {
        if (self.prefilter) |*prefilter| {
            if (prefilter.find(line, 0) == null) return false;
        }
        return c.zg_regex_posix_matches(self.compiled, line.ptr, line.len);
    }

    pub fn find(self: *const Regex, line: []const u8, start: usize) ?Match {
        if (start > line.len) return null;
        if (self.prefilter) |*prefilter| {
            if (prefilter.find(line, start) == null) return null;
        }
        var match_start: usize = undefined;
        var match_end: usize = undefined;
        if (!c.zg_regex_find(
            self.compiled,
            line.ptr,
            line.len,
            start,
            &match_start,
            &match_end,
        )) return null;
        return .{ .start = match_start, .end = match_end };
    }

    pub fn createWorker(self: *const Regex) ?RegexWorker {
        const worker = c.zg_regex_worker_create(self.compiled) orelse return null;
        return .{ .compiled = worker };
    }
};

pub const RegexWorker = struct {
    compiled: *c.zg_regex_worker,

    pub fn deinit(self: *RegexWorker) void {
        c.zg_regex_worker_free(self.compiled);
    }

    pub fn matches(self: *const RegexWorker, line: []const u8) bool {
        return c.zg_regex_worker_matches(self.compiled, line.ptr, line.len);
    }

    pub fn matchesPosix(self: *const RegexWorker, line: []const u8) bool {
        return c.zg_regex_worker_posix_matches(self.compiled, line.ptr, line.len);
    }
};

pub const ThreadMatcher = union(enum) {
    literal: *const Literal,
    alternation: *const LiteralAlternation,
    regex: struct {
        value: *const Regex,
        worker: RegexWorker,
    },
    posix_regex: struct {
        value: *const Regex,
        worker: RegexWorker,
    },

    pub fn init(matcher: *const Matcher) !ThreadMatcher {
        return switch (matcher.*) {
            .literal => |*literal| .{ .literal = literal },
            .alternation => |*alternation| .{ .alternation = alternation },
            .regex => |*regex| .{ .regex = .{
                .value = regex,
                .worker = regex.createWorker() orelse return error.OutOfMemory,
            } },
            .posix_regex => |*regex| .{ .posix_regex = .{
                .value = regex,
                .worker = regex.createWorker() orelse return error.OutOfMemory,
            } },
        };
    }

    pub fn deinit(self: *ThreadMatcher) void {
        switch (self.*) {
            .regex => |*regex| regex.worker.deinit(),
            .posix_regex => |*regex| regex.worker.deinit(),
            else => {},
        }
    }

    pub fn matches(self: *const ThreadMatcher, record: []const u8) bool {
        return switch (self.*) {
            .literal => |literal| literal.matches(record),
            .alternation => |alternation| alternation.matches(record),
            .regex => |*regex| matches: {
                if (regex.value.prefilter) |*prefilter| {
                    if (prefilter.find(record, 0) == null) break :matches false;
                }
                break :matches regex.worker.matches(record);
            },
            .posix_regex => |*regex| matches: {
                if (regex.value.prefilter) |*prefilter| {
                    if (prefilter.find(record, 0) == null) break :matches false;
                }
                break :matches regex.worker.matchesPosix(record);
            },
        };
    }
};

pub const Literal = struct {
    pattern: []const u8,
    skip: [256]usize,
    ignore_case: bool,
    whole_line: bool,
    word: bool,

    pub fn init(pattern: []const u8, ignore_case: bool, whole_line: bool, word: bool) Literal {
        var result: Literal = .{
            .pattern = pattern,
            .skip = undefined,
            .ignore_case = ignore_case,
            .whole_line = whole_line,
            .word = word,
        };
        @memset(&result.skip, @max(pattern.len, 1));
        if (pattern.len > 1) {
            for (pattern[0 .. pattern.len - 1], 0..) |byte, index| {
                const shift = pattern.len - 1 - index;
                result.skip[byte] = shift;
                if (ignore_case) {
                    result.skip[std.ascii.toLower(byte)] = shift;
                    result.skip[std.ascii.toUpper(byte)] = shift;
                }
            }
        }
        return result;
    }

    pub fn matches(self: *const Literal, line: []const u8) bool {
        if (self.whole_line) return self.eqlPattern(line);
        var start: usize = 0;
        while (self.find(line, start)) |index| {
            if (self.acceptsMatchAt(line, index)) return true;
            start = index + @max(self.pattern.len, 1);
            if (start > line.len) return false;
        }
        return false;
    }

    pub fn acceptsMatchAt(self: *const Literal, haystack: []const u8, start: usize) bool {
        return !self.word or hasWordBoundaries(haystack, start, self.pattern.len);
    }

    pub fn findMatch(self: *const Literal, line: []const u8, start: usize) ?Match {
        if (self.whole_line) {
            if (start != 0 or !self.eqlPattern(line)) return null;
            return .{ .start = 0, .end = line.len };
        }
        var position = start;
        while (self.find(line, position)) |found| {
            if (self.acceptsMatchAt(line, found))
                return .{ .start = found, .end = found + self.pattern.len };
            position = found + @max(self.pattern.len, 1);
            if (position > line.len) return null;
        }
        return null;
    }

    pub fn find(self: *const Literal, haystack: []const u8, start: usize) ?usize {
        if (start > haystack.len or self.pattern.len > haystack.len - start) return null;
        if (self.pattern.len == 0) return start;
        if (haystack.len - start < 64) {
            if (!self.ignore_case) return std.mem.findPosLinear(u8, haystack, start, self.pattern);
            return self.findScalarIgnoreCase(haystack, start);
        }

        if (self.pattern.len <= 32) return self.findVectorized(haystack, start);

        var index = start;
        const last = self.pattern.len - 1;
        while (index <= haystack.len - self.pattern.len) {
            const tail = haystack[index + last];
            if (self.bytesEqual(tail, self.pattern[last]) and
                self.eqlPattern(haystack[index .. index + self.pattern.len]))
            {
                return index;
            }
            index += self.skip[tail];
        }
        return null;
    }

    fn findVectorized(self: *const Literal, haystack: []const u8, start: usize) ?usize {
        const width = 32;
        const Bytes = @Vector(width, u8);
        const first_exact: Bytes = @splat(self.pattern[0]);
        const first_lower: Bytes = @splat(std.ascii.toLower(self.pattern[0]));
        const first_upper: Bytes = @splat(std.ascii.toUpper(self.pattern[0]));
        const last_index = self.pattern.len - 1;
        const last_exact: Bytes = @splat(self.pattern[last_index]);
        const last_lower: Bytes = @splat(std.ascii.toLower(self.pattern[last_index]));
        const last_upper: Bytes = @splat(std.ascii.toUpper(self.pattern[last_index]));
        var index = start;

        while (index + width + last_index <= haystack.len) : (index += width) {
            const heads: *align(1) const Bytes = @ptrCast(haystack[index..].ptr);
            const first_exact_mask: u32 = @bitCast(heads.* == first_exact);
            const first_lower_mask: u32 = @bitCast(heads.* == first_lower);
            const first_upper_mask: u32 = @bitCast(heads.* == first_upper);
            var candidates = if (self.ignore_case)
                first_lower_mask | first_upper_mask
            else
                first_exact_mask;
            if (last_index != 0) {
                const tails: *align(1) const Bytes = @ptrCast(haystack[index + last_index ..].ptr);
                const last_exact_mask: u32 = @bitCast(tails.* == last_exact);
                const last_lower_mask: u32 = @bitCast(tails.* == last_lower);
                const last_upper_mask: u32 = @bitCast(tails.* == last_upper);
                candidates &= if (self.ignore_case)
                    last_lower_mask | last_upper_mask
                else
                    last_exact_mask;
            }
            while (candidates != 0) {
                const offset: usize = @intCast(@ctz(candidates));
                const candidate = index + offset;
                if (self.eqlPattern(haystack[candidate .. candidate + self.pattern.len])) {
                    return candidate;
                }
                candidates &= candidates - 1;
            }
        }
        if (!self.ignore_case) return std.mem.findPosLinear(u8, haystack, index, self.pattern);
        return self.findScalarIgnoreCase(haystack, index);
    }

    pub fn eqlPattern(self: *const Literal, candidate: []const u8) bool {
        if (candidate.len != self.pattern.len) return false;
        if (!self.ignore_case) return std.mem.eql(u8, candidate, self.pattern);
        for (candidate, self.pattern) |actual, expected| {
            if (!bytesEqualIgnoreCase(actual, expected)) return false;
        }
        return true;
    }

    fn findScalarIgnoreCase(self: *const Literal, haystack: []const u8, start: usize) ?usize {
        var index = start;
        while (index <= haystack.len - self.pattern.len) : (index += 1) {
            if (self.bytesEqual(haystack[index], self.pattern[0]) and
                self.eqlPattern(haystack[index .. index + self.pattern.len])) return index;
        }
        return null;
    }

    fn bytesEqual(self: *const Literal, actual: u8, expected: u8) bool {
        return actual == expected or (self.ignore_case and bytesEqualIgnoreCase(actual, expected));
    }
};

fn bytesEqualIgnoreCase(left: u8, right: u8) bool {
    return std.ascii.toLower(left) == std.ascii.toLower(right);
}

fn isWordByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn hasWordBoundaries(line: []const u8, start: usize, len: usize) bool {
    const left = start == 0 or !isWordByte(line[start - 1]);
    const end = start + len;
    const right = end == line.len or !isWordByte(line[end]);
    return left and right;
}

fn isLiteralPattern(pattern: []const u8, mode: options.Mode) bool {
    if (mode == .fixed) return true;
    for (pattern) |byte| {
        // BRE/ERE escaping changes the bytes that are matched. Keeping every
        // escaped pattern on the regex path avoids a fast-path semantic split.
        if (byte == '\\') return false;
        if (byte == '[') return false;
        if (byte == '.' or byte == '^' or byte == '$' or byte == '*') return false;
        if ((mode == .extended or mode == .perl) and
            (byte == '(' or byte == ')' or byte == '{' or byte == '}' or
                byte == '+' or byte == '?' or byte == '|')) return false;
    }
    return true;
}

fn posixPatternIsPcreCompatible(pattern: []const u8, mode: options.Mode) bool {
    if (mode == .fixed or mode == .perl) return true;
    var in_class = false;
    var class_prefix: u2 = 0;
    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        const byte = pattern[index];
        if (in_class) {
            if (byte == '\\') return false;
            if (class_prefix == 0 and byte == '^') {
                class_prefix = 1;
                continue;
            }
            if (class_prefix < 2 and byte == ']') {
                class_prefix = 2;
                continue;
            }
            if (byte == ']' and isPosixBracketSubexpressionEnd(pattern, index)) continue;
            if (byte == ']') {
                in_class = false;
                continue;
            }
            class_prefix = 2;
            if (byte == '[' and index + 1 < pattern.len and
                (pattern[index + 1] == '.' or pattern[index + 1] == '=')) return false;
            continue;
        }
        if (byte == '[') {
            in_class = true;
            class_prefix = 0;
            continue;
        }
        if (byte == '\\' and index + 1 < pattern.len) {
            const next = pattern[index + 1];
            if (mode == .basic and next == '{') {
                if (index + 2 < pattern.len and pattern[index + 2] == ',') return false;
                if (posixIntervalExceedsMax(pattern, index + 2, true)) return false;
            }
            if (next == '<' or next == '>') return false;
            if (std.ascii.isAlphanumeric(next) and
                !(next >= '1' and next <= '9') and
                std.mem.findScalar(u8, "bBwsS", next) == null) return false;
            index += 1;
            continue;
        }
        if (mode == .extended) {
            if (byte == '{') {
                if (index + 1 < pattern.len and pattern[index + 1] == ',') return false;
                if (posixIntervalExceedsMax(pattern, index + 1, false)) return false;
            }
            if (byte == '(' and index + 1 < pattern.len and
                (pattern[index + 1] == '?' or pattern[index + 1] == '*')) return false;
            if ((byte == '*' or byte == '+' or byte == '?') and index + 1 < pattern.len and
                (pattern[index + 1] == '?' or pattern[index + 1] == '+')) return false;
        }
    }
    return true;
}

fn posixPatternNeedsLongestEngine(pattern: []const u8, mode: options.Mode) bool {
    if (mode == .fixed or mode == .perl) return false;
    var in_class = false;
    var class_prefix: u2 = 0;
    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        const byte = pattern[index];
        if (in_class) {
            if (class_prefix == 0 and byte == '^') {
                class_prefix = 1;
                continue;
            }
            if (class_prefix < 2 and byte == ']') {
                class_prefix = 2;
                continue;
            }
            if (byte == ']' and isPosixBracketSubexpressionEnd(pattern, index)) continue;
            if (byte == ']') in_class = false else class_prefix = 2;
            continue;
        }
        if (byte == '[') {
            in_class = true;
            class_prefix = 0;
            continue;
        }
        if (byte == '\\' and index + 1 < pattern.len) {
            if (mode == .basic and pattern[index + 1] == '|') return true;
            index += 1;
            continue;
        }
        if (mode == .extended and byte == '|') return true;
    }
    return false;
}

fn posixIntervalExceedsMax(pattern: []const u8, start: usize, escaped_close: bool) bool {
    const max_repeat: usize = 32767;
    var value: usize = 0;
    var index = start;
    while (index < pattern.len) : (index += 1) {
        const byte = pattern[index];
        if (std.ascii.isDigit(byte)) {
            const digit: usize = byte - '0';
            if (value > (max_repeat - digit) / 10) return true;
            value = value * 10 + digit;
            continue;
        }
        if (byte == ',') {
            value = 0;
            continue;
        }
        if ((!escaped_close and byte == '}') or
            (escaped_close and byte == '\\' and index + 1 < pattern.len and pattern[index + 1] == '}'))
        {
            return false;
        }
        return false;
    }
    return false;
}

fn isPosixBracketSubexpressionEnd(pattern: []const u8, index: usize) bool {
    if (index == 0) return false;
    return pattern[index - 1] == ':' or pattern[index - 1] == '.' or pattern[index - 1] == '=';
}

fn requiredLiteralEre(pattern: []const u8) ?[]const u8 {
    var depth: usize = 0;
    var in_class = false;
    var class_prefix: u2 = 0;
    var run_start: ?usize = null;
    var best: ?[]const u8 = null;

    for (pattern, 0..) |byte, index| {
        if (in_class) {
            if (byte == '\\') return null;
            if (class_prefix < 2 and byte == '^' and class_prefix == 0) {
                class_prefix = 1;
                continue;
            }
            if (class_prefix < 2 and byte == ']') {
                class_prefix = 2;
                continue;
            }
            if (byte == ']' and isPosixBracketSubexpressionEnd(pattern, index)) continue;
            if (byte == ']') {
                in_class = false;
            } else {
                class_prefix = 2;
            }
            continue;
        }
        if (byte == '\\') return null;
        if (byte == '[') {
            finishLiteralRun(pattern, run_start, index, &best);
            run_start = null;
            in_class = true;
            class_prefix = 0;
            continue;
        }
        if (byte == '(') {
            finishLiteralRun(pattern, run_start, index, &best);
            run_start = null;
            if (index + 1 < pattern.len and (pattern[index + 1] == '?' or pattern[index + 1] == '*')) return null;
            depth += 1;
            continue;
        }
        if (byte == ')') {
            finishLiteralRun(pattern, run_start, index, &best);
            run_start = null;
            if (depth == 0) return null;
            depth -= 1;
            continue;
        }
        if (byte == '|' and depth == 0) return null;
        if (depth != 0) continue;

        if (byte == '{') return null;
        if (byte == '*' or byte == '+' or byte == '?') {
            // A quantifier modifies the preceding atom. Discarding its entire
            // literal run is conservative and avoids an optional prefilter.
            run_start = null;
            continue;
        }
        if (byte == '.' or byte == '^' or byte == '$' or byte == '}' or byte == '|' or byte == ']') {
            finishLiteralRun(pattern, run_start, index, &best);
            run_start = null;
            continue;
        }
        if (run_start == null) run_start = index;
    }
    if (in_class or depth != 0) return null;
    finishLiteralRun(pattern, run_start, pattern.len, &best);
    return best;
}

fn finishLiteralRun(
    pattern: []const u8,
    run_start: ?usize,
    end: usize,
    best: *?[]const u8,
) void {
    const start = run_start orelse return;
    const candidate = pattern[start..end];
    if (candidate.len == 0) return;
    if (best.* == null or candidate.len > best.*.?.len) best.* = candidate;
}

fn translatePattern(
    allocator: std.mem.Allocator,
    pattern: []const u8,
    mode: options.Mode,
    line_regexp: bool,
    word_regexp: bool,
) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    if (line_regexp) try result.appendSlice(allocator, "^(?:");
    if (word_regexp) try result.appendSlice(allocator, "(?<![[:alnum:]_])(?:");

    if (mode == .fixed) {
        for (pattern) |byte| {
            if (std.mem.findScalar(u8, "\\.^$|?*+()[]{}", byte) != null)
                try result.append(allocator, '\\');
            try result.append(allocator, byte);
        }
    } else if (mode == .extended or mode == .perl) {
        try result.appendSlice(allocator, pattern);
    } else {
        var index: usize = 0;
        var in_class = false;
        while (index < pattern.len) : (index += 1) {
            const byte = pattern[index];
            if (byte == '[' and !in_class) {
                in_class = true;
                try result.append(allocator, byte);
                continue;
            }
            if (byte == ']' and in_class and isPosixBracketSubexpressionEnd(pattern, index)) {
                try result.append(allocator, byte);
                continue;
            }
            if (byte == ']' and in_class) {
                in_class = false;
                try result.append(allocator, byte);
                continue;
            }
            if (!in_class and byte == '\\' and index + 1 < pattern.len) {
                const next = pattern[index + 1];
                if (next == '(' or next == ')' or next == '{' or next == '}' or
                    next == '+' or next == '?' or next == '|')
                {
                    try result.append(allocator, next);
                    index += 1;
                    continue;
                }
                try result.append(allocator, byte);
                try result.append(allocator, next);
                index += 1;
                continue;
            }
            if (!in_class and (byte == '(' or byte == ')' or byte == '{' or byte == '}' or
                byte == '+' or byte == '?' or byte == '|'))
            {
                try result.append(allocator, '\\');
            }
            try result.append(allocator, byte);
        }
    }

    if (word_regexp) try result.appendSlice(allocator, ")(?![[:alnum:]_])");
    if (line_regexp) try result.appendSlice(allocator, ")$");
    return result.toOwnedSlice(allocator);
}

test "literal BMH finds matches" {
    const literal = Literal.init("needle", false, false, false);
    try std.testing.expectEqual(60, literal.find("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxneedle!", 0));
    try std.testing.expectEqual(null, literal.find("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", 0));
}

test "vectorized literal search handles block boundaries" {
    const literal = Literal.init("needle", false, false, false);
    var haystack: [160]u8 = @splat('x');
    @memcpy(haystack[95..101], "needle");
    try std.testing.expectEqual(95, literal.find(&haystack, 0));
    try std.testing.expectEqual(95, literal.find(&haystack, 64));
    try std.testing.expectEqual(null, literal.find(&haystack, 96));
}

test "literal line and word matching" {
    const line = Literal.init("abc", false, true, false);
    try std.testing.expect(line.matches("abc"));
    try std.testing.expect(!line.matches("xabc"));
    const word = Literal.init("abc", false, false, true);
    try std.testing.expect(word.matches("x abc!"));
    try std.testing.expect(!word.matches("xabc_"));
}

test "ASCII case-insensitive literal search" {
    const literal = Literal.init("NeEdLe", true, false, false);
    try std.testing.expectEqual(64, literal.find("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxNEEDLE", 0));
    try std.testing.expect(literal.matches("a needle here"));
    try std.testing.expect(!literal.matches("no match"));
}

test "BRE literal detection" {
    try std.testing.expect(isLiteralPattern("ordinary text", .basic));
    try std.testing.expect(!isLiteralPattern("a\\+", .basic));
    try std.testing.expect(!isLiteralPattern("a\\.", .basic));
    try std.testing.expect(!isLiteralPattern("a.*b", .basic));
    try std.testing.expect(isLiteralPattern("a+b", .basic));
    try std.testing.expect(!isLiteralPattern("a+b", .extended));
}

test "BRE translation" {
    const translated = try translatePattern(std.testing.allocator, "a\\(b\\|c\\)\\+", .basic, false, false);
    defer std.testing.allocator.free(translated);
    try std.testing.expectEqualStrings("a(b|c)+", translated);
}

test "BRE translation keeps POSIX bracket subexpressions nested" {
    const translated = try translatePattern(
        std.testing.allocator,
        "[[:alpha:]|]",
        .basic,
        false,
        false,
    );
    defer std.testing.allocator.free(translated);
    try std.testing.expectEqualStrings("[[:alpha:]|]", translated);
}

test "POSIX patterns with GNU or PCRE-only syntax use the POSIX engine" {
    try std.testing.expect(!posixPatternIsPcreCompatible("\\<word\\>", .basic));
    try std.testing.expect(!posixPatternIsPcreCompatible("\\q", .extended));
    try std.testing.expect(!posixPatternIsPcreCompatible("a{,2}", .extended));
    try std.testing.expect(!posixPatternIsPcreCompatible("(?=a)", .extended));
    try std.testing.expect(!posixPatternIsPcreCompatible("[\\d]", .extended));
    try std.testing.expect(posixPatternIsPcreCompatible("a{32767}", .extended));
    try std.testing.expect(!posixPatternIsPcreCompatible("a{32768}", .extended));
    try std.testing.expect(!posixPatternIsPcreCompatible("a\\{1,32768\\}", .basic));
    try std.testing.expect(posixPatternIsPcreCompatible("(foo|bar)[[:digit:]]+", .extended));
}

test "POSIX longest-match engine is reserved for alternation" {
    try std.testing.expect(!posixPatternNeedsLongestEngine("[a-z]+-needle", .extended));
    try std.testing.expect(posixPatternNeedsLongestEngine("(a|ab)c?", .extended));
    try std.testing.expect(posixPatternNeedsLongestEngine("\\(a\\|ab\\)c\\?", .basic));
    try std.testing.expect(!posixPatternNeedsLongestEngine("[a|b]+", .extended));
}

test "ERE required literal extraction is conservative" {
    try std.testing.expectEqualStrings("-needle", requiredLiteralEre("[a-z]+-needle").?);
    try std.testing.expectEqualStrings("status=", requiredLiteralEre("status=(200|500)").?);
    try std.testing.expectEqualStrings("required", requiredLiteralEre("(foo|bar)required").?);
    try std.testing.expectEqualStrings("needle", requiredLiteralEre("[]a]needle").?);
    try std.testing.expectEqualStrings("needle", requiredLiteralEre("[^]]needle").?);
    try std.testing.expectEqualStrings("needle", requiredLiteralEre("[[:alpha:]_]needle").?);
    try std.testing.expectEqual(null, requiredLiteralEre("^[ab][[:alpha:]_]$"));
    try std.testing.expectEqualStrings("bar", requiredLiteralEre("foo?bar").?);
    try std.testing.expectEqual(null, requiredLiteralEre("foo|bar"));
    try std.testing.expectEqual(null, requiredLiteralEre("foo{0}bar"));
    try std.testing.expectEqual(null, requiredLiteralEre("(?i)needle"));
    try std.testing.expectEqual(null, requiredLiteralEre("foo\\.bar"));
}

test "pure ERE literal alternation promotion" {
    var alternation = (try LiteralAlternation.init(
        std.testing.allocator,
        "error|warning|fatal",
        false,
        false,
        false,
    )).?;
    defer alternation.deinit();
    try std.testing.expect(alternation.matches("a warning here"));
    try std.testing.expect(!alternation.matches("all clear"));
    const longest = alternation.find("fatal warning", 0).?;
    try std.testing.expectEqual(0, longest.start);
    try std.testing.expectEqual(5, longest.end);
    try std.testing.expectEqual(
        null,
        try LiteralAlternation.init(std.testing.allocator, "error|warn.*", false, false, false),
    );
}

test "PCRE2 worker owns independent match data" {
    var error_buffer: [256]u8 = @splat(0);
    var matcher = try Matcher.init(
        std.testing.allocator,
        "[[:digit:]]{3}",
        .extended,
        false,
        false,
        false,
        false,
        false,
        &error_buffer,
    );
    defer matcher.deinit();
    switch (matcher) {
        .regex => |*regex| {
            var worker = regex.createWorker() orelse return error.OutOfMemory;
            defer worker.deinit();
            try std.testing.expect(worker.matches("status=500"));
            try std.testing.expect(!worker.matches("status=ok"));
        },
        else => return error.TestUnexpectedResult,
    }
}
