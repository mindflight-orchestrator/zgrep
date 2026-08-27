const std = @import("std");
const matcher_mod = @import("matcher.zig");
const options_mod = @import("options.zig");

pub const ColorConfig = struct {
    selected_match: []const u8 = "01;31",
    context_match: []const u8 = "01;31",
    selected_line: []const u8 = "",
    context_line: []const u8 = "",
    filename: []const u8 = "35",
    line_number: []const u8 = "32",
    byte_offset: []const u8 = "32",
    separator: []const u8 = "36",
    erase_line: bool = true,
    reverse: bool = false,

    pub fn fromEnvironment(environ: *const std.process.Environ.Map) ColorConfig {
        var result: ColorConfig = .{};
        if (environ.get("GREP_COLORS")) |specification| {
            result.apply(specification);
        } else if (environ.get("GREP_COLOR")) |match_color| {
            if (match_color.len != 0) {
                result.selected_match = match_color;
                result.context_match = match_color;
            }
        }
        return result;
    }

    fn apply(self: *ColorConfig, specification: []const u8) void {
        var fields = std.mem.splitScalar(u8, specification, ':');
        while (fields.next()) |field| {
            if (std.mem.eql(u8, field, "ne")) {
                self.erase_line = false;
                continue;
            }
            if (std.mem.eql(u8, field, "rv")) {
                self.reverse = true;
                continue;
            }
            const equals = std.mem.findScalar(u8, field, '=') orelse continue;
            const name = field[0..equals];
            const value = field[equals + 1 ..];
            if (std.mem.eql(u8, name, "ms")) {
                self.selected_match = value;
            } else if (std.mem.eql(u8, name, "mc")) {
                self.context_match = value;
            } else if (std.mem.eql(u8, name, "mt")) {
                self.selected_match = value;
                self.context_match = value;
            } else if (std.mem.eql(u8, name, "sl")) {
                self.selected_line = value;
            } else if (std.mem.eql(u8, name, "cx")) {
                self.context_line = value;
            } else if (std.mem.eql(u8, name, "fn")) {
                self.filename = value;
            } else if (std.mem.eql(u8, name, "ln")) {
                self.line_number = value;
            } else if (std.mem.eql(u8, name, "bn")) {
                self.byte_offset = value;
            } else if (std.mem.eql(u8, name, "se")) {
                self.separator = value;
            }
        }
    }
};

pub const ScanOptions = struct {
    invert: bool,
    count: bool,
    line_number: bool,
    show_filename: bool,
    quiet: bool,
    list_files: ?bool,
    max_count: ?usize,
    byte_offset: bool,
    only_matching: bool,
    before_context: usize = 0,
    after_context: usize = 0,
    context_separator: ?[]const u8 = "--",
    context_state: ?*ContextState = null,
    binary_mode: options_mod.BinaryMode,
    line_buffered: bool = false,
    initial_tab_width: usize = 0,
    utf8_locale: bool = false,
    ascii_input: ?bool = null,
    delimiter: u8 = '\n',
    null_filename: bool = false,
    colors: ?*const ColorConfig = null,
};

pub const ContextState = struct {
    emitted_group: bool = false,
};

pub const Result = struct {
    matched: bool = false,
    selected_lines: usize = 0,
    binary_match: bool = false,
};

fn suppressInvalidUtf8(line: []const u8, options: ScanOptions, result: *Result) bool {
    if (!options.utf8_locale or options.binary_mode == .text or
        options.only_matching or options.count or options.quiet or
        options.list_files != null or std.unicode.utf8ValidateSlice(line)) return false;
    if (options.binary_mode == .binary) result.binary_match = true;
    return true;
}

fn bufferIsAscii(buffer: []const u8, options: ScanOptions) bool {
    return options.ascii_input orelse matcher_mod.isAscii(buffer);
}

pub fn scanBuffer(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    if (options.list_files) |want_match| {
        var inner_options = options;
        inner_options.list_files = null;
        inner_options.quiet = true;
        inner_options.count = false;
        const result = try scanBuffer(buffer, matchers, path, inner_options, writer);
        const selected = result.matched == want_match;
        if (selected) try emitFilename(
            writer,
            path,
            options.null_filename,
            options.colors,
            options.line_buffered,
        );
        return result;
    }
    if (options.max_count == 0) {
        if (options.count) try emitCount(
            writer,
            path,
            options.show_filename,
            options.null_filename,
            options.colors,
            0,
            options.line_buffered,
        );
        return .{};
    }
    if (contextOutputEnabled(options)) {
        const invalid_utf8 = options.utf8_locale and options.binary_mode != .text and
            !std.unicode.utf8ValidateSlice(buffer);
        if (!invalid_utf8 and matchers.len == 1 and !options.invert) {
            if (try parallelSparseContextOutput(buffer, matchers, path, options, writer)) |result|
                return result;
            switch (matchers[0]) {
                .literal => |*literal| if (!literal.whole_line and literal.pattern.len != 0) {
                    return scanLiteralContextFast(buffer, matchers, literal, path, options, writer);
                },
                .posix_regex => |*regex| if (bufferIsAscii(buffer, options)) {
                    if (regex.ascii_literal) |*literal| {
                        if (!literal.whole_line and literal.pattern.len != 0)
                            return scanLiteralContextFast(buffer, matchers, literal, path, options, writer);
                    }
                },
                else => {},
            }
        }
        return scanLinesWithContext(buffer, matchers, path, options, writer);
    }
    const needs_match_output = options.only_matching and !options.count and !options.quiet;
    if (matchers.len == 1 and !options.invert) {
        switch (matchers[0]) {
            .literal => |*literal| if (!literal.whole_line) {
                if (needs_match_output and literal.pattern.len != 0)
                    return scanLiteralOnlyMatchingFast(buffer, literal, path, options, writer);
                if (!needs_match_output) return scanLiteralFast(buffer, matchers, literal, path, options, writer);
            },
            .alternation => |*alternation| if (!needs_match_output and alternationFastMaxLast(alternation) != null) {
                return scanAlternationFast(buffer, matchers, alternation, path, options, writer);
            },
            .regex => |*regex| if (regex.prefilter) |*prefilter| {
                if (shouldUseRegexPrefilter(buffer, prefilter))
                    return scanRegexPrefilterFast(buffer, matchers, regex, prefilter, path, options, writer);
                return scanLines(buffer, matchers, regex, path, options, writer);
            },
            .posix_regex => |*regex| {
                if (regex.ascii_literal) |*literal| {
                    if (bufferIsAscii(buffer, options) and !literal.whole_line) {
                        if (needs_match_output and literal.pattern.len != 0)
                            return scanLiteralOnlyMatchingFast(buffer, literal, path, options, writer);
                        if (!needs_match_output)
                            return scanLiteralFast(buffer, matchers, literal, path, options, writer);
                    }
                } else if (regex.ascii_alternation) |*alternation| {
                    if (!needs_match_output and bufferIsAscii(buffer, options) and
                        !alternationContainsDelimiter(alternation, options.delimiter) and
                        alternationFastMaxLast(alternation) != null)
                    {
                        return scanAlternationFast(buffer, matchers, alternation, path, options, writer);
                    }
                } else if (regex.ascii_pcre) {
                    if (regex.prefilter) |*prefilter| {
                        if (shouldUseRegexPrefilter(buffer, prefilter))
                            return scanRegexPrefilterFast(buffer, matchers, regex, prefilter, path, options, writer);
                    }
                    if (bufferIsAscii(buffer, options))
                        return scanLines(buffer, matchers, regex, path, options, writer);
                }
            },
        }
    }
    return scanLines(buffer, matchers, null, path, options, writer);
}

pub fn scanReader(
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    if (options.list_files) |want_match| {
        var inner_options = options;
        inner_options.list_files = null;
        inner_options.quiet = true;
        inner_options.count = false;
        const result = try scanReader(reader, allocator, matchers, path, inner_options, writer);
        const selected = result.matched == want_match;
        if (selected) try emitFilename(
            writer,
            path,
            options.null_filename,
            options.colors,
            options.line_buffered,
        );
        return result;
    }
    if (options.max_count == 0) {
        if (options.count) try emitCount(
            writer,
            path,
            options.show_filename,
            options.null_filename,
            options.colors,
            0,
            options.line_buffered,
        );
        return .{};
    }
    if (contextOutputEnabled(options))
        return scanReaderWithContext(reader, allocator, matchers, path, options, writer);
    var result: Result = .{};
    var line_number: usize = 1;
    var byte_offset: usize = 0;
    var binary_checked_through: usize = 0;
    var binary_detected = false;
    var long_line: std.ArrayList(u8) = .empty;
    defer long_line.deinit(allocator);

    var reached_end = false;
    while (!reached_end) : (line_number += 1) {
        var line: []const u8 = undefined;
        while (true) {
            if (shouldSummarizeBinary(options) and !binary_detected) {
                if (reader.bufferedLen() == 0) {
                    reader.fillMore() catch |err| switch (err) {
                        error.EndOfStream => {},
                        error.ReadFailed => return error.ReadFailed,
                    };
                }
                const buffered = reader.buffered();
                const buffered_start = byte_offset + long_line.items.len;
                const unchecked_start = if (binary_checked_through > buffered_start)
                    @min(binary_checked_through - buffered_start, buffered.len)
                else
                    0;
                if (std.mem.findScalar(u8, buffered[unchecked_start..], 0) != null) {
                    binary_detected = true;
                    if (result.matched) return result;
                }
                binary_checked_through = @max(binary_checked_through, buffered_start + buffered.len);
            }
            const maybe_line = reader.takeDelimiter(options.delimiter) catch |err| switch (err) {
                error.StreamTooLong => {
                    const buffered = reader.buffered();
                    try long_line.appendSlice(allocator, buffered);
                    reader.tossBuffered();
                    continue;
                },
                error.ReadFailed => return error.ReadFailed,
            };
            if (maybe_line) |chunk| {
                if (long_line.items.len == 0) {
                    line = chunk;
                } else {
                    try long_line.appendSlice(allocator, chunk);
                    line = long_line.items;
                }
            } else {
                reached_end = true;
                if (long_line.items.len == 0) break;
                line = long_line.items;
            }
            break;
        }
        if (reached_end and long_line.items.len == 0) break;
        if (shouldSummarizeBinary(options) and !binary_detected and
            std.mem.findScalar(u8, line, 0) != null)
        {
            binary_detected = true;
            if (result.matched) return result;
        }

        var raw_match = false;
        for (matchers) |*matcher| {
            if (matcher.matches(line)) {
                raw_match = true;
                break;
            }
        }
        const selected = if (options.invert) !raw_match else raw_match;
        if (selected) {
            result.matched = true;
            result.selected_lines += 1;
            if (binary_detected) {
                result.binary_match = true;
                return result;
            }
            if (options.quiet) return result;
            const suppress_output = suppressInvalidUtf8(line, options, &result);
            if (!options.count and !suppress_output) {
                if (options.only_matching)
                    try emitSelectedOnlyMatches(
                        writer,
                        path,
                        options,
                        if (options.line_number) line_number else null,
                        byte_offset,
                        matchers,
                        line,
                    )
                else
                    try emitSelectedLine(
                        writer,
                        path,
                        options,
                        if (options.line_number) line_number else null,
                        if (options.byte_offset) byte_offset else null,
                        line,
                        matchers,
                    );
            }
            if (options.max_count == result.selected_lines) break;
        }
        byte_offset += line.len + @intFromBool(!reached_end);
        long_line.clearRetainingCapacity();
    }

    if (options.count and !options.quiet) try emitCount(
        writer,
        path,
        options.show_filename,
        options.null_filename,
        options.colors,
        result.selected_lines,
        options.line_buffered,
    );
    return result;
}

const RetainedContextLine = struct {
    data: []u8,
    number: usize,
    byte_offset: usize,
};

fn scanReaderWithContext(
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var line_number: usize = 1;
    var byte_offset: usize = 0;
    var binary_checked_through: usize = 0;
    var binary_detected = false;
    var long_line: std.ArrayList(u8) = .empty;
    defer long_line.deinit(allocator);

    var retained: std.ArrayList(RetainedContextLine) = .empty;
    defer {
        for (retained.items) |record| allocator.free(record.data);
        retained.deinit(allocator);
    }
    var retained_head: usize = 0;
    var last_emitted_number: ?usize = null;
    var after_remaining: usize = 0;
    var matching_finished = false;
    var reached_end = false;

    while (!reached_end) : (line_number += 1) {
        var line: []const u8 = undefined;
        while (true) {
            if (shouldSummarizeBinary(options) and !binary_detected) {
                if (reader.bufferedLen() == 0) {
                    reader.fillMore() catch |err| switch (err) {
                        error.EndOfStream => {},
                        error.ReadFailed => return error.ReadFailed,
                    };
                }
                const buffered = reader.buffered();
                const buffered_start = byte_offset + long_line.items.len;
                const unchecked_start = if (binary_checked_through > buffered_start)
                    @min(binary_checked_through - buffered_start, buffered.len)
                else
                    0;
                if (std.mem.findScalar(u8, buffered[unchecked_start..], 0) != null) {
                    binary_detected = true;
                    if (result.matched) return result;
                }
                binary_checked_through = @max(binary_checked_through, buffered_start + buffered.len);
            }
            const maybe_line = reader.takeDelimiter(options.delimiter) catch |err| switch (err) {
                error.StreamTooLong => {
                    const buffered = reader.buffered();
                    try long_line.appendSlice(allocator, buffered);
                    reader.tossBuffered();
                    continue;
                },
                error.ReadFailed => return error.ReadFailed,
            };
            if (maybe_line) |chunk| {
                if (long_line.items.len == 0) {
                    line = chunk;
                } else {
                    try long_line.appendSlice(allocator, chunk);
                    line = long_line.items;
                }
            } else {
                reached_end = true;
                if (long_line.items.len == 0) break;
                line = long_line.items;
            }
            break;
        }
        if (reached_end and long_line.items.len == 0) break;
        if (shouldSummarizeBinary(options) and !binary_detected and
            std.mem.findScalar(u8, line, 0) != null)
        {
            binary_detected = true;
            if (result.matched) return result;
        }

        var selected = false;
        if (!matching_finished) {
            var raw_match = false;
            for (matchers) |*matcher| {
                if (matcher.matches(line)) {
                    raw_match = true;
                    break;
                }
            }
            selected = if (options.invert) !raw_match else raw_match;
        }

        if (selected) {
            result.matched = true;
            result.selected_lines += 1;
            if (binary_detected) {
                result.binary_match = true;
                return result;
            }
            const suppress_selected = suppressInvalidUtf8(line, options, &result);
            const context_start_number = if (retained.items.len == 0)
                line_number
            else
                retained.items[retained_head].number;
            const starts_new_group = if (last_emitted_number) |last|
                context_start_number > last + 1
            else
                true;
            if (starts_new_group and (!suppress_selected or retained.items.len != 0))
                try beginContextGroup(writer, options, last_emitted_number == null);

            const retained_emit_start = if (last_emitted_number) |last|
                if (last >= context_start_number)
                    @min(retained.items.len, last - context_start_number + 1)
                else
                    0
            else
                0;
            for (retained_emit_start..retained.items.len) |retained_index| {
                const index = (retained_head + retained_index) % retained.items.len;
                const prior = retained.items[index];
                if (!suppressInvalidUtf8(prior.data, options, &result)) {
                    try emitContextLine(
                        writer,
                        path,
                        matchers,
                        options,
                        if (options.line_number) prior.number else null,
                        if (options.byte_offset) prior.byte_offset else null,
                        prior.data,
                        '-',
                        false,
                    );
                    last_emitted_number = prior.number;
                }
            }

            if (!suppress_selected) {
                try emitContextLine(
                    writer,
                    path,
                    matchers,
                    options,
                    if (options.line_number) line_number else null,
                    if (options.byte_offset) byte_offset else null,
                    line,
                    ':',
                    true,
                );
                last_emitted_number = line_number;
            }
            after_remaining = if (suppress_selected) 0 else options.after_context;
            if (options.max_count == result.selected_lines) {
                matching_finished = true;
                if (after_remaining == 0) break;
            }
        } else if (after_remaining > 0) {
            if (!suppressInvalidUtf8(line, options, &result)) {
                try emitContextLine(
                    writer,
                    path,
                    matchers,
                    options,
                    if (options.line_number) line_number else null,
                    if (options.byte_offset) byte_offset else null,
                    line,
                    '-',
                    false,
                );
                last_emitted_number = line_number;
            }
            after_remaining -= 1;
            if (matching_finished and after_remaining == 0) break;
        }

        if (options.before_context != 0) {
            const saved: RetainedContextLine = .{
                .data = try allocator.dupe(u8, line),
                .number = line_number,
                .byte_offset = byte_offset,
            };
            errdefer allocator.free(saved.data);
            if (retained.items.len < options.before_context) {
                try retained.append(allocator, saved);
            } else {
                allocator.free(retained.items[retained_head].data);
                retained.items[retained_head] = saved;
                retained_head = (retained_head + 1) % retained.items.len;
            }
        }
        byte_offset += line.len + @intFromBool(!reached_end);
        long_line.clearRetainingCapacity();
    }
    return result;
}

pub fn scanBufferQuietThreadMatchers(
    buffer: []const u8,
    matchers: []const matcher_mod.ThreadMatcher,
    options: ScanOptions,
) Result {
    if (options.max_count == 0 or buffer.len == 0) return .{};
    if (options.delimiter != 0 and options.binary_mode == .without_match) {
        if (std.mem.findScalar(u8, buffer, 0)) |nul_position| {
            const text_end = binaryTextPrefixEnd(
                buffer,
                nul_position,
                options.delimiter,
            );
            if (text_end == 0) return .{};
            var text_options = options;
            text_options.binary_mode = .text;
            return scanBufferQuietThreadMatchers(
                buffer[0..text_end],
                matchers,
                text_options,
            );
        }
    }

    if (!options.invert) {
        var all_whole_buffer_literals = matchers.len != 0;
        for (matchers) |*matcher| {
            if (matcher.matchesWholeBufferLiteral(buffer, options.delimiter)) |matched| {
                if (matched) return .{ .matched = true, .selected_lines = 1 };
            } else {
                all_whole_buffer_literals = false;
                break;
            }
        }
        if (all_whole_buffer_literals) return .{};

        var has_ascii_witness = false;
        for (matchers) |*matcher| {
            if (matcher.hasAsciiWitness()) {
                has_ascii_witness = true;
                break;
            }
        }
        if (has_ascii_witness) {
            for (matchers) |*matcher| {
                if (matcher.matchesAsciiWitness(buffer))
                    return .{ .matched = true, .selected_lines = 1 };
            }
        }

        if (matchers.len == 1) switch (matchers[0]) {
            .regex => |*regex| if (regex.value.prefilter) |*prefilter| {
                if (threadRegexPrefilterMatches(
                    buffer,
                    regex,
                    prefilter,
                    false,
                    options.delimiter,
                )) |matched| return if (matched)
                    .{ .matched = true, .selected_lines = 1 }
                else
                    .{};
            },
            .posix_regex => |*regex| if (regex.value.prefilter) |*prefilter| {
                if (threadRegexPrefilterMatches(
                    buffer,
                    regex,
                    prefilter,
                    true,
                    options.delimiter,
                )) |matched| return if (matched)
                    .{ .matched = true, .selected_lines = 1 }
                else
                    .{};
            },
            else => {},
        };
    }

    const known_ascii = threadMatchersBenefitFromKnownAscii(matchers) and
        matcher_mod.isAscii(buffer);
    var record_start: usize = 0;
    while (record_start < buffer.len) {
        const record_end = std.mem.findScalarPos(
            u8,
            buffer,
            record_start,
            options.delimiter,
        ) orelse buffer.len;
        const record = buffer[record_start..record_end];
        var raw_match = false;
        for (matchers) |*matcher| {
            if (if (known_ascii)
                matcher.matchesKnownAscii(record)
            else
                matcher.matches(record))
            {
                raw_match = true;
                break;
            }
        }
        if (if (options.invert) !raw_match else raw_match)
            return .{ .matched = true, .selected_lines = 1 };
        if (record_end == buffer.len) break;
        record_start = record_end + 1;
    }
    return .{};
}

fn threadRegexPrefilterMatches(
    buffer: []const u8,
    regex: anytype,
    prefilter: *const matcher_mod.Literal,
    posix: bool,
    delimiter: u8,
) ?bool {
    const sample_len = @min(buffer.len, 1024 * 1024);
    const dense_limit = sample_len / 512;
    var sample_occurrences: usize = 0;
    var search_position: usize = 0;
    while (search_position < buffer.len) {
        const match_position = prefilter.find(buffer, search_position) orelse return false;
        if (match_position < sample_len) {
            sample_occurrences += 1;
            if (sample_occurrences > dense_limit) return null;
        }
        const line_start = if (std.mem.findScalarLast(
            u8,
            buffer[0..match_position],
            delimiter,
        )) |record_end| record_end + 1 else 0;
        const line_end = std.mem.findScalarPos(
            u8,
            buffer,
            match_position,
            delimiter,
        ) orelse buffer.len;
        const line = buffer[line_start..line_end];
        const matches = if (!posix or (regex.value.ascii_pcre and matcher_mod.isAscii(line)))
            regex.worker.matches(line)
        else
            regex.worker.matchesPosix(line);
        if (matches) return true;
        if (line_end == buffer.len) return false;
        search_position = line_end + 1;
    }
    return false;
}

fn threadMatchersBenefitFromKnownAscii(matchers: []const matcher_mod.ThreadMatcher) bool {
    for (matchers) |*matcher| {
        if (matcher.benefitsFromKnownAscii()) return true;
    }
    return false;
}

pub fn scanBufferOutputThreadMatchers(
    buffer: []const u8,
    matchers: []const matcher_mod.ThreadMatcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    std.debug.assert(!options.count and !options.quiet and options.list_files == null);
    std.debug.assert(options.max_count == null and !options.only_matching);
    std.debug.assert(options.before_context == 0 and options.after_context == 0);
    std.debug.assert(options.colors == null and !options.line_buffered);

    if (matchers.len == 1 and !options.invert) switch (matchers[0]) {
        .literal => |literal| if (!literal.whole_line) {
            const local_matcher: matcher_mod.Matcher = .{ .literal = literal.* };
            return scanLiteralFast(
                buffer,
                &.{local_matcher},
                literal,
                path,
                options,
                writer,
            );
        },
        .alternation => |alternation| if (alternationFastMaxLast(alternation) != null) {
            const local_matcher: matcher_mod.Matcher = .{ .alternation = alternation.* };
            return scanAlternationFast(
                buffer,
                &.{local_matcher},
                alternation,
                path,
                options,
                writer,
            );
        },
        .regex => |*regex| if (regex.value.prefilter) |*prefilter| {
            if (shouldUseRegexPrefilter(buffer, prefilter))
                return scanThreadRegexPrefilterOutput(
                    buffer,
                    regex,
                    prefilter,
                    false,
                    path,
                    options,
                    writer,
                );
        },
        .posix_regex => |*regex| {
            if (regex.value.ascii_literal) |*literal| {
                if (!literal.whole_line and
                    std.mem.findScalar(u8, literal.pattern, options.delimiter) == null and
                    matcher_mod.isAscii(buffer))
                {
                    const local_matcher: matcher_mod.Matcher = .{ .literal = literal.* };
                    return scanLiteralFast(
                        buffer,
                        &.{local_matcher},
                        literal,
                        path,
                        options,
                        writer,
                    );
                }
            }
            if (regex.value.ascii_alternation) |*alternation| {
                if (alternationFastMaxLast(alternation) != null and
                    !alternationContainsDelimiter(alternation, options.delimiter) and
                    matcher_mod.isAscii(buffer))
                {
                    const local_matcher: matcher_mod.Matcher = .{ .alternation = alternation.* };
                    return scanAlternationFast(
                        buffer,
                        &.{local_matcher},
                        alternation,
                        path,
                        options,
                        writer,
                    );
                }
            }
            if (regex.value.prefilter) |*prefilter| {
                if (shouldUseRegexPrefilter(buffer, prefilter))
                    return scanThreadRegexPrefilterOutput(
                        buffer,
                        regex,
                        prefilter,
                        true,
                        path,
                        options,
                        writer,
                    );
            }
        },
    };

    const known_ascii = threadMatchersBenefitFromKnownAscii(matchers) and
        matcher_mod.isAscii(buffer);
    var result: Result = .{};
    var record_start: usize = 0;
    var record_number: usize = 1;
    while (record_start < buffer.len) : (record_number += 1) {
        const record_end = std.mem.findScalarPos(
            u8,
            buffer,
            record_start,
            options.delimiter,
        ) orelse buffer.len;
        const record = buffer[record_start..record_end];
        var raw_match = false;
        for (matchers) |*matcher| {
            if (if (known_ascii)
                matcher.matchesKnownAscii(record)
            else
                matcher.matches(record))
            {
                raw_match = true;
                break;
            }
        }
        if (if (options.invert) !raw_match else raw_match) {
            result.matched = true;
            result.selected_lines += 1;
            if (!suppressInvalidUtf8(record, options, &result))
                try emitLine(
                    writer,
                    path,
                    options.show_filename,
                    if (options.line_number) record_number else null,
                    if (options.byte_offset) record_start else null,
                    record,
                    options.delimiter,
                    options.null_filename,
                    options.initial_tab_width,
                    false,
                );
        }
        if (record_end == buffer.len) break;
        record_start = record_end + 1;
    }
    return result;
}

fn scanThreadRegexPrefilterOutput(
    buffer: []const u8,
    regex: anytype,
    prefilter: *const matcher_mod.Literal,
    posix: bool,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var search_position: usize = 0;
    var line_number: usize = 1;
    var numbered_through: usize = 0;
    while (search_position < buffer.len) {
        const match_position = prefilter.find(buffer, search_position) orelse break;
        const line_start = if (std.mem.findScalarLast(
            u8,
            buffer[0..match_position],
            options.delimiter,
        )) |record_end| record_end + 1 else 0;
        const line_end = std.mem.findScalarPos(
            u8,
            buffer,
            match_position,
            options.delimiter,
        ) orelse buffer.len;
        const line = buffer[line_start..line_end];
        const matches = if (!posix or (regex.value.ascii_pcre and matcher_mod.isAscii(line)))
            regex.worker.matches(line)
        else
            regex.worker.matchesPosix(line);
        if (matches) {
            if (options.line_number) {
                line_number += std.mem.countScalar(
                    u8,
                    buffer[numbered_through..line_start],
                    options.delimiter,
                );
                numbered_through = line_start;
            }
            result.matched = true;
            result.selected_lines += 1;
            if (!suppressInvalidUtf8(line, options, &result))
                try emitLine(
                    writer,
                    path,
                    options.show_filename,
                    if (options.line_number) line_number else null,
                    if (options.byte_offset) line_start else null,
                    line,
                    options.delimiter,
                    options.null_filename,
                    options.initial_tab_width,
                    false,
                );
        }
        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }
    return result;
}

fn shouldSummarizeBinary(options: ScanOptions) bool {
    return options.binary_mode == .binary and
        options.delimiter != 0 and !options.count and
        options.list_files == null and !options.quiet;
}

pub fn binaryTextPrefixEnd(
    buffer: []const u8,
    nul_position: usize,
    delimiter: u8,
) usize {
    const detection_block_bytes = 256 * 1024;
    const nominal_start = nul_position / detection_block_bytes * detection_block_bytes;
    if (nominal_start == 0) return 0;
    return if (std.mem.findScalarLast(u8, buffer[0..nominal_start], delimiter)) |record_end|
        record_end + 1
    else
        0;
}

pub fn scanFileLiteralCount(
    file: std.Io.File,
    io: std.Io,
    allocator: std.mem.Allocator,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !?Result {
    if (!options.count or options.quiet or options.list_files != null or
        options.max_count != null or matchers.len != 1) return null;
    const literal = switch (matchers[0]) {
        .literal => |*value| value,
        .alternation => return null,
        .regex => return null,
        .posix_regex => return null,
    };
    if (literal.whole_line) return null;

    const block = try allocator.alloc(u8, 4 * 1024 * 1024);
    defer allocator.free(block);
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(allocator);
    var selected_lines: usize = 0;

    while (true) {
        const bytes_read = file.readStreaming(io, &.{block}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |other| return other,
        };
        if (bytes_read == 0) continue;
        const chunk = block[0..bytes_read];
        var cursor: usize = 0;

        if (pending.items.len != 0) {
            if (std.mem.findScalar(u8, chunk, options.delimiter)) |newline| {
                try pending.appendSlice(allocator, chunk[0 .. newline + 1]);
                selected_lines += countLiteralSelected(
                    pending.items,
                    literal,
                    options.invert,
                    options.delimiter,
                );
                pending.clearRetainingCapacity();
                cursor = newline + 1;
            } else {
                try pending.appendSlice(allocator, chunk);
                continue;
            }
        }

        if (cursor < chunk.len) {
            if (std.mem.findScalarLast(u8, chunk[cursor..], options.delimiter)) |relative_newline| {
                const end = cursor + relative_newline + 1;
                selected_lines += countLiteralSelected(
                    chunk[cursor..end],
                    literal,
                    options.invert,
                    options.delimiter,
                );
                try pending.appendSlice(allocator, chunk[end..]);
            } else {
                try pending.appendSlice(allocator, chunk[cursor..]);
            }
        }
    }

    if (pending.items.len != 0) {
        selected_lines += countLiteralSelected(
            pending.items,
            literal,
            options.invert,
            options.delimiter,
        );
    }
    try emitCount(
        writer,
        path,
        options.show_filename,
        options.null_filename,
        options.colors,
        selected_lines,
        options.line_buffered,
    );
    return .{ .matched = selected_lines != 0, .selected_lines = selected_lines };
}

pub fn scanFileLiteralOutput(
    file: std.Io.File,
    io: std.Io,
    allocator: std.mem.Allocator,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !?Result {
    if (options.colors != null or options.line_buffered or options.count or options.quiet or options.list_files != null or options.invert or
        options.only_matching or contextOutputEnabled(options) or matchers.len != 1) return null;
    const literal = switch (matchers[0]) {
        .literal => |*value| value,
        else => return null,
    };
    if (literal.whole_line or literal.pattern.len == 0 or
        std.mem.findScalar(u8, literal.pattern, options.delimiter) != null) return null;

    const detection_block_bytes = 256 * 1024;
    const block = try allocator.alloc(u8, detection_block_bytes);
    defer allocator.free(block);
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(allocator);

    var result: Result = .{};
    var line_number: usize = 1;
    var block_offset: usize = 0;
    var pending_offset: usize = 0;
    var binary_detected = false;
    var reached_end = false;

    while (!reached_end) {
        var filled: usize = 0;
        while (filled < block.len) {
            const bytes_read = file.readStreaming(io, &.{block[filled..]}) catch |err| switch (err) {
                error.EndOfStream => {
                    reached_end = true;
                    break;
                },
                else => |other| return other,
            };
            if (bytes_read == 0) continue;
            filled += bytes_read;
        }
        if (filled == 0) break;
        const chunk = block[0..filled];

        if (!binary_detected and options.delimiter != 0 and options.binary_mode == .binary and
            std.mem.findScalar(u8, chunk, 0) != null)
        {
            binary_detected = true;
            if (result.matched) return result;
        }
        if (binary_detected) {
            if (try binaryLiteralBlockMatches(
                allocator,
                &pending,
                chunk,
                literal,
                options.delimiter,
            )) {
                result.matched = true;
                result.selected_lines = 1;
                result.binary_match = true;
                return result;
            }
        } else if (try scanStreamingLiteralBlock(
            allocator,
            &pending,
            &pending_offset,
            chunk,
            block_offset,
            literal,
            path,
            options,
            writer,
            &line_number,
            &result,
        )) return result;
        block_offset += filled;
    }

    if (pending.items.len != 0) {
        if (binary_detected) {
            if (literal.matches(pending.items)) {
                result.matched = true;
                result.selected_lines = 1;
                result.binary_match = true;
            }
        } else {
            _ = try emitStreamingLiteralLine(
                pending.items,
                pending_offset,
                line_number,
                literal,
                path,
                options,
                writer,
                &result,
            );
        }
    }
    return result;
}

fn scanStreamingLiteralBlock(
    allocator: std.mem.Allocator,
    pending: *std.ArrayList(u8),
    pending_offset: *usize,
    chunk: []const u8,
    block_offset: usize,
    literal: *const matcher_mod.Literal,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
    line_number: *usize,
    result: *Result,
) !bool {
    var cursor: usize = 0;
    if (pending.items.len != 0) {
        const newline = std.mem.findScalar(u8, chunk, options.delimiter) orelse {
            try pending.appendSlice(allocator, chunk);
            return false;
        };
        try pending.appendSlice(allocator, chunk[0..newline]);
        if (try emitStreamingLiteralLine(
            pending.items,
            pending_offset.*,
            line_number.*,
            literal,
            path,
            options,
            writer,
            result,
        )) return true;
        pending.clearRetainingCapacity();
        line_number.* += 1;
        cursor = newline + 1;
    }

    if (cursor < chunk.len) {
        if (std.mem.findScalarLast(u8, chunk[cursor..], options.delimiter)) |relative_newline| {
            const complete_end = cursor + relative_newline + 1;
            if (try scanCompletedLiteralLines(
                chunk[cursor..complete_end],
                block_offset + cursor,
                line_number.*,
                literal,
                path,
                options,
                writer,
                result,
            )) return true;
            line_number.* += std.mem.countScalar(u8, chunk[cursor..complete_end], options.delimiter);
            if (complete_end < chunk.len) {
                pending_offset.* = block_offset + complete_end;
                try pending.appendSlice(allocator, chunk[complete_end..]);
            }
        } else {
            pending_offset.* = block_offset + cursor;
            try pending.appendSlice(allocator, chunk[cursor..]);
        }
    }
    return false;
}

fn scanCompletedLiteralLines(
    data: []const u8,
    base_offset: usize,
    first_line_number: usize,
    literal: *const matcher_mod.Literal,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
    result: *Result,
) !bool {
    var search_position: usize = 0;
    var line_number = first_line_number;
    var numbered_through: usize = 0;
    while (search_position < data.len) {
        const match_position = literal.find(data, search_position) orelse break;
        if (!literal.acceptsMatchAt(data, match_position)) {
            search_position = match_position + literal.pattern.len;
            continue;
        }
        const line_start = if (std.mem.findScalarLast(u8, data[0..match_position], options.delimiter)) |newline|
            newline + 1
        else
            0;
        const line_end = std.mem.findScalarPos(u8, data, match_position, options.delimiter).?;
        line_number += std.mem.countScalar(u8, data[numbered_through..line_start], options.delimiter);
        numbered_through = line_start;
        result.matched = true;
        result.selected_lines += 1;
        const line = data[line_start..line_end];
        if (!suppressInvalidUtf8(line, options, result))
            try emitLine(
                writer,
                path,
                options.show_filename,
                if (options.line_number) line_number else null,
                if (options.byte_offset) base_offset + line_start else null,
                line,
                options.delimiter,
                options.null_filename,
                options.initial_tab_width,
                options.line_buffered,
            );
        if (options.max_count == result.selected_lines) return true;
        search_position = line_end + 1;
    }
    return false;
}

fn emitStreamingLiteralLine(
    line: []const u8,
    byte_offset: usize,
    line_number: usize,
    literal: *const matcher_mod.Literal,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
    result: *Result,
) !bool {
    if (!literal.matches(line)) return false;
    result.matched = true;
    result.selected_lines += 1;
    if (!suppressInvalidUtf8(line, options, result))
        try emitLine(
            writer,
            path,
            options.show_filename,
            if (options.line_number) line_number else null,
            if (options.byte_offset) byte_offset else null,
            line,
            options.delimiter,
            options.null_filename,
            options.initial_tab_width,
            options.line_buffered,
        );
    return options.max_count == result.selected_lines;
}

fn binaryLiteralBlockMatches(
    allocator: std.mem.Allocator,
    pending: *std.ArrayList(u8),
    chunk: []const u8,
    literal: *const matcher_mod.Literal,
    delimiter: u8,
) !bool {
    var cursor: usize = 0;
    if (pending.items.len != 0) {
        const newline = std.mem.findScalar(u8, chunk, delimiter) orelse {
            try pending.appendSlice(allocator, chunk);
            return false;
        };
        try pending.appendSlice(allocator, chunk[0..newline]);
        if (literal.matches(pending.items)) return true;
        pending.clearRetainingCapacity();
        cursor = newline + 1;
    }
    if (cursor < chunk.len) {
        if (std.mem.findScalarLast(u8, chunk[cursor..], delimiter)) |relative_newline| {
            const complete_end = cursor + relative_newline + 1;
            if (containsAcceptedLiteral(chunk[cursor..complete_end], literal)) return true;
            try pending.appendSlice(allocator, chunk[complete_end..]);
        } else {
            try pending.appendSlice(allocator, chunk[cursor..]);
        }
    }
    return false;
}

fn containsAcceptedLiteral(data: []const u8, literal: *const matcher_mod.Literal) bool {
    var search_position: usize = 0;
    while (literal.find(data, search_position)) |match_position| {
        if (literal.acceptsMatchAt(data, match_position)) return true;
        search_position = match_position + literal.pattern.len;
    }
    return false;
}

pub fn parallelLiteralCount(
    buffer: []const u8,
    literal: *const matcher_mod.Literal,
    invert: bool,
    delimiter: u8,
) !usize {
    const bytes_per_thread = 16 * 1024 * 1024;
    const max_threads = 16;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    if (thread_count == 1) return countLiteralSelected(buffer, literal, invert, delimiter);

    var boundaries: [max_threads + 1]usize = undefined;
    boundaries[0] = 0;
    boundaries[thread_count] = buffer.len;
    for (1..thread_count) |index| {
        const nominal = buffer.len / thread_count * index;
        boundaries[index] = if (std.mem.findScalarPos(u8, buffer, nominal, delimiter)) |record_end|
            record_end + 1
        else
            buffer.len;
    }

    var counts: [max_threads]usize = @splat(0);
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();

    for (0..thread_count - 1) |index| {
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            countWorker,
            .{
                buffer[boundaries[index]..boundaries[index + 1]],
                literal,
                invert,
                delimiter,
                &counts[index],
            },
        );
        spawned += 1;
    }
    counts[thread_count - 1] = countLiteralSelected(
        buffer[boundaries[thread_count - 1]..boundaries[thread_count]],
        literal,
        invert,
        delimiter,
    );
    for (threads[0..spawned]) |thread| thread.join();

    var total: usize = 0;
    for (counts[0..thread_count]) |count| total += count;
    return total;
}

pub fn findNulParallel(buffer: []const u8) !?usize {
    const bytes_per_thread = 16 * 1024 * 1024;
    const max_threads = 16;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    if (thread_count == 1) return std.mem.findScalar(u8, buffer, 0);

    var results: [max_threads]?usize = @splat(null);
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();

    for (0..thread_count - 1) |index| {
        const start = buffer.len / thread_count * index;
        const end = buffer.len / thread_count * (index + 1);
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            findNulWorker,
            .{ buffer[start..end], start, &results[index] },
        );
        spawned += 1;
    }
    const last_start = buffer.len / thread_count * (thread_count - 1);
    findNulWorker(
        buffer[last_start..],
        last_start,
        &results[thread_count - 1],
    );
    for (threads[0..spawned]) |thread| thread.join();

    var first: ?usize = null;
    for (results[0..thread_count]) |result| {
        if (result) |position| first = if (first) |current| @min(current, position) else position;
    }
    return first;
}

pub fn isAsciiParallel(buffer: []const u8) !bool {
    const bytes_per_thread = 8 * 1024 * 1024;
    const max_threads = 16;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    if (thread_count == 1) return matcher_mod.isAscii(buffer);

    var results: [max_threads]bool = @splat(true);
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();

    for (0..thread_count - 1) |index| {
        const start = buffer.len / thread_count * index;
        const end = buffer.len / thread_count * (index + 1);
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            isAsciiWorker,
            .{ buffer[start..end], &results[index] },
        );
        spawned += 1;
    }
    const last_start = buffer.len / thread_count * (thread_count - 1);
    isAsciiWorker(buffer[last_start..], &results[thread_count - 1]);
    for (threads[0..spawned]) |thread| thread.join();
    for (results[0..thread_count]) |result| if (!result) return false;
    return true;
}

pub fn parallelAlternationCount(
    buffer: []const u8,
    alternation: *const matcher_mod.LiteralAlternation,
    invert: bool,
    delimiter: u8,
) !usize {
    const bytes_per_thread = 16 * 1024 * 1024;
    const max_threads = 16;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    if (thread_count == 1) return countAlternationSelected(buffer, alternation, invert, delimiter);

    var boundaries: [max_threads + 1]usize = undefined;
    boundaries[0] = 0;
    boundaries[thread_count] = buffer.len;
    for (1..thread_count) |index| {
        const nominal = buffer.len / thread_count * index;
        boundaries[index] = if (std.mem.findScalarPos(u8, buffer, nominal, delimiter)) |record_end|
            record_end + 1
        else
            buffer.len;
    }

    var counts: [max_threads]usize = @splat(0);
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();

    for (0..thread_count - 1) |index| {
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            countAlternationWorker,
            .{
                buffer[boundaries[index]..boundaries[index + 1]],
                alternation,
                invert,
                delimiter,
                &counts[index],
            },
        );
        spawned += 1;
    }
    counts[thread_count - 1] = countAlternationSelected(
        buffer[boundaries[thread_count - 1]..boundaries[thread_count]],
        alternation,
        invert,
        delimiter,
    );
    for (threads[0..spawned]) |thread| thread.join();

    var total: usize = 0;
    for (counts[0..thread_count]) |count| total += count;
    return total;
}

pub fn parallelRegexCount(
    buffer: []const u8,
    regex: *const matcher_mod.Regex,
    invert: bool,
    delimiter: u8,
    ascii_input: bool,
) !usize {
    const bytes_per_thread: usize = if (ascii_input and regex.ascii_class_sequence != null)
        6 * 1024 * 1024
    else
        8 * 1024 * 1024;
    const max_threads = 16;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    const sparse_prefilter = if (regex.prefilter) |*prefilter|
        shouldUseRegexPrefilter(buffer, prefilter)
    else
        false;
    if (thread_count == 1)
        return countRegexSelected(buffer, regex, invert, delimiter, sparse_prefilter, ascii_input);

    var boundaries: [max_threads + 1]usize = undefined;
    boundaries[0] = 0;
    boundaries[thread_count] = buffer.len;
    for (1..thread_count) |index| {
        const nominal = buffer.len / thread_count * index;
        boundaries[index] = if (std.mem.findScalarPos(u8, buffer, nominal, delimiter)) |record_end|
            record_end + 1
        else
            buffer.len;
    }

    var regex_workers: [max_threads]matcher_mod.RegexWorker = undefined;
    var worker_count: usize = 0;
    defer for (regex_workers[0..worker_count]) |*worker| worker.deinit();
    for (0..thread_count) |index| {
        regex_workers[index] = regex.createWorker() orelse return error.OutOfMemory;
        worker_count += 1;
    }

    var counts: [max_threads]usize = @splat(0);
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();

    for (0..thread_count - 1) |index| {
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            countRegexWorker,
            .{
                buffer[boundaries[index]..boundaries[index + 1]],
                regex,
                &regex_workers[index],
                invert,
                delimiter,
                sparse_prefilter,
                ascii_input,
                &counts[index],
            },
        );
        spawned += 1;
    }
    counts[thread_count - 1] = countRegexSelectedWithWorker(
        buffer[boundaries[thread_count - 1]..boundaries[thread_count]],
        regex,
        &regex_workers[thread_count - 1],
        invert,
        delimiter,
        sparse_prefilter,
        ascii_input,
    );
    for (threads[0..spawned]) |thread| thread.join();

    var total: usize = 0;
    for (counts[0..thread_count]) |count| total += count;
    return total;
}

const ParallelOutputMatcher = union(enum) {
    literal: *const matcher_mod.Literal,
    alternation: struct {
        value: *const matcher_mod.LiteralAlternation,
        max_last: usize,
    },
    regex: struct {
        value: *const matcher_mod.Regex,
        prefilter: *const matcher_mod.Literal,
    },
};

const SelectedRecord = struct {
    start: usize,
    end: usize,
    number: usize,
};

const ParallelOutputChunk = struct {
    records: std.ArrayList(SelectedRecord) = .empty,
    selected_records: usize = 0,
    total_records: usize = 0,
    failed: bool = false,
    too_dense: bool = false,

    fn deinit(self: *ParallelOutputChunk) void {
        self.records.deinit(std.heap.c_allocator);
    }
};

pub fn parallelSelectedOutput(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !?Result {
    return parallelSelectedOutputWithLimits(
        buffer,
        matchers,
        path,
        options,
        writer,
        16 * 1024 * 1024,
        64 * 1024,
    );
}

fn parallelSelectedOutputWithChunkBytes(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
    bytes_per_thread: usize,
) !?Result {
    return parallelSelectedOutputWithLimits(
        buffer,
        matchers,
        path,
        options,
        writer,
        bytes_per_thread,
        64 * 1024,
    );
}

fn parallelSelectedOutputWithLimits(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
    bytes_per_thread: usize,
    max_records_per_chunk: usize,
) !?Result {
    const max_threads = 16;
    if (buffer.len < 4 * bytes_per_thread or matchers.len != 1 or options.invert or
        options.count or options.quiet or options.list_files != null or
        options.max_count != null or contextOutputEnabled(options)) return null;

    const parallel_matcher: ParallelOutputMatcher = switch (matchers[0]) {
        .literal => |*literal| if (!literal.whole_line and literal.pattern.len != 0)
            .{ .literal = literal }
        else
            return null,
        .alternation => |*alternation| if (!options.only_matching)
            .{ .alternation = .{
                .value = alternation,
                .max_last = alternationFastMaxLast(alternation) orelse return null,
            } }
        else
            return null,
        .regex => |*regex| regex_output: {
            const prefilter = if (regex.prefilter) |*value| value else return null;
            if (!shouldUseRegexPrefilter(buffer, prefilter)) return null;
            break :regex_output .{ .regex = .{
                .value = regex,
                .prefilter = prefilter,
            } };
        },
        .posix_regex => |*regex| posix_output: {
            if (regex.ascii_literal) |*literal| {
                if (!bufferIsAscii(buffer, options)) return null;
                if (!literal.whole_line and literal.pattern.len != 0)
                    break :posix_output .{ .literal = literal };
                return null;
            }
            if (!regex.ascii_pcre) return null;
            const prefilter = if (regex.prefilter) |*value| value else return null;
            if (!shouldUseRegexPrefilter(buffer, prefilter)) return null;
            break :posix_output .{ .regex = .{
                .value = regex,
                .prefilter = prefilter,
            } };
        },
    };

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    if (thread_count == 1) return null;

    var boundaries: [max_threads + 1]usize = undefined;
    boundaries[0] = 0;
    boundaries[thread_count] = buffer.len;
    for (1..thread_count) |index| {
        const nominal = buffer.len / thread_count * index;
        boundaries[index] = if (std.mem.findScalarPos(u8, buffer, nominal, options.delimiter)) |record_end|
            record_end + 1
        else
            buffer.len;
    }

    var regex_workers: [max_threads]matcher_mod.RegexWorker = undefined;
    var regex_worker_count: usize = 0;
    defer for (regex_workers[0..regex_worker_count]) |*worker| worker.deinit();
    switch (parallel_matcher) {
        .regex => |regex| for (0..thread_count) |index| {
            regex_workers[index] = regex.value.createWorker() orelse return error.OutOfMemory;
            regex_worker_count += 1;
        },
        else => {},
    }

    var chunks: [max_threads]ParallelOutputChunk = @splat(.{});
    defer for (chunks[0..thread_count]) |*chunk| chunk.deinit();
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();

    for (0..thread_count - 1) |index| {
        const regex_worker: ?*const matcher_mod.RegexWorker = switch (parallel_matcher) {
            .regex => &regex_workers[index],
            else => null,
        };
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            selectedOutputWorker,
            .{
                buffer[boundaries[index]..boundaries[index + 1]],
                parallel_matcher,
                regex_worker,
                options.delimiter,
                options.line_number,
                options.only_matching,
                max_records_per_chunk,
                &chunks[index],
            },
        );
        spawned += 1;
    }
    const last_regex_worker: ?*const matcher_mod.RegexWorker = switch (parallel_matcher) {
        .regex => &regex_workers[thread_count - 1],
        else => null,
    };
    selectedOutputWorker(
        buffer[boundaries[thread_count - 1]..boundaries[thread_count]],
        parallel_matcher,
        last_regex_worker,
        options.delimiter,
        options.line_number,
        options.only_matching,
        max_records_per_chunk,
        &chunks[thread_count - 1],
    );
    for (threads[0..spawned]) |thread| thread.join();

    for (chunks[0..thread_count]) |chunk| {
        if (chunk.failed or chunk.too_dense) return null;
    }

    var result: Result = .{};
    var preceding_records: usize = 0;
    const regex_only_matching = options.only_matching and switch (parallel_matcher) {
        .regex => true,
        else => false,
    };
    for (chunks[0..thread_count], 0..) |chunk, index| {
        for (chunk.records.items) |record| {
            result.matched = true;
            const line = buffer[boundaries[index] + record.start .. boundaries[index] + record.end];
            if (suppressInvalidUtf8(line, options, &result)) continue;
            if (regex_only_matching)
                try emitSelectedOnlyMatches(
                    writer,
                    path,
                    options,
                    if (options.line_number) preceding_records + record.number else null,
                    boundaries[index] + record.start,
                    matchers,
                    line,
                )
            else
                try emitSelectedLine(
                    writer,
                    path,
                    options,
                    if (options.line_number) preceding_records + record.number else null,
                    if (options.byte_offset) boundaries[index] + record.start else null,
                    line,
                    matchers,
                );
        }
        result.selected_lines += chunk.selected_records;
        preceding_records += chunk.total_records;
    }
    return result;
}

fn selectedOutputWorker(
    buffer: []const u8,
    parallel_matcher: ParallelOutputMatcher,
    regex_worker: ?*const matcher_mod.RegexWorker,
    delimiter: u8,
    need_record_numbers: bool,
    only_matching: bool,
    max_records_per_chunk: usize,
    result: *ParallelOutputChunk,
) void {
    var search_position: usize = 0;
    var record_number: usize = 1;
    var numbered_through: usize = 0;
    var last_selected_start: ?usize = null;
    while (search_position < buffer.len) {
        const match_position = findParallelOutputMatch(
            buffer,
            search_position,
            parallel_matcher,
        ) orelse break;
        const record_start = if (std.mem.findScalarLast(u8, buffer[0..match_position], delimiter)) |record_end|
            record_end + 1
        else
            0;
        const record_end = std.mem.findScalarPos(u8, buffer, match_position, delimiter) orelse buffer.len;
        switch (parallel_matcher) {
            .regex => |regex| if (!(if (regex.value.ascii_pcre)
                if (matcher_mod.isAscii(buffer[record_start..record_end]))
                    regex_worker.?.matches(buffer[record_start..record_end])
                else
                    regex_worker.?.matchesPosix(buffer[record_start..record_end])
            else
                regex_worker.?.matches(buffer[record_start..record_end])))
            {
                if (record_end == buffer.len) break;
                search_position = record_end + 1;
                continue;
            },
            else => {},
        }
        if (need_record_numbers) {
            record_number += std.mem.countScalar(
                u8,
                buffer[numbered_through..record_start],
                delimiter,
            );
            numbered_through = record_start;
        }
        if (result.records.items.len == max_records_per_chunk) {
            result.too_dense = true;
            return;
        }
        result.records.append(std.heap.c_allocator, .{
            .start = if (only_matching) switch (parallel_matcher) {
                .literal => match_position,
                .regex => record_start,
                .alternation => unreachable,
            } else record_start,
            .end = if (only_matching) switch (parallel_matcher) {
                .literal => |literal| match_position + literal.pattern.len,
                .regex => record_end,
                .alternation => unreachable,
            } else record_end,
            .number = record_number,
        }) catch {
            result.failed = true;
            return;
        };
        if (last_selected_start == null or last_selected_start.? != record_start) {
            result.selected_records += 1;
            last_selected_start = record_start;
        }
        if (only_matching) {
            switch (parallel_matcher) {
                .literal => |literal| {
                    search_position = match_position + literal.pattern.len;
                    continue;
                },
                .regex => {
                    if (record_end == buffer.len) break;
                    search_position = record_end + 1;
                    continue;
                },
                .alternation => unreachable,
            }
        }
        if (record_end == buffer.len) break;
        search_position = record_end + 1;
    }
    if (need_record_numbers and buffer.len != 0) {
        result.total_records = std.mem.countScalar(u8, buffer, delimiter) +
            @intFromBool(buffer[buffer.len - 1] != delimiter);
    }
}

fn findParallelOutputMatch(
    buffer: []const u8,
    start: usize,
    parallel_matcher: ParallelOutputMatcher,
) ?usize {
    return switch (parallel_matcher) {
        .literal => |literal| find: {
            var search_position = start;
            while (literal.find(buffer, search_position)) |match_position| {
                if (literal.acceptsMatchAt(buffer, match_position)) break :find match_position;
                search_position = match_position + literal.pattern.len;
            }
            break :find null;
        },
        .alternation => |alternation| findAlternationFast(
            buffer,
            start,
            alternation.value,
            alternation.max_last,
        ),
        .regex => |regex| regex.prefilter.find(buffer, start),
    };
}

fn countWorker(
    buffer: []const u8,
    literal: *const matcher_mod.Literal,
    invert: bool,
    delimiter: u8,
    result: *usize,
) void {
    result.* = countLiteralSelected(buffer, literal, invert, delimiter);
}

fn findNulWorker(buffer: []const u8, base: usize, result: *?usize) void {
    result.* = if (std.mem.findScalar(u8, buffer, 0)) |position| base + position else null;
}

fn isAsciiWorker(buffer: []const u8, result: *bool) void {
    result.* = matcher_mod.isAscii(buffer);
}

fn countAlternationWorker(
    buffer: []const u8,
    alternation: *const matcher_mod.LiteralAlternation,
    invert: bool,
    delimiter: u8,
    result: *usize,
) void {
    result.* = countAlternationSelected(buffer, alternation, invert, delimiter);
}

fn countRegexWorker(
    buffer: []const u8,
    regex: *const matcher_mod.Regex,
    worker: *const matcher_mod.RegexWorker,
    invert: bool,
    delimiter: u8,
    sparse_prefilter: bool,
    ascii_input: bool,
    result: *usize,
) void {
    result.* = countRegexSelectedWithWorker(
        buffer,
        regex,
        worker,
        invert,
        delimiter,
        sparse_prefilter,
        ascii_input,
    );
}

fn countLiteralSelected(
    buffer: []const u8,
    literal: *const matcher_mod.Literal,
    invert: bool,
    delimiter: u8,
) usize {
    const counts = countLiteralLines(buffer, literal, delimiter);
    return if (invert) counts.total - counts.matching else counts.matching;
}

fn countAlternationSelected(
    buffer: []const u8,
    alternation: *const matcher_mod.LiteralAlternation,
    invert: bool,
    delimiter: u8,
) usize {
    const counts = countAlternationLines(buffer, alternation, delimiter);
    return if (invert) counts.total - counts.matching else counts.matching;
}

fn countRegexSelected(
    buffer: []const u8,
    regex: *const matcher_mod.Regex,
    invert: bool,
    delimiter: u8,
    sparse_prefilter: bool,
    ascii_input: bool,
) usize {
    if (sparse_prefilter)
        return countRegexSelectedSparse(buffer, regex, invert, delimiter);
    var matching: usize = 0;
    var total: usize = 0;
    var line_start: usize = 0;
    while (line_start < buffer.len) {
        const line_end = std.mem.findScalarPos(u8, buffer, line_start, delimiter) orelse buffer.len;
        total += 1;
        const line = buffer[line_start..line_end];
        const matches = if (ascii_input)
            regex.matchesAsciiClassSequence(line) orelse regex.matches(line)
        else
            regex.matches(line);
        matching += @intFromBool(matches);
        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }
    return if (invert) total - matching else matching;
}

fn countRegexSelectedWithWorker(
    buffer: []const u8,
    regex: *const matcher_mod.Regex,
    worker: *const matcher_mod.RegexWorker,
    invert: bool,
    delimiter: u8,
    sparse_prefilter: bool,
    ascii_input: bool,
) usize {
    if (sparse_prefilter)
        return countRegexSelectedSparseWithWorker(buffer, regex, worker, invert, delimiter);
    var matching: usize = 0;
    var total: usize = 0;
    var line_start: usize = 0;
    while (line_start < buffer.len) {
        const line_end = std.mem.findScalarPos(u8, buffer, line_start, delimiter) orelse buffer.len;
        const line = buffer[line_start..line_end];
        const prefilter_matches = if (regex.prefilter) |*prefilter|
            prefilter.find(line, 0) != null
        else
            true;
        total += 1;
        const matches = if (ascii_input)
            regex.matchesAsciiClassSequence(line) orelse worker.matches(line)
        else
            worker.matches(line);
        matching += @intFromBool(prefilter_matches and matches);
        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }
    return if (invert) total - matching else matching;
}

fn countRegexSelectedSparse(
    buffer: []const u8,
    regex: *const matcher_mod.Regex,
    invert: bool,
    delimiter: u8,
) usize {
    const prefilter = &regex.prefilter.?;
    var matching: usize = 0;
    var search_position: usize = 0;
    while (prefilter.find(buffer, search_position)) |match_position| {
        const record_start = if (std.mem.findScalarLast(
            u8,
            buffer[0..match_position],
            delimiter,
        )) |record_end| record_end + 1 else 0;
        const record_end = std.mem.findScalarPos(
            u8,
            buffer,
            match_position,
            delimiter,
        ) orelse buffer.len;
        matching += @intFromBool(regex.matchesFull(buffer[record_start..record_end]));
        if (record_end == buffer.len) break;
        search_position = record_end + 1;
    }
    if (!invert) return matching;
    const total = if (buffer.len == 0) 0 else std.mem.countScalar(u8, buffer, delimiter) +
        @intFromBool(buffer[buffer.len - 1] != delimiter);
    return total - matching;
}

fn countRegexSelectedSparseWithWorker(
    buffer: []const u8,
    regex: *const matcher_mod.Regex,
    worker: *const matcher_mod.RegexWorker,
    invert: bool,
    delimiter: u8,
) usize {
    const prefilter = &regex.prefilter.?;
    var matching: usize = 0;
    var search_position: usize = 0;
    while (prefilter.find(buffer, search_position)) |match_position| {
        const record_start = if (std.mem.findScalarLast(
            u8,
            buffer[0..match_position],
            delimiter,
        )) |record_end| record_end + 1 else 0;
        const record_end = std.mem.findScalarPos(
            u8,
            buffer,
            match_position,
            delimiter,
        ) orelse buffer.len;
        matching += @intFromBool(worker.matches(buffer[record_start..record_end]));
        if (record_end == buffer.len) break;
        search_position = record_end + 1;
    }
    if (!invert) return matching;
    const total = if (buffer.len == 0) 0 else std.mem.countScalar(u8, buffer, delimiter) +
        @intFromBool(buffer[buffer.len - 1] != delimiter);
    return total - matching;
}

const LineCounts = struct {
    matching: usize,
    total: usize,
};

fn countLiteralLines(buffer: []const u8, literal: *const matcher_mod.Literal, delimiter: u8) LineCounts {
    if (buffer.len == 0) return .{ .matching = 0, .total = 0 };
    if (literal.pattern.len == 0) {
        if (literal.word) return countLiteralLinesFallback(buffer, literal, delimiter);
        const total = std.mem.countScalar(u8, buffer, delimiter) + @intFromBool(buffer[buffer.len - 1] != delimiter);
        return .{ .matching = total, .total = total };
    }
    if (literal.pattern.len > 32) return countLiteralLinesFallback(buffer, literal, delimiter);

    const width = 32;
    const Bytes = @Vector(width, u8);
    const delimiters_vector: Bytes = @splat(delimiter);
    const first_exact_vector: Bytes = @splat(literal.pattern[0]);
    const first_lower_vector: Bytes = @splat(std.ascii.toLower(literal.pattern[0]));
    const first_upper_vector: Bytes = @splat(std.ascii.toUpper(literal.pattern[0]));
    const last_index = literal.pattern.len - 1;
    const last_exact_vector: Bytes = @splat(literal.pattern[last_index]);
    const last_lower_vector: Bytes = @splat(std.ascii.toLower(literal.pattern[last_index]));
    const last_upper_vector: Bytes = @splat(std.ascii.toUpper(literal.pattern[last_index]));

    var matching: usize = 0;
    var total: usize = 0;
    var line_matched = false;
    var index: usize = 0;
    while (index + width + last_index <= buffer.len) : (index += width) {
        const heads: *align(1) const Bytes = @ptrCast(buffer[index..].ptr);
        const head_bytes = heads.*;
        const delimiter_mask: u32 = @bitCast(head_bytes == delimiters_vector);
        const first_exact_mask: u32 = @bitCast(head_bytes == first_exact_vector);
        const first_lower_mask: u32 = @bitCast(head_bytes == first_lower_vector);
        const first_upper_mask: u32 = @bitCast(head_bytes == first_upper_vector);
        var candidate_mask = if (literal.ignore_case)
            first_lower_mask | first_upper_mask
        else
            first_exact_mask;
        if (last_index != 0) {
            const tails: *align(1) const Bytes = @ptrCast(buffer[index + last_index ..].ptr);
            const last_exact_mask: u32 = @bitCast(tails.* == last_exact_vector);
            const last_lower_mask: u32 = @bitCast(tails.* == last_lower_vector);
            const last_upper_mask: u32 = @bitCast(tails.* == last_upper_vector);
            candidate_mask &= if (literal.ignore_case)
                last_lower_mask | last_upper_mask
            else
                last_exact_mask;
        }

        var events = delimiter_mask | candidate_mask;
        while (events != 0) {
            const offset: u5 = @intCast(@ctz(events));
            const bit = @as(u32, 1) << offset;
            if (delimiter_mask & bit != 0) {
                total += 1;
                matching += @intFromBool(line_matched);
                line_matched = false;
            } else if (!line_matched) {
                const candidate = index + @as(usize, offset);
                if (literal.eqlPattern(buffer[candidate .. candidate + literal.pattern.len]) and
                    literal.acceptsMatchAt(buffer, candidate)) line_matched = true;
            }
            events &= events - 1;
        }
    }

    while (index < buffer.len) : (index += 1) {
        if (buffer[index] == delimiter) {
            total += 1;
            matching += @intFromBool(line_matched);
            line_matched = false;
        } else if (!line_matched and index + literal.pattern.len <= buffer.len and
            literal.eqlPattern(buffer[index .. index + literal.pattern.len]) and
            literal.acceptsMatchAt(buffer, index))
        {
            line_matched = true;
        }
    }
    if (buffer[buffer.len - 1] != delimiter) {
        total += 1;
        matching += @intFromBool(line_matched);
    }
    return .{ .matching = matching, .total = total };
}

fn countLiteralLinesFallback(
    buffer: []const u8,
    literal: *const matcher_mod.Literal,
    delimiter: u8,
) LineCounts {
    var matching: usize = 0;
    var total: usize = 0;
    var line_start: usize = 0;
    while (line_start < buffer.len) {
        const line_end = std.mem.findScalarPos(u8, buffer, line_start, delimiter) orelse buffer.len;
        total += 1;
        matching += @intFromBool(literal.matches(buffer[line_start..line_end]));
        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }
    return .{ .matching = matching, .total = total };
}

fn countAlternationLines(
    buffer: []const u8,
    alternation: *const matcher_mod.LiteralAlternation,
    delimiter: u8,
) LineCounts {
    if (buffer.len == 0) return .{ .matching = 0, .total = 0 };
    const max_last = alternationFastMaxLast(alternation) orelse
        return countAlternationLinesFallback(buffer, alternation, delimiter);

    const width = 32;
    const Bytes = @Vector(width, u8);
    const delimiters_vector: Bytes = @splat(delimiter);
    var matching: usize = 0;
    var total: usize = 0;
    var line_matched = false;
    var index: usize = 0;
    while (index + width + max_last <= buffer.len) : (index += width) {
        const heads: *align(1) const Bytes = @ptrCast(buffer[index..].ptr);
        const head_bytes = heads.*;
        const delimiter_mask: u32 = @bitCast(head_bytes == delimiters_vector);
        const candidate_mask = alternationCandidateMask(buffer, index, head_bytes, alternation);

        var events = delimiter_mask | candidate_mask;
        while (events != 0) {
            const offset: u5 = @intCast(@ctz(events));
            const bit = @as(u32, 1) << offset;
            if (delimiter_mask & bit != 0) {
                total += 1;
                matching += @intFromBool(line_matched);
                line_matched = false;
            } else if (!line_matched) {
                const candidate = index + @as(usize, offset);
                line_matched = alternationMatchesAt(buffer, candidate, alternation);
            }
            events &= events - 1;
        }
    }

    while (index < buffer.len) : (index += 1) {
        if (buffer[index] == delimiter) {
            total += 1;
            matching += @intFromBool(line_matched);
            line_matched = false;
        } else if (!line_matched) {
            line_matched = alternationMatchesAt(buffer, index, alternation);
        }
    }
    if (buffer[buffer.len - 1] != delimiter) {
        total += 1;
        matching += @intFromBool(line_matched);
    }
    return .{ .matching = matching, .total = total };
}

fn alternationFastMaxLast(alternation: *const matcher_mod.LiteralAlternation) ?usize {
    var max_last: usize = 0;
    for (alternation.literals) |*literal| {
        if (literal.pattern.len == 0 or literal.pattern.len > 32 or literal.whole_line) return null;
        max_last = @max(max_last, literal.pattern.len - 1);
    }
    return max_last;
}

fn alternationContainsDelimiter(
    alternation: *const matcher_mod.LiteralAlternation,
    delimiter: u8,
) bool {
    for (alternation.literals) |literal| {
        if (std.mem.findScalar(u8, literal.pattern, delimiter) != null) return true;
    }
    return false;
}

fn alternationCandidateMask(
    buffer: []const u8,
    index: usize,
    head_bytes: @Vector(32, u8),
    alternation: *const matcher_mod.LiteralAlternation,
) u32 {
    var candidate_mask: u32 = 0;
    for (alternation.literals) |*literal| {
        candidate_mask |= if (literal.ignore_case)
            literalCandidateMaskIgnoreCase(buffer, index, head_bytes, literal)
        else
            literalCandidateMaskExact(buffer, index, head_bytes, literal);
    }
    return candidate_mask;
}

fn literalCandidateMaskExact(
    buffer: []const u8,
    index: usize,
    head_bytes: @Vector(32, u8),
    literal: *const matcher_mod.Literal,
) u32 {
    const Bytes = @Vector(32, u8);
    var mask: u32 = @bitCast(head_bytes == @as(Bytes, @splat(literal.pattern[0])));
    if (mask == 0) return 0;
    if (literal.pattern.len >= 4) {
        const off = literal.pattern.len - 4;
        inline for (0..4) |k| {
            const chunk: *align(1) const Bytes = @ptrCast(buffer[index + off + k ..].ptr);
            mask &= @bitCast(chunk.* == @as(Bytes, @splat(literal.pattern[off + k])));
        }
    } else if (literal.pattern.len > 1) {
        const last = literal.pattern.len - 1;
        const tails: *align(1) const Bytes = @ptrCast(buffer[index + last ..].ptr);
        mask &= @bitCast(tails.* == @as(Bytes, @splat(literal.pattern[last])));
    }
    return mask;
}

fn literalCandidateMaskIgnoreCase(
    buffer: []const u8,
    index: usize,
    head_bytes: @Vector(32, u8),
    literal: *const matcher_mod.Literal,
) u32 {
    const Bytes = @Vector(32, u8);
    const first_lower: Bytes = @splat(std.ascii.toLower(literal.pattern[0]));
    const first_upper: Bytes = @splat(std.ascii.toUpper(literal.pattern[0]));
    const lower_mask: u32 = @bitCast(head_bytes == first_lower);
    const upper_mask: u32 = @bitCast(head_bytes == first_upper);
    var mask = lower_mask | upper_mask;
    const last = literal.pattern.len - 1;
    if (last != 0) {
        const tails: *align(1) const Bytes = @ptrCast(buffer[index + last ..].ptr);
        const last_lower: Bytes = @splat(std.ascii.toLower(literal.pattern[last]));
        const last_upper: Bytes = @splat(std.ascii.toUpper(literal.pattern[last]));
        const last_lower_mask: u32 = @bitCast(tails.* == last_lower);
        const last_upper_mask: u32 = @bitCast(tails.* == last_upper);
        mask &= last_lower_mask | last_upper_mask;
    }
    return mask;
}

fn alternationMatchesAt(
    buffer: []const u8,
    candidate: usize,
    alternation: *const matcher_mod.LiteralAlternation,
) bool {
    const first = buffer[candidate];
    for (alternation.literals) |*literal| {
        if (!literal.ignore_case and literal.pattern[0] != first) continue;
        if (candidate + literal.pattern.len <= buffer.len and
            literal.eqlPattern(buffer[candidate .. candidate + literal.pattern.len]) and
            literal.acceptsMatchAt(buffer, candidate)) return true;
    }
    return false;
}

fn findAlternationFast(
    buffer: []const u8,
    start: usize,
    alternation: *const matcher_mod.LiteralAlternation,
    max_last: usize,
) ?usize {
    const width = 32;
    const Bytes = @Vector(width, u8);
    var index = start;
    while (index + width + max_last <= buffer.len) : (index += width) {
        const heads: *align(1) const Bytes = @ptrCast(buffer[index..].ptr);
        var candidates = alternationCandidateMask(buffer, index, heads.*, alternation);
        while (candidates != 0) {
            const offset: usize = @intCast(@ctz(candidates));
            const candidate = index + offset;
            if (alternationMatchesAt(buffer, candidate, alternation)) return candidate;
            candidates &= candidates - 1;
        }
    }
    while (index < buffer.len) : (index += 1) {
        if (alternationMatchesAt(buffer, index, alternation)) return index;
    }
    return null;
}

fn countAlternationLinesFallback(
    buffer: []const u8,
    alternation: *const matcher_mod.LiteralAlternation,
    delimiter: u8,
) LineCounts {
    var matching: usize = 0;
    var total: usize = 0;
    var line_start: usize = 0;
    while (line_start < buffer.len) {
        const line_end = std.mem.findScalarPos(u8, buffer, line_start, delimiter) orelse buffer.len;
        total += 1;
        matching += @intFromBool(alternation.matches(buffer[line_start..line_end]));
        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }
    return .{ .matching = matching, .total = total };
}

fn scanLiteralFast(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    literal: *const matcher_mod.Literal,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var search_position: usize = 0;
    var line_number: usize = 1;
    var numbered_through: usize = 0;
    while (search_position < buffer.len) {
        const match_position = literal.find(buffer, search_position) orelse break;
        if (!literal.acceptsMatchAt(buffer, match_position)) {
            search_position = match_position + @max(literal.pattern.len, 1);
            continue;
        }
        const line_start = if (std.mem.findScalarLast(u8, buffer[0..match_position], options.delimiter)) |record_end|
            record_end + 1
        else
            0;
        const line_end = if (std.mem.findScalarPos(u8, buffer, match_position, options.delimiter)) |record_end|
            record_end
        else
            buffer.len;

        if (options.line_number) {
            line_number += std.mem.countScalar(u8, buffer[numbered_through..line_start], options.delimiter);
            numbered_through = line_start;
        }

        result.matched = true;
        result.selected_lines += 1;
        if (options.quiet) return result;
        const line = buffer[line_start..line_end];
        if (!options.count and !suppressInvalidUtf8(line, options, &result))
            try emitSelectedLine(
                writer,
                path,
                options,
                if (options.line_number) line_number else null,
                if (options.byte_offset) line_start else null,
                line,
                matchers,
            );
        if (options.max_count == result.selected_lines) break;

        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(
            writer,
            path,
            options.show_filename,
            options.null_filename,
            options.colors,
            result.selected_lines,
            options.line_buffered,
        );
    return result;
}

fn scanLiteralOnlyMatchingFast(
    buffer: []const u8,
    literal: *const matcher_mod.Literal,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var search_position: usize = 0;
    var selected_line_start: ?usize = null;
    var line_number: usize = 1;
    var numbered_through: usize = 0;
    while (search_position < buffer.len) {
        const match_position = literal.find(buffer, search_position) orelse break;
        if (!literal.acceptsMatchAt(buffer, match_position)) {
            search_position = match_position + literal.pattern.len;
            continue;
        }
        const line_start = if (std.mem.findScalarLast(u8, buffer[0..match_position], options.delimiter)) |record_end|
            record_end + 1
        else
            0;
        if (selected_line_start == null or selected_line_start.? != line_start) {
            if (options.max_count == result.selected_lines) break;
            selected_line_start = line_start;
            result.matched = true;
            result.selected_lines += 1;
            if (options.line_number) {
                line_number += std.mem.countScalar(u8, buffer[numbered_through..line_start], options.delimiter);
                numbered_through = line_start;
            }
        }
        if (options.colors) |colors|
            try emitColoredMatch(
                writer,
                path,
                options.show_filename,
                if (options.line_number) line_number else null,
                if (options.byte_offset) match_position else null,
                buffer[match_position .. match_position + literal.pattern.len],
                options.delimiter,
                options.null_filename,
                options.invert,
                colors,
                options.initial_tab_width,
                options.line_buffered,
            )
        else
            try emitLine(
                writer,
                path,
                options.show_filename,
                if (options.line_number) line_number else null,
                if (options.byte_offset) match_position else null,
                buffer[match_position .. match_position + literal.pattern.len],
                options.delimiter,
                options.null_filename,
                options.initial_tab_width,
                options.line_buffered,
            );
        search_position = match_position + literal.pattern.len;
    }
    return result;
}

fn scanAlternationFast(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    alternation: *const matcher_mod.LiteralAlternation,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    const max_last = alternationFastMaxLast(alternation).?;
    var result: Result = .{};
    var search_position: usize = 0;
    var line_number: usize = 1;
    var numbered_through: usize = 0;
    while (search_position < buffer.len) {
        const match_position = findAlternationFast(buffer, search_position, alternation, max_last) orelse break;
        const line_start = if (std.mem.findScalarLast(u8, buffer[0..match_position], options.delimiter)) |record_end|
            record_end + 1
        else
            0;
        const line_end = if (std.mem.findScalarPos(u8, buffer, match_position, options.delimiter)) |record_end|
            record_end
        else
            buffer.len;
        if (options.line_number) {
            line_number += std.mem.countScalar(u8, buffer[numbered_through..line_start], options.delimiter);
            numbered_through = line_start;
        }

        result.matched = true;
        result.selected_lines += 1;
        if (options.quiet) return result;
        const line = buffer[line_start..line_end];
        if (!options.count and !suppressInvalidUtf8(line, options, &result))
            try emitSelectedLine(
                writer,
                path,
                options,
                if (options.line_number) line_number else null,
                if (options.byte_offset) line_start else null,
                line,
                matchers,
            );
        if (options.max_count == result.selected_lines) break;
        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(
            writer,
            path,
            options.show_filename,
            options.null_filename,
            options.colors,
            result.selected_lines,
            options.line_buffered,
        );
    return result;
}

fn scanRegexPrefilterFast(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    regex: *const matcher_mod.Regex,
    prefilter: *const matcher_mod.Literal,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var search_position: usize = 0;
    var line_number: usize = 1;
    var numbered_through: usize = 0;
    while (search_position < buffer.len) {
        const match_position = prefilter.find(buffer, search_position) orelse break;
        const line_start = if (std.mem.findScalarLast(u8, buffer[0..match_position], options.delimiter)) |record_end|
            record_end + 1
        else
            0;
        const line_end = if (std.mem.findScalarPos(u8, buffer, match_position, options.delimiter)) |record_end|
            record_end
        else
            buffer.len;
        const line = buffer[line_start..line_end];
        const matches = if (regex.ascii_pcre)
            regex.matchesPosix(line)
        else
            regex.matchesFull(line);
        if (matches) {
            if (options.line_number) {
                line_number += std.mem.countScalar(u8, buffer[numbered_through..line_start], options.delimiter);
                numbered_through = line_start;
            }
            result.matched = true;
            result.selected_lines += 1;
            if (options.quiet) return result;
            const suppress_output = suppressInvalidUtf8(line, options, &result);
            if (!options.count and !suppress_output) {
                if (options.only_matching) {
                    try emitSelectedOnlyMatches(
                        writer,
                        path,
                        options,
                        if (options.line_number) line_number else null,
                        line_start,
                        matchers,
                        line,
                    );
                } else {
                    try emitSelectedLine(
                        writer,
                        path,
                        options,
                        if (options.line_number) line_number else null,
                        if (options.byte_offset) line_start else null,
                        line,
                        matchers,
                    );
                }
            }
            if (options.max_count == result.selected_lines) break;
        }
        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(
            writer,
            path,
            options.show_filename,
            options.null_filename,
            options.colors,
            result.selected_lines,
            options.line_buffered,
        );
    return result;
}

fn shouldUseRegexPrefilter(buffer: []const u8, prefilter: *const matcher_mod.Literal) bool {
    const sample_len = @min(buffer.len, 1024 * 1024);
    const sample = buffer[0..sample_len];
    const dense_limit = sample_len / 512;
    var occurrences: usize = 0;
    var position: usize = 0;
    while (position < sample.len) {
        const found = prefilter.find(sample, position) orelse break;
        occurrences += 1;
        if (occurrences > dense_limit) return false;
        position = found + prefilter.pattern.len;
    }
    return true;
}

fn scanLines(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    direct_regex: ?*const matcher_mod.Regex,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var line_start: usize = 0;
    var line_number: usize = 1;

    while (line_start < buffer.len) : (line_number += 1) {
        const line_end = if (std.mem.findScalarPos(u8, buffer, line_start, options.delimiter)) |record_end|
            record_end
        else
            buffer.len;
        const line = buffer[line_start..line_end];
        const raw_match = if (direct_regex) |regex|
            regex.matchesFull(line)
        else matches: {
            for (matchers) |*matcher| {
                if (matcher.matches(line)) break :matches true;
            }
            break :matches false;
        };
        const selected = if (options.invert) !raw_match else raw_match;
        if (selected) {
            result.matched = true;
            result.selected_lines += 1;
            if (options.quiet) return result;
            const suppress_output = suppressInvalidUtf8(line, options, &result);
            if (!options.count and !suppress_output) {
                if (options.only_matching)
                    try emitSelectedOnlyMatches(
                        writer,
                        path,
                        options,
                        if (options.line_number) line_number else null,
                        line_start,
                        matchers,
                        line,
                    )
                else
                    try emitSelectedLine(
                        writer,
                        path,
                        options,
                        if (options.line_number) line_number else null,
                        if (options.byte_offset) line_start else null,
                        line,
                        matchers,
                    );
            }
            if (options.max_count == result.selected_lines) break;
        }
        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(
            writer,
            path,
            options.show_filename,
            options.null_filename,
            options.colors,
            result.selected_lines,
            options.line_buffered,
        );
    return result;
}

fn scanLinesWithContext(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var line_start: usize = 0;
    var line_number: usize = 1;
    var last_emitted_number: ?usize = null;
    var after_remaining: usize = 0;
    var matching_finished = false;

    while (line_start < buffer.len) : (line_number += 1) {
        const line_end = if (std.mem.findScalarPos(u8, buffer, line_start, options.delimiter)) |record_end|
            record_end
        else
            buffer.len;
        const line = buffer[line_start..line_end];

        var selected = false;
        if (!matching_finished) {
            var raw_match = false;
            for (matchers) |*matcher| {
                if (matcher.matches(line)) {
                    raw_match = true;
                    break;
                }
            }
            selected = if (options.invert) !raw_match else raw_match;
        }

        if (selected) {
            result.matched = true;
            result.selected_lines += 1;
            const suppress_selected = suppressInvalidUtf8(line, options, &result);

            const context_start = rewindLines(
                buffer,
                line_start,
                line_number,
                options.before_context,
                options.delimiter,
            );
            const starts_new_group = if (last_emitted_number) |last|
                context_start.number > last + 1
            else
                true;
            if (starts_new_group and (!suppress_selected or context_start.start < line_start))
                try beginContextGroup(writer, options, last_emitted_number == null);

            var prior_start = context_start.start;
            var prior_number = context_start.number;
            while (prior_start < line_start) : (prior_number += 1) {
                const prior_end = std.mem.findScalarPos(u8, buffer, prior_start, options.delimiter) orelse buffer.len;
                if (last_emitted_number == null or prior_number > last_emitted_number.?) {
                    const prior_line = buffer[prior_start..prior_end];
                    if (!suppressInvalidUtf8(prior_line, options, &result)) {
                        try emitContextLine(
                            writer,
                            path,
                            matchers,
                            options,
                            if (options.line_number) prior_number else null,
                            if (options.byte_offset) prior_start else null,
                            prior_line,
                            '-',
                            false,
                        );
                        last_emitted_number = prior_number;
                    }
                }
                if (prior_end == buffer.len) break;
                prior_start = prior_end + 1;
            }

            if (!suppress_selected) {
                try emitContextLine(
                    writer,
                    path,
                    matchers,
                    options,
                    if (options.line_number) line_number else null,
                    if (options.byte_offset) line_start else null,
                    line,
                    ':',
                    true,
                );
                last_emitted_number = line_number;
            }
            after_remaining = if (suppress_selected) 0 else options.after_context;

            if (options.max_count == result.selected_lines) {
                matching_finished = true;
                if (after_remaining == 0) break;
            }
        } else if (after_remaining > 0) {
            if (!suppressInvalidUtf8(line, options, &result)) {
                try emitContextLine(
                    writer,
                    path,
                    matchers,
                    options,
                    if (options.line_number) line_number else null,
                    if (options.byte_offset) line_start else null,
                    line,
                    '-',
                    false,
                );
                last_emitted_number = line_number;
            }
            after_remaining -= 1;
            if (matching_finished and after_remaining == 0) break;
        }

        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }
    return result;
}

fn emitContextLine(
    writer: *std.Io.Writer,
    path: []const u8,
    matchers: []const matcher_mod.Matcher,
    options: ScanOptions,
    line_number: ?usize,
    byte_offset: ?usize,
    line: []const u8,
    separator: u8,
    selected: bool,
) !void {
    if (options.colors) |colors| return emitColoredLine(
        writer,
        path,
        options.show_filename,
        line_number,
        byte_offset,
        line,
        separator,
        options.delimiter,
        options.null_filename,
        matchers,
        selected and !options.invert,
        !selected,
        options.invert,
        colors,
        options.initial_tab_width,
        options.line_buffered,
    );
    return emitDecoratedLine(
        writer,
        path,
        options.show_filename,
        line_number,
        byte_offset,
        line,
        separator,
        options.delimiter,
        options.null_filename,
        options.initial_tab_width,
        options.line_buffered,
    );
}

fn scanLiteralContextFast(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    literal: *const matcher_mod.Literal,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
    var result: Result = .{};
    var search_position: usize = 0;
    var numbered_through: usize = 0;
    var line_number: usize = 1;
    var last_selected_start: ?usize = null;
    var last_selected_number: usize = 0;
    var group_start: usize = 0;
    var group_start_number: usize = 1;
    var group_end: usize = 0;
    var has_group = false;
    var emitted_group = false;

    while (search_position < buffer.len) {
        const match_position = literal.find(buffer, search_position) orelse break;
        if (!literal.acceptsMatchAt(buffer, match_position)) {
            search_position = match_position + literal.pattern.len;
            continue;
        }
        const line_start = if (std.mem.findScalarLast(u8, buffer[0..match_position], options.delimiter)) |record_end|
            record_end + 1
        else
            0;
        const line_end = std.mem.findScalarPos(u8, buffer, match_position, options.delimiter) orelse buffer.len;
        if (last_selected_start != null and last_selected_start.? == line_start) {
            if (line_end == buffer.len) break;
            search_position = line_end + 1;
            continue;
        }

        line_number += std.mem.countScalar(u8, buffer[numbered_through..line_start], options.delimiter);
        numbered_through = line_start;
        last_selected_start = line_start;
        last_selected_number = line_number;
        result.matched = true;
        result.selected_lines += 1;

        const context_start = rewindLines(
            buffer,
            line_start,
            line_number,
            options.before_context,
            options.delimiter,
        );
        const context_end = advanceLinesEnd(buffer, line_end, options.after_context, options.delimiter);
        if (!has_group) {
            group_start = context_start.start;
            group_start_number = context_start.number;
            group_end = context_end;
            has_group = true;
        } else if (context_start.start <= group_end + @intFromBool(group_end < buffer.len)) {
            group_end = @max(group_end, context_end);
        } else {
            try beginContextGroup(writer, options, !emitted_group);
            try emitMatchedContextGroup(
                writer,
                buffer,
                matchers,
                path,
                options,
                group_start,
                group_start_number,
                group_end,
                null,
            );
            emitted_group = true;
            group_start = context_start.start;
            group_start_number = context_start.number;
            group_end = context_end;
        }

        if (options.max_count == result.selected_lines) break;
        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }

    if (has_group) {
        try beginContextGroup(writer, options, !emitted_group);
        try emitMatchedContextGroup(
            writer,
            buffer,
            matchers,
            path,
            options,
            group_start,
            group_start_number,
            group_end,
            if (options.max_count == result.selected_lines) last_selected_number else null,
        );
    }
    return result;
}

fn parallelSparseContextOutput(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !?Result {
    if (matchers.len != 1) return null;
    const parallel_matcher: ParallelOutputMatcher = switch (matchers[0]) {
        .literal => |*literal| if (!literal.whole_line and literal.pattern.len != 0)
            .{ .literal = literal }
        else
            return null,
        .alternation => |*alternation| .{ .alternation = .{
            .value = alternation,
            .max_last = alternationFastMaxLast(alternation) orelse return null,
        } },
        .regex => |*regex| regex_context: {
            const prefilter = if (regex.prefilter) |*value| value else return null;
            if (!shouldUseRegexPrefilter(buffer, prefilter)) return null;
            break :regex_context .{ .regex = .{
                .value = regex,
                .prefilter = prefilter,
            } };
        },
        .posix_regex => |*regex| posix_context: {
            if (regex.ascii_literal) |*literal| {
                if (bufferIsAscii(buffer, options) and !literal.whole_line and literal.pattern.len != 0)
                    break :posix_context .{ .literal = literal };
                return null;
            }
            if (!regex.ascii_pcre) return null;
            const prefilter = if (regex.prefilter) |*value| value else return null;
            if (!shouldUseRegexPrefilter(buffer, prefilter)) return null;
            break :posix_context .{ .regex = .{
                .value = regex,
                .prefilter = prefilter,
            } };
        },
    };
    return parallelSparseContextOutputWithLimits(
        buffer,
        matchers,
        parallel_matcher,
        path,
        options,
        writer,
        16 * 1024 * 1024,
        64 * 1024,
    );
}

fn parallelSparseContextOutputWithLimits(
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    parallel_matcher: ParallelOutputMatcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
    bytes_per_thread: usize,
    max_records_per_chunk: usize,
) !?Result {
    const max_threads = 16;
    if (buffer.len < 4 * bytes_per_thread or matchers.len != 1 or options.invert or
        options.count or options.quiet or options.list_files != null or
        options.max_count != null or options.only_matching or
        !contextOutputEnabled(options)) return null;

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    if (thread_count == 1) return null;

    var boundaries: [max_threads + 1]usize = undefined;
    boundaries[0] = 0;
    boundaries[thread_count] = buffer.len;
    for (1..thread_count) |index| {
        const nominal = buffer.len / thread_count * index;
        boundaries[index] = if (std.mem.findScalarPos(u8, buffer, nominal, options.delimiter)) |record_end|
            record_end + 1
        else
            buffer.len;
    }

    var regex_workers: [max_threads]matcher_mod.RegexWorker = undefined;
    var regex_worker_count: usize = 0;
    defer for (regex_workers[0..regex_worker_count]) |*worker| worker.deinit();
    switch (parallel_matcher) {
        .regex => |regex| for (0..thread_count) |index| {
            regex_workers[index] = regex.value.createWorker() orelse return error.OutOfMemory;
            regex_worker_count += 1;
        },
        else => {},
    }

    var chunks: [max_threads]ParallelOutputChunk = @splat(.{});
    defer for (chunks[0..thread_count]) |*chunk| chunk.deinit();
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();

    for (0..thread_count - 1) |index| {
        const regex_worker: ?*const matcher_mod.RegexWorker = switch (parallel_matcher) {
            .regex => &regex_workers[index],
            else => null,
        };
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            selectedOutputWorker,
            .{
                buffer[boundaries[index]..boundaries[index + 1]],
                parallel_matcher,
                regex_worker,
                options.delimiter,
                true,
                false,
                max_records_per_chunk,
                &chunks[index],
            },
        );
        spawned += 1;
    }
    const last_regex_worker: ?*const matcher_mod.RegexWorker = switch (parallel_matcher) {
        .regex => &regex_workers[thread_count - 1],
        else => null,
    };
    selectedOutputWorker(
        buffer[boundaries[thread_count - 1]..boundaries[thread_count]],
        parallel_matcher,
        last_regex_worker,
        options.delimiter,
        true,
        false,
        max_records_per_chunk,
        &chunks[thread_count - 1],
    );
    for (threads[0..spawned]) |thread| thread.join();

    for (chunks[0..thread_count]) |chunk| {
        if (chunk.failed or chunk.too_dense) return null;
    }

    var result: Result = .{};
    var preceding_records: usize = 0;
    var group_start: usize = 0;
    var group_start_number: usize = 1;
    var group_end: usize = 0;
    var has_group = false;
    var emitted_group = false;

    for (chunks[0..thread_count], 0..) |chunk, index| {
        for (chunk.records.items) |record| {
            const line_start = boundaries[index] + record.start;
            const line_end = boundaries[index] + record.end;
            const line_number = preceding_records + record.number;
            result.matched = true;
            result.selected_lines += 1;

            const context_start = rewindLines(
                buffer,
                line_start,
                line_number,
                options.before_context,
                options.delimiter,
            );
            const context_end = advanceLinesEnd(buffer, line_end, options.after_context, options.delimiter);
            if (!has_group) {
                group_start = context_start.start;
                group_start_number = context_start.number;
                group_end = context_end;
                has_group = true;
            } else if (context_start.start <= group_end + @intFromBool(group_end < buffer.len)) {
                group_end = @max(group_end, context_end);
            } else {
                try beginContextGroup(writer, options, !emitted_group);
                try emitMatchedContextGroup(
                    writer,
                    buffer,
                    matchers,
                    path,
                    options,
                    group_start,
                    group_start_number,
                    group_end,
                    null,
                );
                emitted_group = true;
                group_start = context_start.start;
                group_start_number = context_start.number;
                group_end = context_end;
            }
        }
        preceding_records += chunk.total_records;
    }

    if (has_group) {
        try beginContextGroup(writer, options, !emitted_group);
        try emitMatchedContextGroup(
            writer,
            buffer,
            matchers,
            path,
            options,
            group_start,
            group_start_number,
            group_end,
            null,
        );
    }
    return result;
}

fn advanceLinesEnd(buffer: []const u8, line_end: usize, count: usize, delimiter: u8) usize {
    var result = line_end;
    var remaining = count;
    while (remaining > 0 and result < buffer.len) : (remaining -= 1) {
        result = std.mem.findScalarPos(u8, buffer, result + 1, delimiter) orelse buffer.len;
    }
    return result;
}

fn emitMatchedContextGroup(
    writer: *std.Io.Writer,
    buffer: []const u8,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    group_start: usize,
    group_start_number: usize,
    group_end: usize,
    selected_through: ?usize,
) !void {
    var line_start = group_start;
    var line_number = group_start_number;
    while (line_start < buffer.len and line_start <= group_end) : (line_number += 1) {
        const line_end = std.mem.findScalarPos(u8, buffer, line_start, options.delimiter) orelse buffer.len;
        var selected = false;
        if (selected_through == null or line_number <= selected_through.?) {
            for (matchers) |*matcher| {
                if (matcher.matches(buffer[line_start..line_end])) {
                    selected = true;
                    break;
                }
            }
        }
        try emitContextLine(
            writer,
            path,
            matchers,
            options,
            if (options.line_number) line_number else null,
            if (options.byte_offset) line_start else null,
            buffer[line_start..line_end],
            if (selected) ':' else '-',
            selected,
        );
        if (line_end == buffer.len or line_end >= group_end) break;
        line_start = line_end + 1;
    }
}

const LinePosition = struct {
    start: usize,
    number: usize,
};

fn rewindLines(
    buffer: []const u8,
    line_start: usize,
    line_number: usize,
    count: usize,
    delimiter: u8,
) LinePosition {
    var result: LinePosition = .{ .start = line_start, .number = line_number };
    var remaining = count;
    while (remaining > 0 and result.start > 0) : (remaining -= 1) {
        result.start = if (std.mem.findScalarLast(u8, buffer[0 .. result.start - 1], delimiter)) |record_end|
            record_end + 1
        else
            0;
        result.number -= 1;
    }
    return result;
}

fn contextOutputEnabled(options: ScanOptions) bool {
    return (options.before_context != 0 or options.after_context != 0) and
        !options.count and !options.quiet and options.list_files == null and !options.only_matching;
}

fn beginContextGroup(writer: *std.Io.Writer, options: ScanOptions, first_in_file: bool) !void {
    var needs_separator = !first_in_file;
    if (first_in_file) if (options.context_state) |state| {
        needs_separator = state.emitted_group;
        state.emitted_group = true;
    };
    if (needs_separator) if (options.context_separator) |separator| {
        if (options.colors) |colors|
            try writeColoredValue(writer, separator, colors.separator, colors)
        else
            try writer.writeAll(separator);
        try writer.writeByte('\n');
        try finishRecord(writer, options.line_buffered);
    };
}

pub const unknown_initial_tab_width = std.fmt.comptimePrint(
    "{d}",
    .{std.math.maxInt(isize)},
).len;
const initial_tab_padding = [_]u8{' '} ** @bitSizeOf(usize);

fn finishRecord(writer: *std.Io.Writer, line_buffered: bool) !void {
    if (line_buffered) try writer.flush();
}

fn emitLine(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    line_number: ?usize,
    byte_offset: ?usize,
    line: []const u8,
    delimiter: u8,
    null_filename: bool,
    initial_tab_width: usize,
    line_buffered: bool,
) !void {
    return emitDecoratedLine(
        writer,
        path,
        show_filename,
        line_number,
        byte_offset,
        line,
        ':',
        delimiter,
        null_filename,
        initial_tab_width,
        line_buffered,
    );
}

fn emitDecoratedLine(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    line_number: ?usize,
    byte_offset: ?usize,
    line: []const u8,
    separator: u8,
    delimiter: u8,
    null_filename: bool,
    initial_tab_width: usize,
    line_buffered: bool,
) !void {
    var has_prefix = false;
    if (show_filename) {
        try writer.writeAll(path);
        try writer.writeByte(if (null_filename) 0 else separator);
        has_prefix = true;
    }
    var prefix: [2 * @bitSizeOf(usize) + 2]u8 = undefined;
    var prefix_len: usize = 0;
    if (line_number) |number| {
        const number_start = prefix_len;
        const number_len = std.fmt.printInt(prefix[number_start..], number, 10, .lower, .{});
        if (initial_tab_width != 0) {
            const padding_len = @max(2, initial_tab_width) - number_len;
            std.mem.copyBackwards(
                u8,
                prefix[number_start + padding_len .. number_start + padding_len + number_len],
                prefix[number_start .. number_start + number_len],
            );
            @memcpy(prefix[number_start .. number_start + padding_len], initial_tab_padding[0..padding_len]);
            prefix_len += padding_len;
        }
        prefix_len += number_len;
        prefix[prefix_len] = separator;
        prefix_len += 1;
        has_prefix = true;
    }
    if (byte_offset) |offset| {
        const number_start = prefix_len;
        const number_len = std.fmt.printInt(prefix[number_start..], offset, 10, .lower, .{});
        if (initial_tab_width != 0) {
            const padding_len = initial_tab_width - number_len;
            std.mem.copyBackwards(
                u8,
                prefix[number_start + padding_len .. number_start + padding_len + number_len],
                prefix[number_start .. number_start + number_len],
            );
            @memcpy(prefix[number_start .. number_start + padding_len], initial_tab_padding[0..padding_len]);
            prefix_len += padding_len;
        }
        prefix_len += number_len;
        prefix[prefix_len] = separator;
        prefix_len += 1;
        has_prefix = true;
    }
    if (prefix_len != 0) try writer.writeAll(prefix[0..prefix_len]);
    if (initial_tab_width != 0 and has_prefix) try writer.writeByte('\t');
    try writer.writeAll(line);
    try writer.writeByte(delimiter);
    try finishRecord(writer, line_buffered);
}

fn emitSelectedLine(
    writer: *std.Io.Writer,
    path: []const u8,
    options: ScanOptions,
    line_number: ?usize,
    byte_offset: ?usize,
    line: []const u8,
    matchers: []const matcher_mod.Matcher,
) !void {
    if (options.colors) |colors| return emitColoredLine(
        writer,
        path,
        options.show_filename,
        line_number,
        byte_offset,
        line,
        ':',
        options.delimiter,
        options.null_filename,
        matchers,
        !options.invert,
        false,
        options.invert,
        colors,
        options.initial_tab_width,
        options.line_buffered,
    );
    return emitLine(
        writer,
        path,
        options.show_filename,
        line_number,
        byte_offset,
        line,
        options.delimiter,
        options.null_filename,
        options.initial_tab_width,
        options.line_buffered,
    );
}

fn emitSelectedOnlyMatches(
    writer: *std.Io.Writer,
    path: []const u8,
    options: ScanOptions,
    line_number: ?usize,
    line_offset: usize,
    matchers: []const matcher_mod.Matcher,
    line: []const u8,
) !void {
    if (options.colors) |colors| return emitOnlyMatchesColored(
        writer,
        path,
        options.show_filename,
        line_number,
        line_offset,
        options.byte_offset,
        matchers,
        line,
        options.delimiter,
        options.null_filename,
        options.invert,
        colors,
        options.initial_tab_width,
        options.line_buffered,
    );
    return emitOnlyMatches(
        writer,
        path,
        options.show_filename,
        line_number,
        line_offset,
        options.byte_offset,
        matchers,
        line,
        options.delimiter,
        options.null_filename,
        options.initial_tab_width,
        options.line_buffered,
    );
}

fn writeColorStart(writer: *std.Io.Writer, code: []const u8, colors: *const ColorConfig) !void {
    try writer.writeAll("\x1b[");
    try writer.writeAll(code);
    try writer.writeByte('m');
    if (colors.erase_line) try writer.writeAll("\x1b[K");
}

fn writeColorReset(writer: *std.Io.Writer, colors: *const ColorConfig) !void {
    try writer.writeAll("\x1b[m");
    if (colors.erase_line) try writer.writeAll("\x1b[K");
}

fn writeColoredValue(
    writer: *std.Io.Writer,
    value: []const u8,
    code: []const u8,
    colors: *const ColorConfig,
) !void {
    if (code.len == 0) return writer.writeAll(value);
    try writeColorStart(writer, code, colors);
    try writer.writeAll(value);
    try writeColorReset(writer, colors);
}

pub fn emitFilename(
    writer: *std.Io.Writer,
    path: []const u8,
    null_filename: bool,
    colors: ?*const ColorConfig,
    line_buffered: bool,
) !void {
    if (colors) |config|
        try writeColoredValue(writer, path, config.filename, config)
    else
        try writer.writeAll(path);
    try writer.writeByte(if (null_filename) 0 else '\n');
    try finishRecord(writer, line_buffered);
}

fn emitColoredPrefix(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    line_number: ?usize,
    byte_offset: ?usize,
    separator: u8,
    null_filename: bool,
    colors: *const ColorConfig,
    initial_tab_width: usize,
) !void {
    const separator_bytes: [1]u8 = .{separator};
    var has_prefix = false;
    if (show_filename) {
        try writeColoredValue(writer, path, colors.filename, colors);
        if (null_filename)
            try writer.writeByte(0)
        else
            try writeColoredValue(writer, &separator_bytes, colors.separator, colors);
        has_prefix = true;
    }
    var number_buffer: [@bitSizeOf(usize)]u8 = undefined;
    if (line_number) |number| {
        var length = std.fmt.printInt(&number_buffer, number, 10, .lower, .{});
        if (initial_tab_width != 0) {
            const padding_len = @max(2, initial_tab_width) - length;
            std.mem.copyBackwards(u8, number_buffer[padding_len .. padding_len + length], number_buffer[0..length]);
            @memcpy(number_buffer[0..padding_len], initial_tab_padding[0..padding_len]);
            length += padding_len;
        }
        try writeColoredValue(writer, number_buffer[0..length], colors.line_number, colors);
        try writeColoredValue(writer, &separator_bytes, colors.separator, colors);
        has_prefix = true;
    }
    if (byte_offset) |offset| {
        var length = std.fmt.printInt(&number_buffer, offset, 10, .lower, .{});
        if (initial_tab_width != 0) {
            const padding_len = initial_tab_width - length;
            std.mem.copyBackwards(u8, number_buffer[padding_len .. padding_len + length], number_buffer[0..length]);
            @memcpy(number_buffer[0..padding_len], initial_tab_padding[0..padding_len]);
            length += padding_len;
        }
        try writeColoredValue(writer, number_buffer[0..length], colors.byte_offset, colors);
        try writeColoredValue(writer, &separator_bytes, colors.separator, colors);
        has_prefix = true;
    }
    if (initial_tab_width != 0 and has_prefix) try writer.writeByte('\t');
}

fn useContextColors(colors: *const ColorConfig, context: bool, invert: bool) bool {
    return context != (colors.reverse and invert);
}

fn emitColoredLine(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    line_number: ?usize,
    byte_offset: ?usize,
    line: []const u8,
    separator: u8,
    delimiter: u8,
    null_filename: bool,
    matchers: []const matcher_mod.Matcher,
    highlight_matches: bool,
    context: bool,
    invert: bool,
    colors: *const ColorConfig,
    initial_tab_width: usize,
    line_buffered: bool,
) !void {
    try emitColoredPrefix(
        writer,
        path,
        show_filename,
        line_number,
        byte_offset,
        separator,
        null_filename,
        colors,
        initial_tab_width,
    );
    const context_colors = useContextColors(colors, context, invert);
    const line_color = if (context_colors) colors.context_line else colors.selected_line;
    const match_color = if (context_colors) colors.context_match else colors.selected_match;
    var line_color_active = line.len != 0 and line_color.len != 0;
    if (line_color_active) try writeColorStart(writer, line_color, colors);

    var cursor: usize = 0;
    var search_position: usize = 0;
    if (highlight_matches) while (search_position <= line.len) {
        const selected = findBestMatch(matchers, line, search_position) orelse break;
        if (selected.end == selected.start) {
            if (selected.start == line.len) break;
            search_position = selected.start + 1;
            continue;
        }
        try writer.writeAll(line[cursor..selected.start]);
        if (match_color.len == 0) {
            try writer.writeAll(line[selected.start..selected.end]);
        } else {
            try writeColorStart(writer, match_color, colors);
            try writer.writeAll(line[selected.start..selected.end]);
            try writeColorReset(writer, colors);
            line_color_active = false;
            if (selected.end < line.len and line_color.len != 0) {
                try writeColorStart(writer, line_color, colors);
                line_color_active = true;
            }
        }
        cursor = selected.end;
        search_position = selected.end;
    };
    try writer.writeAll(line[cursor..]);
    if (line_color_active) try writeColorReset(writer, colors);
    try writer.writeByte(delimiter);
    try finishRecord(writer, line_buffered);
}

fn emitColoredMatch(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    line_number: ?usize,
    byte_offset: ?usize,
    match: []const u8,
    delimiter: u8,
    null_filename: bool,
    invert: bool,
    colors: *const ColorConfig,
    initial_tab_width: usize,
    line_buffered: bool,
) !void {
    try emitColoredPrefix(
        writer,
        path,
        show_filename,
        line_number,
        byte_offset,
        ':',
        null_filename,
        colors,
        initial_tab_width,
    );
    const context_colors = useContextColors(colors, false, invert);
    const line_color = if (context_colors) colors.context_line else colors.selected_line;
    const match_color = if (context_colors) colors.context_match else colors.selected_match;
    var line_color_active = line_color.len != 0;
    if (line_color_active) try writeColorStart(writer, line_color, colors);
    if (match_color.len != 0) {
        try writeColorStart(writer, match_color, colors);
        try writer.writeAll(match);
        try writeColorReset(writer, colors);
        line_color_active = false;
    } else {
        try writer.writeAll(match);
    }
    if (line_color_active) try writeColorReset(writer, colors);
    try writer.writeByte(delimiter);
    try finishRecord(writer, line_buffered);
}

fn findBestMatch(
    matchers: []const matcher_mod.Matcher,
    line: []const u8,
    search_position: usize,
) ?matcher_mod.Match {
    var best: ?matcher_mod.Match = null;
    for (matchers) |*matcher| {
        const candidate = matcher.find(line, search_position) orelse continue;
        if (best == null or candidate.start < best.?.start or
            (candidate.start == best.?.start and candidate.end > best.?.end)) best = candidate;
    }
    return best;
}

fn emitOnlyMatches(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    line_number: ?usize,
    line_offset: usize,
    show_byte_offset: bool,
    matchers: []const matcher_mod.Matcher,
    line: []const u8,
    delimiter: u8,
    null_filename: bool,
    initial_tab_width: usize,
    line_buffered: bool,
) !void {
    var search_position: usize = 0;
    while (search_position <= line.len) {
        const selected = findBestMatch(matchers, line, search_position) orelse break;
        if (selected.end > selected.start) try emitLine(
            writer,
            path,
            show_filename,
            line_number,
            if (show_byte_offset) line_offset + selected.start else null,
            line[selected.start..selected.end],
            delimiter,
            null_filename,
            initial_tab_width,
            line_buffered,
        );
        if (selected.end > selected.start) {
            search_position = selected.end;
        } else if (selected.start < line.len) {
            search_position = selected.start + 1;
        } else {
            break;
        }
    }
}

fn emitOnlyMatchesColored(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    line_number: ?usize,
    line_offset: usize,
    show_byte_offset: bool,
    matchers: []const matcher_mod.Matcher,
    line: []const u8,
    delimiter: u8,
    null_filename: bool,
    invert: bool,
    colors: *const ColorConfig,
    initial_tab_width: usize,
    line_buffered: bool,
) !void {
    var search_position: usize = 0;
    while (search_position <= line.len) {
        const selected = findBestMatch(matchers, line, search_position) orelse break;
        if (selected.end > selected.start) try emitColoredMatch(
            writer,
            path,
            show_filename,
            line_number,
            if (show_byte_offset) line_offset + selected.start else null,
            line[selected.start..selected.end],
            delimiter,
            null_filename,
            invert,
            colors,
            initial_tab_width,
            line_buffered,
        );
        if (selected.end > selected.start) {
            search_position = selected.end;
        } else if (selected.start < line.len) {
            search_position = selected.start + 1;
        } else {
            break;
        }
    }
}

pub fn emitCount(
    writer: *std.Io.Writer,
    path: []const u8,
    show_filename: bool,
    null_filename: bool,
    colors: ?*const ColorConfig,
    count: usize,
    line_buffered: bool,
) !void {
    if (show_filename) {
        if (colors) |config|
            try writeColoredValue(writer, path, config.filename, config)
        else
            try writer.writeAll(path);
        if (null_filename) {
            try writer.writeByte(0);
        } else if (colors) |config| {
            try writeColoredValue(writer, ":", config.separator, config);
        } else {
            try writer.writeByte(':');
        }
    }
    try writer.printInt(count, 10, .lower, .{});
    try writer.writeByte('\n');
    try finishRecord(writer, line_buffered);
}

test "alternation last-four probe rejects a shared prefix" {
    var alternation = (try matcher_mod.LiteralAlternation.init(
        std.testing.allocator,
        "rare-needle|status=500|route=/api/item/42|latency_us=999",
        false,
        false,
        false,
    )).?;
    defer alternation.deinit();
    const data =
        "2026 INFO route=/api/item/1 status=200 latency_us=12\n" ++
        "2026 INFO route=/api/item/42 status=500 latency_us=999 rare-needle\n" ++
        "2026 INFO route=/api/item/2 status=200 latency_us=9\n";
    try std.testing.expectEqual(1, try parallelAlternationCount(data, &alternation, false, '\n'));
    try std.testing.expectEqual(2, try parallelAlternationCount(data, &alternation, true, '\n'));
}

test "parallel literal count preserves line boundaries" {
    const literal = matcher_mod.Literal.init("needle", false, false, false);
    const data = "needle here\nno match\nneedle twice needle\nlast needle";
    try std.testing.expectEqual(3, try parallelLiteralCount(data, &literal, false, '\n'));
    try std.testing.expectEqual(1, try parallelLiteralCount(data, &literal, true, '\n'));
}

test "parallel literal count supports NUL records" {
    const literal = matcher_mod.Literal.init("needle", false, false, false);
    const data = "needle here\x00no match\x00needle twice needle\x00last needle";
    try std.testing.expectEqual(3, try parallelLiteralCount(data, &literal, false, 0));
    try std.testing.expectEqual(1, try parallelLiteralCount(data, &literal, true, 0));
}

test "parallel selected output preserves order, record numbers and byte offsets" {
    const matcher = matcher_mod.Matcher{ .literal = .init("needle", false, false, false) };
    const data = "first\nneedle two\nthird\nneedle four\nlast";
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = (try parallelSelectedOutputWithChunkBytes(
        data,
        &.{matcher},
        "input",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = true,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = true,
            .only_matching = false,
            .binary_mode = .text,
        },
        &output.writer,
        8,
    )).?;
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(2, result.selected_lines);
    try std.testing.expectEqualStrings(
        "input:2:6:needle two\ninput:4:23:needle four\n",
        output.written(),
    );
}

test "thread matcher output preserves file prefixes and record order" {
    const matcher = matcher_mod.Matcher{ .literal = .init("needle", false, false, false) };
    var thread_matcher = try matcher_mod.ThreadMatcher.init(&matcher);
    defer thread_matcher.deinit();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = try scanBufferOutputThreadMatchers(
        "first\nneedle two\nthird\nneedle four\nlast",
        &.{thread_matcher},
        "input",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = true,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = true,
            .only_matching = false,
            .binary_mode = .text,
        },
        &output.writer,
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(2, result.selected_lines);
    try std.testing.expectEqualStrings(
        "input:2:6:needle two\ninput:4:23:needle four\n",
        output.written(),
    );
}

test "thread regex prefilter fuses sparse probing and preserves dense fallback" {
    var error_buffer: [256]u8 = @splat(0);
    var matcher = try matcher_mod.Matcher.init(
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
    defer matcher.deinit();
    var thread_matcher = try matcher_mod.ThreadMatcher.init(&matcher);
    defer thread_matcher.deinit();

    const run = struct {
        fn prefilter(thread: *matcher_mod.ThreadMatcher, buffer: []const u8) ?bool {
            return switch (thread.*) {
                .regex => |*regex| threadRegexPrefilterMatches(
                    buffer,
                    regex,
                    &regex.value.prefilter.?,
                    false,
                    '\n',
                ),
                .posix_regex => |*regex| threadRegexPrefilterMatches(
                    buffer,
                    regex,
                    &regex.value.prefilter.?,
                    true,
                    '\n',
                ),
                else => unreachable,
            };
        }
    }.prefilter;

    var absent: [1024]u8 = @splat('x');
    try std.testing.expectEqual(false, run(&thread_matcher, &absent));

    var sparse = absent;
    @memcpy(sparse[100..110], "ABC_RESUME");
    try std.testing.expectEqual(true, run(&thread_matcher, &sparse));

    var dense = absent;
    @memcpy(dense[100..108], "x_RESUME");
    dense[108] = '\n';
    @memcpy(dense[300..308], "x_RESUME");
    dense[308] = '\n';
    @memcpy(dense[500..508], "x_RESUME");
    try std.testing.expectEqual(null, run(&thread_matcher, &dense));
}

test "thread matcher output suppresses invalid UTF-8 and reports a binary match" {
    const matcher = matcher_mod.Matcher{ .literal = .init("needle", false, false, false) };
    var thread_matcher = try matcher_mod.ThreadMatcher.init(&matcher);
    defer thread_matcher.deinit();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = try scanBufferOutputThreadMatchers(
        "valid needle\ninvalid\xff needle\nvalid two needle\n",
        &.{thread_matcher},
        "input",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = true,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = true,
            .only_matching = false,
            .binary_mode = .binary,
            .utf8_locale = true,
        },
        &output.writer,
    );
    try std.testing.expect(result.matched);
    try std.testing.expect(result.binary_match);
    try std.testing.expectEqual(3, result.selected_lines);
    try std.testing.expectEqualStrings(
        "input:1:0:valid needle\ninput:3:29:valid two needle\n",
        output.written(),
    );
}

test "parallel literal only-matching output counts selected records" {
    const matcher = matcher_mod.Matcher{ .literal = .init("needle", false, false, false) };
    const data = "needle needle\nnone\nx needle";
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = (try parallelSelectedOutputWithChunkBytes(
        data,
        &.{matcher},
        "input",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = false,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = true,
            .only_matching = true,
            .binary_mode = .text,
        },
        &output.writer,
        6,
    )).?;
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(2, result.selected_lines);
    try std.testing.expectEqualStrings(
        "1:0:needle\n1:7:needle\n3:21:needle\n",
        output.written(),
    );
}

test "parallel selected output falls back before emitting when metadata is capped" {
    const matcher = matcher_mod.Matcher{ .literal = .init("needle", false, false, false) };
    const data = "needle one\nneedle two\nneedle three\nneedle four\nneedle five";
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = try parallelSelectedOutputWithLimits(
        data,
        &.{matcher},
        "input",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = false,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = false,
            .only_matching = false,
            .binary_mode = .text,
        },
        &output.writer,
        8,
        0,
    );
    try std.testing.expectEqual(null, result);
    try std.testing.expectEqual(0, output.written().len);
}

test "parallel literal context preserves groups numbers and byte offsets" {
    const literal = matcher_mod.Literal.init("needle", false, false, false);
    const matchers = [_]matcher_mod.Matcher{.{ .literal = literal }};
    const data = "zero\nneedle one\nctx\nfar\naway\nneedle two\nlast";
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = (try parallelSparseContextOutputWithLimits(
        data,
        &matchers,
        .{ .literal = &literal },
        "input",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = true,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = true,
            .only_matching = false,
            .before_context = 1,
            .after_context = 1,
            .binary_mode = .text,
        },
        &output.writer,
        8,
        64,
    )).?;
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(2, result.selected_lines);
    try std.testing.expectEqualStrings(
        "input-1-0-zero\n" ++
            "input:2:5:needle one\n" ++
            "input-3-16-ctx\n" ++
            "--\n" ++
            "input-5-24-away\n" ++
            "input:6:29:needle two\n" ++
            "input-7-40-last\n",
        output.written(),
    );
}

test "parallel literal context falls back before output when metadata is capped" {
    const literal = matcher_mod.Literal.init("needle", false, false, false);
    const matchers = [_]matcher_mod.Matcher{.{ .literal = literal }};
    const data = "zero\nneedle one\nctx\nfar\nneedle two\nlast";
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = try parallelSparseContextOutputWithLimits(
        data,
        &matchers,
        .{ .literal = &literal },
        "input",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = false,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = false,
            .only_matching = false,
            .before_context = 1,
            .after_context = 1,
            .binary_mode = .text,
        },
        &output.writer,
        8,
        0,
    );
    try std.testing.expectEqual(null, result);
    try std.testing.expectEqual(0, output.written().len);
}

test "worker threads can be spawned" {
    var result: usize = 0;
    const literal = matcher_mod.Literal.init("x", false, false, false);
    const thread = try std.Thread.spawn(
        .{ .stack_size = 1024 * 1024 },
        countWorker,
        .{ "x\n", &literal, false, '\n', &result },
    );
    thread.join();
    try std.testing.expectEqual(1, result);
}

test "parallel NUL detection returns the first byte" {
    try std.testing.expectEqual(3, try findNulParallel("abc\x00def\x00"));
    try std.testing.expectEqual(null, try findNulParallel("text only"));
}

test "parallel ASCII detection rejects high bytes" {
    try std.testing.expect(try isAsciiParallel("plain ASCII"));
    try std.testing.expect(!(try isAsciiParallel("café")));
}

test "streaming scanner handles input without a final newline" {
    const matcher = matcher_mod.Matcher{ .literal = .init("needle", false, false, false) };
    var reader = std.Io.Reader.fixed("first\nneedle last");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const result = try scanReader(
        &reader,
        std.testing.allocator,
        &.{matcher},
        "stdin",
        .{
            .invert = false,
            .count = false,
            .line_number = true,
            .show_filename = false,
            .quiet = false,
            .list_files = null,
            .max_count = null,
            .byte_offset = false,
            .only_matching = false,
            .binary_mode = .binary,
        },
        &output.writer,
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualStrings("2:needle last\n", output.writer.buffered());
}
