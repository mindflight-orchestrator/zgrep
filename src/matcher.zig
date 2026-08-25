const std = @import("std");
const c = @import("pcre2");
const options = @import("options.zig");

pub const Match = struct {
    start: usize,
    end: usize,
};

pub fn initializeLocale() bool {
    return c.zg_initialize_locale();
}

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
        const utf8_locale = c.zg_locale_is_utf8();
        const locale_sensitive_literal = utf8_locale and (ignore_case or word_regexp);
        const literal_pattern = isLiteralPattern(pattern, mode);
        if (mode == .fixed and !locale_sensitive_literal) {
            return .{ .literal = Literal.init(pattern, ignore_case, line_regexp, word_regexp) };
        }
        if (literal_pattern and !locale_sensitive_literal) {
            return .{ .literal = Literal.init(pattern, ignore_case, line_regexp, word_regexp) };
        }
        if (mode == .extended and !locale_sensitive_literal) {
            if (try LiteralAlternation.init(
                allocator,
                pattern,
                ignore_case,
                line_regexp,
                word_regexp,
            )) |alternation| return .{ .alternation = alternation };
        }

        const fixed_posix = utf8_locale and mode == .fixed;
        const locale_posix = utf8_locale and mode != .perl;
        const ascii_pattern = isAscii(pattern);
        const translated = try translatePattern(
            allocator,
            pattern,
            mode,
            line_regexp and !fixed_posix,
            word_regexp and !fixed_posix,
        );
        defer allocator.free(translated);
        const pcre_compatible = posixPatternIsPcreCompatible(pattern, mode) and
            (!locale_posix or ascii_pattern);
        const standard_ascii_classes = c.zg_locale_has_standard_ascii_classes();
        const locale_class_run = if (locale_posix and pcre_compatible and standard_ascii_classes)
            LocaleClassRun.init(pattern, mode, ignore_case, line_regexp, word_regexp)
        else
            null;
        var ascii_alternation = if (locale_posix and ascii_pattern and mode == .extended)
            try LiteralAlternation.init(
                allocator,
                pattern,
                ignore_case,
                line_regexp,
                word_regexp,
            )
        else
            null;
        errdefer if (ascii_alternation) |*alternation| alternation.deinit();
        const ascii_witness = locale_class_run == null and locale_posix and pcre_compatible and
            standard_ascii_classes and
            posixPatternHasAsciiWitness(pattern, mode, ignore_case, word_regexp);
        const ascii_class_sequence = if (locale_class_run == null and pcre_compatible and
            standard_ascii_classes)
            try AsciiClassSequence.init(
                allocator,
                pattern,
                mode,
                ignore_case,
                line_regexp,
                word_regexp,
            )
        else
            null;
        errdefer if (ascii_class_sequence) |sequence| sequence.deinit();
        const regex = c.zg_regex_compile(
            translated.ptr,
            translated.len,
            if (fixed_posix) translated.ptr else pattern.ptr,
            if (fixed_posix) translated.len else pattern.len,
            if (fixed_posix) c.ZG_REGEX_SYNTAX_EXTENDED else switch (mode) {
                .basic => c.ZG_REGEX_SYNTAX_BASIC,
                .extended => c.ZG_REGEX_SYNTAX_EXTENDED,
                .fixed, .perl => c.ZG_REGEX_SYNTAX_PERL,
            },
            pcre_compatible,
            ascii_witness,
            locale_posix or (only_matching and posixPatternNeedsLongestEngine(pattern, mode)),
            ignore_case,
            dot_matches_newline,
            line_regexp,
            word_regexp,
            error_buffer.ptr,
            error_buffer.len,
        ) orelse return error.InvalidRegex;
        const prefilter = if (!ignore_case)
            if (fixed_posix)
                Literal.init(pattern, false, false, false)
            else if (mode == .extended)
                if (requiredLiteralEre(pattern)) |literal| Literal.init(literal, false, false, false) else null
            else
                null
        else
            null;
        const uses_pcre = c.zg_regex_uses_pcre(regex);
        const value: Regex = .{
            .compiled = regex,
            .prefilter = prefilter,
            .ascii_pcre = locale_posix and mode != .fixed and ascii_pattern and uses_pcre,
            .ascii_pcre_longest = posixPatternNeedsLongestEngine(pattern, mode),
            .ascii_witness = ascii_witness and uses_pcre,
            .ascii_class_sequence = ascii_class_sequence,
            .locale_class_run = locale_class_run,
            .ascii_alternation = ascii_alternation,
            .ascii_literal = if (locale_posix and ascii_pattern and (fixed_posix or literal_pattern))
                Literal.init(pattern, ignore_case, line_regexp, word_regexp)
            else
                null,
        };
        return if (!locale_posix and uses_pcre)
            .{ .regex = value }
        else
            .{ .posix_regex = value };
    }

    pub fn deinit(self: *Matcher) void {
        switch (self.*) {
            .literal => {},
            .alternation => |*alternation| alternation.deinit(),
            .regex => |*regex| regex.deinit(),
            .posix_regex => |*regex| regex.deinit(),
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
            .posix_regex => |*regex| regex.findPosix(line, start),
        };
    }

    pub fn benefitsFromLargeFileListParallelism(self: *const Matcher) bool {
        return switch (self.*) {
            .regex => true,
            .posix_regex => |*regex| regex.ascii_literal == null and
                regex.ascii_alternation == null,
            else => false,
        };
    }

    pub fn benefitsFromExtraRecursiveWorkers(self: *const Matcher) bool {
        return switch (self.*) {
            .regex, .posix_regex => |*regex| regex.prefilter == null and
                regex.ascii_literal == null and regex.ascii_alternation == null,
            else => false,
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
    ascii_pcre: bool = false,
    ascii_pcre_longest: bool = false,
    ascii_witness: bool = false,
    ascii_class_sequence: ?*AsciiClassSequence = null,
    locale_class_run: ?LocaleClassRun = null,
    ascii_alternation: ?LiteralAlternation = null,
    ascii_literal: ?Literal = null,

    pub fn deinit(self: *Regex) void {
        if (self.ascii_alternation) |*alternation| alternation.deinit();
        if (self.ascii_class_sequence) |sequence| sequence.deinit();
        c.zg_regex_free(self.compiled);
    }

    pub fn matches(self: *const Regex, line: []const u8) bool {
        if (self.prefilter) |*prefilter| {
            if (prefilter.find(line, 0) == null) return false;
        }
        if (self.ascii_class_sequence) |sequence| {
            if (isAscii(line)) return sequence.matches(line);
        }
        return self.matchesFull(line);
    }

    pub fn matchesFull(self: *const Regex, line: []const u8) bool {
        return c.zg_regex_matches(self.compiled, line.ptr, line.len);
    }

    pub fn matchesAsciiClassSequence(self: *const Regex, line: []const u8) ?bool {
        const sequence = self.ascii_class_sequence orelse return null;
        return sequence.matches(line);
    }

    pub fn matchesPosix(self: *const Regex, line: []const u8) bool {
        if (self.prefilter) |*prefilter| {
            if (prefilter.find(line, 0) == null) return false;
        }
        if (self.locale_class_run) |class_run| return class_run.matches(line);
        if (self.ascii_class_sequence) |sequence| {
            if (isAscii(line)) return sequence.matches(line);
        }
        if (self.ascii_alternation) |*alternation| {
            if (isAscii(line)) return alternation.matches(line);
        }
        if (self.ascii_literal) |*literal| {
            if (isAscii(line)) return literal.matches(line);
            if (localeAsciiCaseLiteralEligible(literal)) {
                if (literal.matches(line)) return true;
                return localeAsciiCaseLiteralMatches(literal, line);
            }
        } else if (self.ascii_pcre and isAscii(line)) {
            return c.zg_regex_matches(self.compiled, line.ptr, line.len);
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

    pub fn findPosix(self: *const Regex, line: []const u8, start: usize) ?Match {
        if (start > line.len) return null;
        if ((self.ascii_pcre or self.ascii_literal != null) and isAscii(line)) {
            if (self.ascii_literal) |*literal| return literal.findMatch(line, start);
            if (self.prefilter) |*prefilter| {
                if (prefilter.find(line, start) == null) return null;
            }
            var match_start: usize = undefined;
            var match_end: usize = undefined;
            const found = if (self.ascii_pcre_longest)
                c.zg_regex_find(
                    self.compiled,
                    line.ptr,
                    line.len,
                    start,
                    &match_start,
                    &match_end,
                )
            else
                c.zg_regex_pcre_find(
                    self.compiled,
                    line.ptr,
                    line.len,
                    start,
                    &match_start,
                    &match_end,
                );
            if (!found) return null;
            return .{ .start = match_start, .end = match_end };
        }
        return self.find(line, start);
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

const LocaleClassRun = struct {
    masks: [2]u64 = @splat(0),
    classes: u32 = 0,
    minimum: usize,

    fn init(
        pattern: []const u8,
        mode: options.Mode,
        ignore_case: bool,
        line_regexp: bool,
        word_regexp: bool,
    ) ?LocaleClassRun {
        if (mode != .extended or ignore_case or line_regexp or word_regexp or pattern.len < 5 or
            pattern[0] != '[' or !isAscii(pattern)) return null;

        var result: LocaleClassRun = .{ .minimum = 0 };
        var index: usize = 1;
        if (pattern[index] == '^') return null;
        if (pattern[index] == ']') {
            result.add(']');
            index += 1;
        }

        var closed = false;
        while (index < pattern.len) {
            const byte = pattern[index];
            if (byte == ']') {
                closed = true;
                index += 1;
                break;
            }
            if (byte == 0 or byte == '\n' or byte == '\\' or byte == '-') return null;
            if (byte == '[') {
                if (index + 2 >= pattern.len or pattern[index + 1] != ':') return null;
                const name_start = index + 2;
                var name_end = name_start;
                while (name_end + 1 < pattern.len and
                    !(pattern[name_end] == ':' and pattern[name_end + 1] == ']'))
                {
                    name_end += 1;
                }
                if (name_end + 1 >= pattern.len or
                    !result.addClass(pattern[name_start..name_end])) return null;
                index = name_end + 2;
                continue;
            }
            result.add(byte);
            index += 1;
        }
        if (!closed or (result.masks[0] == 0 and result.masks[1] == 0) or
            index >= pattern.len or pattern[index] != '{') return null;
        index += 1;
        const number_start = index;
        var minimum: usize = 0;
        while (index < pattern.len and std.ascii.isDigit(pattern[index])) : (index += 1) {
            const digit: usize = pattern[index] - '0';
            if (minimum > (32767 - digit) / 10) return null;
            minimum = minimum * 10 + digit;
        }
        if (index == number_start or index + 1 != pattern.len or pattern[index] != '}') return null;
        result.minimum = minimum;
        return result;
    }

    fn matches(self: LocaleClassRun, buffer: []const u8) bool {
        return c.zg_locale_class_run_matches(
            buffer.ptr,
            buffer.len,
            self.masks[0],
            self.masks[1],
            self.classes,
            self.minimum,
        );
    }

    fn add(self: *LocaleClassRun, byte: u8) void {
        if (byte >= 128) return;
        self.masks[byte >> 6] |= @as(u64, 1) << @intCast(byte & 63);
    }

    fn addRange(self: *LocaleClassRun, first: u8, last: u8) void {
        var byte = first;
        while (byte <= last) : (byte += 1) self.add(byte);
    }

    fn addClass(self: *LocaleClassRun, name: []const u8) bool {
        if (std.mem.eql(u8, name, "alnum") or std.mem.eql(u8, name, "alpha")) {
            self.classes |= if (std.mem.eql(u8, name, "alnum"))
                c.ZG_LOCALE_CLASS_ALNUM
            else
                c.ZG_LOCALE_CLASS_ALPHA;
            self.addRange('A', 'Z');
            self.addRange('a', 'z');
            if (std.mem.eql(u8, name, "alnum")) self.addRange('0', '9');
        } else if (std.mem.eql(u8, name, "blank")) {
            self.classes |= c.ZG_LOCALE_CLASS_BLANK;
            self.add('\t');
            self.add(' ');
        } else if (std.mem.eql(u8, name, "digit")) {
            self.classes |= c.ZG_LOCALE_CLASS_DIGIT;
            self.addRange('0', '9');
        } else if (std.mem.eql(u8, name, "graph") or std.mem.eql(u8, name, "print")) {
            self.classes |= if (std.mem.eql(u8, name, "graph"))
                c.ZG_LOCALE_CLASS_GRAPH
            else
                c.ZG_LOCALE_CLASS_PRINT;
            self.addRange(if (std.mem.eql(u8, name, "graph")) 33 else 32, 126);
        } else if (std.mem.eql(u8, name, "lower")) {
            self.classes |= c.ZG_LOCALE_CLASS_LOWER;
            self.addRange('a', 'z');
        } else if (std.mem.eql(u8, name, "punct")) {
            self.classes |= c.ZG_LOCALE_CLASS_PUNCT;
            var byte: u8 = 33;
            while (byte <= 126) : (byte += 1) {
                if (!std.ascii.isAlphanumeric(byte)) self.add(byte);
            }
        } else if (std.mem.eql(u8, name, "upper")) {
            self.classes |= c.ZG_LOCALE_CLASS_UPPER;
            self.addRange('A', 'Z');
        } else if (std.mem.eql(u8, name, "xdigit")) {
            self.classes |= c.ZG_LOCALE_CLASS_XDIGIT;
            self.addRange('0', '9');
            self.addRange('A', 'F');
            self.addRange('a', 'f');
        } else {
            return false;
        }
        return true;
    }
};

const AsciiClassSequence = struct {
    allocator: std.mem.Allocator,
    masks: [128]u64,
    repeat_mask: u64,
    accept_mask: u64,

    fn init(
        allocator: std.mem.Allocator,
        pattern: []const u8,
        mode: options.Mode,
        ignore_case: bool,
        line_regexp: bool,
        word_regexp: bool,
    ) !?*AsciiClassSequence {
        if (mode != .extended or ignore_case or line_regexp or word_regexp or
            pattern.len == 0 or !isAscii(pattern)) return null;

        var masks: [128]u64 = @splat(0);
        var repeat_mask: u64 = 0;
        var state_count: usize = 0;
        var atom_count: usize = 0;
        var index: usize = 0;
        while (index < pattern.len) {
            const parsed = parseAsciiClass(pattern, index) orelse return null;
            index = parsed.end;
            atom_count += 1;

            var repetitions: usize = 1;
            var repeats_last = false;
            if (index < pattern.len and pattern[index] == '+') {
                repeats_last = true;
                index += 1;
            } else if (index < pattern.len and pattern[index] == '{') {
                index += 1;
                const digits_start = index;
                repetitions = 0;
                while (index < pattern.len and std.ascii.isDigit(pattern[index])) : (index += 1) {
                    const digit: usize = pattern[index] - '0';
                    if (repetitions > (64 - digit) / 10) return null;
                    repetitions = repetitions * 10 + digit;
                }
                if (index == digits_start or repetitions == 0 or index >= pattern.len or
                    pattern[index] != '}') return null;
                index += 1;
            }
            if (state_count + repetitions > 64) return null;
            for (0..repetitions) |_| {
                const state_bit = @as(u64, 1) << @intCast(state_count);
                for (0..128) |byte| {
                    if (parsed.contains(@intCast(byte))) masks[byte] |= state_bit;
                }
                state_count += 1;
            }
            if (repeats_last) repeat_mask |= @as(u64, 1) << @intCast(state_count - 1);
        }
        if (atom_count < 2 or state_count == 0) return null;

        const result = try allocator.create(AsciiClassSequence);
        result.* = .{
            .allocator = allocator,
            .masks = masks,
            .repeat_mask = repeat_mask,
            .accept_mask = @as(u64, 1) << @intCast(state_count - 1),
        };
        return result;
    }

    fn deinit(self: *AsciiClassSequence) void {
        self.allocator.destroy(self);
    }

    fn matches(self: *const AsciiClassSequence, record: []const u8) bool {
        var active: u64 = 0;
        for (record) |byte| {
            if (byte >= 128) return false;
            active = ((active << 1) | 1 | (active & self.repeat_mask)) & self.masks[byte];
            if (active & self.accept_mask != 0) return true;
        }
        return false;
    }
};

const ParsedAsciiClass = struct {
    masks: [2]u64 = @splat(0),
    end: usize,

    fn add(self: *ParsedAsciiClass, byte: u8) void {
        if (byte >= 128) return;
        self.masks[byte >> 6] |= @as(u64, 1) << @intCast(byte & 63);
    }

    fn addRange(self: *ParsedAsciiClass, first: u8, last: u8) void {
        var byte: usize = first;
        while (byte <= last) : (byte += 1) self.add(@intCast(byte));
    }

    fn contains(self: ParsedAsciiClass, byte: u8) bool {
        return self.masks[byte >> 6] & (@as(u64, 1) << @intCast(byte & 63)) != 0;
    }
};

fn parseAsciiClass(pattern: []const u8, start: usize) ?ParsedAsciiClass {
    if (start >= pattern.len or pattern[start] != '[' or start + 1 >= pattern.len or
        pattern[start + 1] == '^' or pattern[start + 1] == ']') return null;
    var result: ParsedAsciiClass = .{ .end = 0 };
    var has_member = false;
    var index = start + 1;
    while (index < pattern.len) {
        const byte = pattern[index];
        if (byte == ']') {
            if (!has_member) return null;
            result.end = index + 1;
            return result;
        }
        if (byte == '\\' or byte == '-' or byte >= 128) return null;
        if (byte == '[') {
            if (index + 1 >= pattern.len or pattern[index + 1] != ':') return null;
            const name_start = index + 2;
            var name_end = name_start;
            while (name_end + 1 < pattern.len and
                !(pattern[name_end] == ':' and pattern[name_end + 1] == ']'))
            {
                name_end += 1;
            }
            if (name_end + 1 >= pattern.len or
                !addAsciiPosixClass(&result, pattern[name_start..name_end])) return null;
            has_member = true;
            index = name_end + 2;
            continue;
        }
        result.add(byte);
        has_member = true;
        index += 1;
    }
    return null;
}

fn addAsciiPosixClass(result: *ParsedAsciiClass, name: []const u8) bool {
    if (std.mem.eql(u8, name, "alnum") or std.mem.eql(u8, name, "alpha")) {
        result.addRange('A', 'Z');
        result.addRange('a', 'z');
        if (std.mem.eql(u8, name, "alnum")) result.addRange('0', '9');
    } else if (std.mem.eql(u8, name, "blank")) {
        result.add('\t');
        result.add(' ');
    } else if (std.mem.eql(u8, name, "cntrl")) {
        result.addRange(0, 31);
        result.add(127);
    } else if (std.mem.eql(u8, name, "digit")) {
        result.addRange('0', '9');
    } else if (std.mem.eql(u8, name, "graph") or std.mem.eql(u8, name, "print")) {
        result.addRange(if (std.mem.eql(u8, name, "graph")) 33 else 32, 126);
    } else if (std.mem.eql(u8, name, "lower")) {
        result.addRange('a', 'z');
    } else if (std.mem.eql(u8, name, "punct")) {
        var byte: u8 = 33;
        while (byte <= 126) : (byte += 1) {
            if (!std.ascii.isAlphanumeric(byte)) result.add(byte);
        }
    } else if (std.mem.eql(u8, name, "space")) {
        result.addRange('\t', '\r');
        result.add(' ');
    } else if (std.mem.eql(u8, name, "upper")) {
        result.addRange('A', 'Z');
    } else if (std.mem.eql(u8, name, "xdigit")) {
        result.addRange('0', '9');
        result.addRange('A', 'F');
        result.addRange('a', 'f');
    } else {
        return false;
    }
    return true;
}

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
        return self.matchesImpl(record, false);
    }

    pub fn benefitsFromKnownAscii(self: *const ThreadMatcher) bool {
        return switch (self.*) {
            .regex => |*regex| regex.value.ascii_class_sequence != null,
            .posix_regex => |*regex| regex.value.ascii_pcre or
                regex.value.ascii_alternation != null or
                regex.value.ascii_literal != null or
                regex.value.ascii_class_sequence != null,
            else => false,
        };
    }

    pub fn matchesKnownAscii(self: *const ThreadMatcher, record: []const u8) bool {
        return self.matchesImpl(record, true);
    }

    fn matchesImpl(
        self: *const ThreadMatcher,
        record: []const u8,
        known_ascii: bool,
    ) bool {
        return switch (self.*) {
            .literal => |literal| literal.matches(record),
            .alternation => |alternation| alternation.matches(record),
            .regex => |*regex| matches: {
                if (regex.value.prefilter) |*prefilter| {
                    if (prefilter.find(record, 0) == null) break :matches false;
                }
                if (regex.value.ascii_class_sequence) |sequence| {
                    if (known_ascii or isAscii(record)) break :matches sequence.matches(record);
                }
                break :matches regex.worker.matches(record);
            },
            .posix_regex => |*regex| matches: {
                if (regex.value.prefilter) |*prefilter| {
                    if (prefilter.find(record, 0) == null) break :matches false;
                }
                if (regex.value.locale_class_run) |class_run|
                    break :matches class_run.matches(record);
                if (regex.value.ascii_class_sequence) |sequence| {
                    if (known_ascii or isAscii(record)) break :matches sequence.matches(record);
                }
                if (regex.value.ascii_alternation) |*alternation| {
                    if (known_ascii or isAscii(record))
                        break :matches alternation.matches(record);
                }
                if (regex.value.ascii_literal) |*literal| {
                    if (known_ascii or isAscii(record)) break :matches literal.matches(record);
                    if (localeAsciiCaseLiteralEligible(literal)) {
                        if (literal.matches(record)) break :matches true;
                        break :matches localeAsciiCaseLiteralMatches(literal, record);
                    }
                } else if (regex.value.ascii_pcre and (known_ascii or isAscii(record))) {
                    break :matches regex.worker.matches(record);
                }
                break :matches regex.worker.matchesPosix(record);
            },
        };
    }

    pub fn hasAsciiWitness(self: *const ThreadMatcher) bool {
        return switch (self.*) {
            .posix_regex => |*regex| regex.value.ascii_witness,
            else => false,
        };
    }

    pub fn matchesAsciiWitness(self: *const ThreadMatcher, buffer: []const u8) bool {
        return switch (self.*) {
            .posix_regex => |*regex| regex.value.ascii_witness and
                c.zg_regex_worker_ascii_witness_matches(
                    regex.worker.compiled,
                    buffer.ptr,
                    buffer.len,
                ),
            else => false,
        };
    }

    pub fn matchesWholeBufferLiteral(
        self: *const ThreadMatcher,
        buffer: []const u8,
        delimiter: u8,
    ) ?bool {
        return switch (self.*) {
            .literal => |literal| if (literal.whole_line or
                std.mem.findScalar(u8, literal.pattern, delimiter) != null)
                null
            else
                literal.matches(buffer),
            .alternation => |alternation| whole: {
                for (alternation.literals) |literal| {
                    if (literal.whole_line or
                        std.mem.findScalar(u8, literal.pattern, delimiter) != null)
                        break :whole null;
                }
                break :whole alternation.matches(buffer);
            },
            .posix_regex => |*regex| whole: {
                if (regex.value.locale_class_run) |class_run|
                    break :whole class_run.matches(buffer);
                if (regex.value.ascii_alternation) |*alternation| {
                    for (alternation.literals) |literal| {
                        if (literal.whole_line or
                            std.mem.findScalar(u8, literal.pattern, delimiter) != null)
                            break :whole null;
                    }
                    if (isAscii(buffer)) break :whole alternation.matches(buffer);
                }
                if (regex.value.ascii_literal) |literal| {
                    if (std.mem.findScalar(u8, literal.pattern, delimiter) != null)
                        break :whole null;
                    if (!literal.whole_line and !literal.word)
                        break :whole self.matches(buffer);
                    if (!literal.whole_line and literal.word and !literal.ignore_case and
                        literal.pattern.len != 0)
                    {
                        break :whole c.zg_locale_ascii_literal_word_matches(
                            buffer.ptr,
                            buffer.len,
                            literal.pattern.ptr,
                            literal.pattern.len,
                        );
                    }
                }
                break :whole null;
            },
            .regex => null,
        };
    }
};

pub fn isAscii(bytes: []const u8) bool {
    const width = 32;
    const Bytes = @Vector(width, u8);
    const high_bit: Bytes = @splat(0x80);
    const zero: Bytes = @splat(0);
    var index: usize = 0;
    while (index + width <= bytes.len) : (index += width) {
        const chunk: *align(1) const Bytes = @ptrCast(bytes[index..].ptr);
        if (@reduce(.Or, chunk.* & high_bit != zero)) return false;
    }
    for (bytes[index..]) |byte| if (byte & 0x80 != 0) return false;
    return true;
}

fn localeAsciiCaseLiteralEligible(literal: *const Literal) bool {
    return literal.ignore_case and !literal.whole_line and !literal.word and
        c.zg_locale_has_simple_ascii_casefold();
}

fn localeAsciiCaseLiteralMatches(literal: *const Literal, bytes: []const u8) bool {
    return c.zg_locale_ascii_case_literal_matches(
        bytes.ptr,
        bytes.len,
        literal.pattern.ptr,
        literal.pattern.len,
    );
}

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

fn posixPatternHasAsciiWitness(
    pattern: []const u8,
    mode: options.Mode,
    ignore_case: bool,
    word_regexp: bool,
) bool {
    if (mode != .extended or ignore_case or word_regexp or !isAscii(pattern)) return false;

    var in_class = false;
    var class_start: usize = 0;
    var index: usize = 0;
    while (index < pattern.len) {
        const byte = pattern[index];
        if (byte == 0 or byte == '\n') return false;
        if (!in_class) {
            if (byte == '\\' or byte == '.') return false;
            if (byte == '[') {
                if (index + 1 < pattern.len and pattern[index + 1] == '^') return false;
                in_class = true;
                class_start = index + 1;
            }
            index += 1;
            continue;
        }

        if (byte == '\\' or byte == '-') return false;
        if (byte == ']' and index == class_start) {
            index += 1;
            continue;
        }
        if (byte == '[') {
            if (index + 2 >= pattern.len or pattern[index + 1] != ':') return false;
            const name_start = index + 2;
            var name_end = name_start;
            while (name_end + 1 < pattern.len and
                !(pattern[name_end] == ':' and pattern[name_end + 1] == ']'))
            {
                name_end += 1;
            }
            if (name_end + 1 >= pattern.len or
                !asciiWitnessClassName(pattern[name_start..name_end])) return false;
            index = name_end + 2;
            continue;
        }
        if (byte == ']') in_class = false;
        index += 1;
    }
    return !in_class;
}

fn asciiWitnessClassName(name: []const u8) bool {
    const names = [_][]const u8{
        "alnum", "alpha", "blank", "digit",  "graph", "lower",
        "print", "punct", "upper", "xdigit",
    };
    for (names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
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

test "thread literal whole-buffer search preserves record boundaries" {
    const literal = Literal.init("needle", false, false, false);
    const matcher: ThreadMatcher = .{ .literal = &literal };
    try std.testing.expect(matcher.matchesWholeBufferLiteral("prefix\nneedle\nsuffix", '\n').?);
    try std.testing.expect(!matcher.matchesWholeBufferLiteral("prefix nee\ndle suffix", '\n').?);

    const whole_line = Literal.init("needle", false, true, false);
    const whole_line_matcher: ThreadMatcher = .{ .literal = &whole_line };
    try std.testing.expectEqual(null, whole_line_matcher.matchesWholeBufferLiteral("needle\n", '\n'));

    const crossing = Literal.init("nee\ndle", false, false, false);
    const crossing_matcher: ThreadMatcher = .{ .literal = &crossing };
    try std.testing.expectEqual(null, crossing_matcher.matchesWholeBufferLiteral("nee\ndle", '\n'));
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

test "ASCII witness classifier only accepts positive byte-safe EREs" {
    try std.testing.expect(posixPatternHasAsciiWitness(
        "[[:alnum:]_]{12}",
        .extended,
        false,
        false,
    ));
    try std.testing.expect(posixPatternHasAsciiWitness("^[abc_]+$", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("[[:space:]]+", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("[[:cntrl:]]+", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("abc\ndef", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("[[:alnum:]-]+", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("[^[:alpha:]]+", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness(".+", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("foo\\.bar", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("[[:word:]]+", .extended, false, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("[[:alpha:]]+", .extended, true, false));
    try std.testing.expect(!posixPatternHasAsciiWitness("[[:alpha:]]+", .extended, false, true));
    try std.testing.expect(!posixPatternHasAsciiWitness("[[:alpha:]]\\+", .basic, false, false));
}

test "locale class run is exact across record and encoding boundaries" {
    const witness = LocaleClassRun.init(
        "[[:alnum:]_]{12}",
        .extended,
        false,
        false,
        false,
    ).?;
    try std.testing.expect(witness.matches("\xff prefix abcdefghijkl suffix"));
    try std.testing.expect(!witness.matches("abcdef\nghijkl"));
    try std.testing.expect(!witness.matches("abcdef\x00ghijkl"));

    const digits = LocaleClassRun.init("[[:digit:]]{3}", .extended, false, false, false).?;
    try std.testing.expect(digits.matches("status=500"));
    try std.testing.expect(!digits.matches("status=50"));
    try std.testing.expectEqual(
        null,
        LocaleClassRun.init("[^[:alpha:]]{3}", .extended, false, false, false),
    );
    try std.testing.expectEqual(
        null,
        LocaleClassRun.init("[a-z]{3}", .extended, false, false, false),
    );
    try std.testing.expectEqual(
        null,
        LocaleClassRun.init("[[:space:]]{3}", .extended, false, false, false),
    );
}

test "ASCII class sequence uses a bit-parallel record NFA" {
    const allocator = std.testing.allocator;
    const sequence = (try AsciiClassSequence.init(
        allocator,
        "[[:alnum:]_]{2}[[:space:]]+[[:digit:]]{2}",
        .extended,
        false,
        false,
        false,
    )).?;
    defer sequence.deinit();
    try std.testing.expect(sequence.matches("prefix ab \t12 suffix"));
    try std.testing.expect(sequence.matches("a!ab  12"));
    try std.testing.expect(!sequence.matches("a 12"));
    try std.testing.expect(!sequence.matches("ab12"));
    try std.testing.expect(!sequence.matches("ab  1x"));

    try std.testing.expect((try AsciiClassSequence.init(
        allocator,
        "[a-z]{2}[[:digit:]]{2}",
        .extended,
        false,
        false,
        false,
    )) == null);
    try std.testing.expect((try AsciiClassSequence.init(
        allocator,
        "[^a][b]",
        .extended,
        false,
        false,
        false,
    )) == null);
    try std.testing.expect((try AsciiClassSequence.init(
        allocator,
        "[a]{64}[b]",
        .extended,
        false,
        false,
        false,
    )) == null);
    try std.testing.expect((try AsciiClassSequence.init(
        allocator,
        "[a][b]",
        .extended,
        true,
        false,
        false,
    )) == null);
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

test "recursive worker preference distinguishes sparse and compute-heavy matchers" {
    var error_buffer: [256]u8 = @splat(0);
    var sparse = try Matcher.init(
        std.testing.allocator,
        "[A-Z]+_RESUME",
        .extended,
        false,
        false,
        false,
        false,
        false,
        &error_buffer,
    );
    defer sparse.deinit();
    try std.testing.expect(!sparse.benefitsFromExtraRecursiveWorkers());

    var compute_heavy = try Matcher.init(
        std.testing.allocator,
        "[[:alnum:]_]{12}",
        .extended,
        false,
        false,
        false,
        false,
        false,
        &error_buffer,
    );
    defer compute_heavy.deinit();
    try std.testing.expect(compute_heavy.benefitsFromExtraRecursiveWorkers());

    const literal = Matcher{ .literal = .init("needle", false, false, false) };
    try std.testing.expect(!literal.benefitsFromExtraRecursiveWorkers());
}
