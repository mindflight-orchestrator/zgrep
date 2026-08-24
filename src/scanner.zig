const std = @import("std");
const matcher_mod = @import("matcher.zig");
const options_mod = @import("options.zig");

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
    delimiter: u8 = '\n',
    null_filename: bool = false,
};

pub const ContextState = struct {
    emitted_group: bool = false,
};

pub const Result = struct {
    matched: bool = false,
    selected_lines: usize = 0,
    binary_match: bool = false,
};

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
        if (selected) {
            try writer.writeAll(path);
            try writer.writeByte(if (options.null_filename) 0 else '\n');
        }
        return result;
    }
    if (options.max_count == 0) {
        if (options.count) try emitCount(writer, path, options.show_filename, options.null_filename, 0);
        return .{};
    }
    if (contextOutputEnabled(options)) {
        if (matchers.len == 1 and !options.invert) switch (matchers[0]) {
            .literal => |*literal| if (!literal.whole_line and literal.pattern.len != 0)
                return scanLiteralContextFast(buffer, literal, path, options, writer),
            else => {},
        };
        return scanLinesWithContext(buffer, matchers, path, options, writer);
    }
    const needs_match_output = options.only_matching and !options.count and !options.quiet;
    if (matchers.len == 1 and !options.invert) {
        switch (matchers[0]) {
            .literal => |*literal| if (!literal.whole_line) {
                if (needs_match_output and literal.pattern.len != 0)
                    return scanLiteralOnlyMatchingFast(buffer, literal, path, options, writer);
                if (!needs_match_output) return scanLiteralFast(buffer, literal, path, options, writer);
            },
            .alternation => |*alternation| if (!needs_match_output and alternationFastMaxLast(alternation) != null) {
                return scanAlternationFast(buffer, alternation, path, options, writer);
            },
            .regex => |*regex| if (regex.prefilter) |*prefilter| {
                if (shouldUseRegexPrefilter(buffer, prefilter))
                    return scanRegexPrefilterFast(buffer, matchers, regex, prefilter, path, options, writer);
                return scanLines(buffer, matchers, regex, path, options, writer);
            },
            .posix_regex => {},
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
        if (selected) {
            try writer.writeAll(path);
            try writer.writeByte(if (options.null_filename) 0 else '\n');
        }
        return result;
    }
    if (options.max_count == 0) {
        if (options.count) try emitCount(writer, path, options.show_filename, options.null_filename, 0);
        return .{};
    }
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
            if (!options.count) if (options.only_matching)
                try emitOnlyMatches(
                    writer,
                    path,
                    options.show_filename,
                    if (options.line_number) line_number else null,
                    byte_offset,
                    options.byte_offset,
                    matchers,
                    line,
                    options.delimiter,
                    options.null_filename,
                )
            else
                try emitLine(
                    writer,
                    path,
                    options.show_filename,
                    if (options.line_number) line_number else null,
                    if (options.byte_offset) byte_offset else null,
                    line,
                    options.delimiter,
                    options.null_filename,
                );
            if (options.max_count == result.selected_lines) break;
        }
        byte_offset += line.len + @intFromBool(!reached_end);
        long_line.clearRetainingCapacity();
    }

    if (options.count and !options.quiet)
        try emitCount(writer, path, options.show_filename, options.null_filename, result.selected_lines);
    return result;
}

pub fn scanBufferQuietThreadMatchers(
    buffer: []const u8,
    matchers: []const matcher_mod.ThreadMatcher,
    options: ScanOptions,
) Result {
    if (options.max_count == 0 or buffer.len == 0) return .{};
    if (options.delimiter != 0 and options.binary_mode == .without_match and
        std.mem.findScalar(u8, buffer, 0) != null) return .{};

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
            if (matcher.matches(record)) {
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

fn shouldSummarizeBinary(options: ScanOptions) bool {
    return options.binary_mode == .binary and
        options.delimiter != 0 and !options.count and
        options.list_files == null and !options.quiet;
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
    try emitCount(writer, path, options.show_filename, options.null_filename, selected_lines);
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
    if (options.count or options.quiet or options.list_files != null or options.invert or
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
        try emitLine(
            writer,
            path,
            options.show_filename,
            if (options.line_number) line_number else null,
            if (options.byte_offset) base_offset + line_start else null,
            data[line_start..line_end],
            options.delimiter,
            options.null_filename,
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
    try emitLine(
        writer,
        path,
        options.show_filename,
        if (options.line_number) line_number else null,
        if (options.byte_offset) byte_offset else null,
        line,
        options.delimiter,
        options.null_filename,
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
) !usize {
    const bytes_per_thread = 8 * 1024 * 1024;
    const max_threads = 16;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (buffer.len + bytes_per_thread - 1) / bytes_per_thread;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    const sparse_prefilter = if (regex.prefilter) |*prefilter|
        shouldUseRegexPrefilter(buffer, prefilter)
    else
        false;
    if (thread_count == 1)
        return countRegexSelected(buffer, regex, invert, delimiter, sparse_prefilter);

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
            if (options.only_matching) return null;
            const prefilter = if (regex.prefilter) |*value| value else return null;
            if (!shouldUseRegexPrefilter(buffer, prefilter)) return null;
            break :regex_output .{ .regex = .{
                .value = regex,
                .prefilter = prefilter,
            } };
        },
        .posix_regex => return null,
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
    for (chunks[0..thread_count], 0..) |chunk, index| {
        for (chunk.records.items) |record| {
            result.matched = true;
            try emitLine(
                writer,
                path,
                options.show_filename,
                if (options.line_number) preceding_records + record.number else null,
                if (options.byte_offset) boundaries[index] + record.start else null,
                buffer[boundaries[index] + record.start .. boundaries[index] + record.end],
                options.delimiter,
                options.null_filename,
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
            .regex => if (!regex_worker.?.matches(buffer[record_start..record_end])) {
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
            .start = if (only_matching) match_position else record_start,
            .end = if (only_matching) switch (parallel_matcher) {
                .literal => |literal| match_position + literal.pattern.len,
                .alternation, .regex => unreachable,
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
            search_position = switch (parallel_matcher) {
                .literal => |literal| match_position + literal.pattern.len,
                .alternation, .regex => unreachable,
            };
            continue;
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
    result: *usize,
) void {
    result.* = countRegexSelectedWithWorker(
        buffer,
        regex,
        worker,
        invert,
        delimiter,
        sparse_prefilter,
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
) usize {
    if (sparse_prefilter)
        return countRegexSelectedSparse(buffer, regex, invert, delimiter);
    var matching: usize = 0;
    var total: usize = 0;
    var line_start: usize = 0;
    while (line_start < buffer.len) {
        const line_end = std.mem.findScalarPos(u8, buffer, line_start, delimiter) orelse buffer.len;
        total += 1;
        matching += @intFromBool(regex.matches(buffer[line_start..line_end]));
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
        matching += @intFromBool(prefilter_matches and worker.matches(line));
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

fn alternationCandidateMask(
    buffer: []const u8,
    index: usize,
    head_bytes: @Vector(32, u8),
    alternation: *const matcher_mod.LiteralAlternation,
) u32 {
    const Bytes = @Vector(32, u8);
    var candidate_mask: u32 = 0;
    for (alternation.literals) |*literal| {
        const first_exact: Bytes = @splat(literal.pattern[0]);
        const first_lower: Bytes = @splat(std.ascii.toLower(literal.pattern[0]));
        const first_upper: Bytes = @splat(std.ascii.toUpper(literal.pattern[0]));
        const exact_mask: u32 = @bitCast(head_bytes == first_exact);
        const lower_mask: u32 = @bitCast(head_bytes == first_lower);
        const upper_mask: u32 = @bitCast(head_bytes == first_upper);
        var literal_mask = if (literal.ignore_case) lower_mask | upper_mask else exact_mask;
        const last = literal.pattern.len - 1;
        if (last != 0) {
            const tails: *align(1) const Bytes = @ptrCast(buffer[index + last ..].ptr);
            const last_exact: Bytes = @splat(literal.pattern[last]);
            const last_lower: Bytes = @splat(std.ascii.toLower(literal.pattern[last]));
            const last_upper: Bytes = @splat(std.ascii.toUpper(literal.pattern[last]));
            const last_exact_mask: u32 = @bitCast(tails.* == last_exact);
            const last_lower_mask: u32 = @bitCast(tails.* == last_lower);
            const last_upper_mask: u32 = @bitCast(tails.* == last_upper);
            literal_mask &= if (literal.ignore_case)
                last_lower_mask | last_upper_mask
            else
                last_exact_mask;
        }
        candidate_mask |= literal_mask;
    }
    return candidate_mask;
}

fn alternationMatchesAt(
    buffer: []const u8,
    candidate: usize,
    alternation: *const matcher_mod.LiteralAlternation,
) bool {
    for (alternation.literals) |*literal| {
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
        if (!options.count) try emitLine(
            writer,
            path,
            options.show_filename,
            if (options.line_number) line_number else null,
            if (options.byte_offset) line_start else null,
            buffer[line_start..line_end],
            options.delimiter,
            options.null_filename,
        );
        if (options.max_count == result.selected_lines) break;

        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(writer, path, options.show_filename, options.null_filename, result.selected_lines);
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
        try emitLine(
            writer,
            path,
            options.show_filename,
            if (options.line_number) line_number else null,
            if (options.byte_offset) match_position else null,
            buffer[match_position .. match_position + literal.pattern.len],
            options.delimiter,
            options.null_filename,
        );
        search_position = match_position + literal.pattern.len;
    }
    return result;
}

fn scanAlternationFast(
    buffer: []const u8,
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
        if (!options.count) try emitLine(
            writer,
            path,
            options.show_filename,
            if (options.line_number) line_number else null,
            if (options.byte_offset) line_start else null,
            buffer[line_start..line_end],
            options.delimiter,
            options.null_filename,
        );
        if (options.max_count == result.selected_lines) break;
        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(writer, path, options.show_filename, options.null_filename, result.selected_lines);
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
        if (regex.matchesFull(line)) {
            if (options.line_number) {
                line_number += std.mem.countScalar(u8, buffer[numbered_through..line_start], options.delimiter);
                numbered_through = line_start;
            }
            result.matched = true;
            result.selected_lines += 1;
            if (options.quiet) return result;
            if (!options.count) {
                if (options.only_matching) {
                    try emitOnlyMatches(
                        writer,
                        path,
                        options.show_filename,
                        if (options.line_number) line_number else null,
                        line_start,
                        options.byte_offset,
                        matchers,
                        line,
                        options.delimiter,
                        options.null_filename,
                    );
                } else {
                    try emitLine(
                        writer,
                        path,
                        options.show_filename,
                        if (options.line_number) line_number else null,
                        if (options.byte_offset) line_start else null,
                        line,
                        options.delimiter,
                        options.null_filename,
                    );
                }
            }
            if (options.max_count == result.selected_lines) break;
        }
        if (line_end == buffer.len) break;
        search_position = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(writer, path, options.show_filename, options.null_filename, result.selected_lines);
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
            if (!options.count) if (options.only_matching)
                try emitOnlyMatches(
                    writer,
                    path,
                    options.show_filename,
                    if (options.line_number) line_number else null,
                    line_start,
                    options.byte_offset,
                    matchers,
                    line,
                    options.delimiter,
                    options.null_filename,
                )
            else
                try emitLine(
                    writer,
                    path,
                    options.show_filename,
                    if (options.line_number) line_number else null,
                    if (options.byte_offset) line_start else null,
                    line,
                    options.delimiter,
                    options.null_filename,
                );
            if (options.max_count == result.selected_lines) break;
        }
        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }

    if (options.count and !options.quiet)
        try emitCount(writer, path, options.show_filename, options.null_filename, result.selected_lines);
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
            if (starts_new_group) try beginContextGroup(writer, options, last_emitted_number == null);

            var prior_start = context_start.start;
            var prior_number = context_start.number;
            while (prior_start < line_start) : (prior_number += 1) {
                const prior_end = std.mem.findScalarPos(u8, buffer, prior_start, options.delimiter) orelse buffer.len;
                if (last_emitted_number == null or prior_number > last_emitted_number.?) {
                    try emitDecoratedLine(
                        writer,
                        path,
                        options.show_filename,
                        if (options.line_number) prior_number else null,
                        if (options.byte_offset) prior_start else null,
                        buffer[prior_start..prior_end],
                        '-',
                        options.delimiter,
                        options.null_filename,
                    );
                    last_emitted_number = prior_number;
                }
                if (prior_end == buffer.len) break;
                prior_start = prior_end + 1;
            }

            try emitDecoratedLine(
                writer,
                path,
                options.show_filename,
                if (options.line_number) line_number else null,
                if (options.byte_offset) line_start else null,
                line,
                ':',
                options.delimiter,
                options.null_filename,
            );
            last_emitted_number = line_number;
            after_remaining = options.after_context;

            if (options.max_count == result.selected_lines) {
                matching_finished = true;
                if (after_remaining == 0) break;
            }
        } else if (after_remaining > 0) {
            try emitDecoratedLine(
                writer,
                path,
                options.show_filename,
                if (options.line_number) line_number else null,
                if (options.byte_offset) line_start else null,
                line,
                '-',
                options.delimiter,
                options.null_filename,
            );
            last_emitted_number = line_number;
            after_remaining -= 1;
            if (matching_finished and after_remaining == 0) break;
        }

        if (line_end == buffer.len) break;
        line_start = line_end + 1;
    }
    return result;
}

fn scanLiteralContextFast(
    buffer: []const u8,
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
            try emitLiteralContextGroup(
                writer,
                buffer,
                literal,
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
        try emitLiteralContextGroup(
            writer,
            buffer,
            literal,
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

fn advanceLinesEnd(buffer: []const u8, line_end: usize, count: usize, delimiter: u8) usize {
    var result = line_end;
    var remaining = count;
    while (remaining > 0 and result < buffer.len) : (remaining -= 1) {
        result = std.mem.findScalarPos(u8, buffer, result + 1, delimiter) orelse buffer.len;
    }
    return result;
}

fn emitLiteralContextGroup(
    writer: *std.Io.Writer,
    buffer: []const u8,
    literal: *const matcher_mod.Literal,
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
        const selected = (selected_through == null or line_number <= selected_through.?) and
            literal.matches(buffer[line_start..line_end]);
        try emitDecoratedLine(
            writer,
            path,
            options.show_filename,
            if (options.line_number) line_number else null,
            if (options.byte_offset) line_start else null,
            buffer[line_start..line_end],
            if (selected) ':' else '-',
            options.delimiter,
            options.null_filename,
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
        try writer.writeAll(separator);
        try writer.writeByte(options.delimiter);
    };
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
) !void {
    if (show_filename) {
        try writer.writeAll(path);
        try writer.writeByte(if (null_filename) 0 else separator);
    }
    var prefix: [2 * @bitSizeOf(usize) + 2]u8 = undefined;
    var prefix_len: usize = 0;
    if (line_number) |number| {
        prefix_len += std.fmt.printInt(prefix[prefix_len..], number, 10, .lower, .{});
        prefix[prefix_len] = separator;
        prefix_len += 1;
    }
    if (byte_offset) |offset| {
        prefix_len += std.fmt.printInt(prefix[prefix_len..], offset, 10, .lower, .{});
        prefix[prefix_len] = separator;
        prefix_len += 1;
    }
    if (prefix_len != 0) try writer.writeAll(prefix[0..prefix_len]);
    try writer.writeAll(line);
    try writer.writeByte(delimiter);
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
) !void {
    var search_position: usize = 0;
    while (search_position <= line.len) {
        var best: ?matcher_mod.Match = null;
        for (matchers) |*matcher| {
            const candidate = matcher.find(line, search_position) orelse continue;
            if (best == null or candidate.start < best.?.start or
                (candidate.start == best.?.start and candidate.end > best.?.end)) best = candidate;
        }
        const selected = best orelse break;
        if (selected.end > selected.start) try emitLine(
            writer,
            path,
            show_filename,
            line_number,
            if (show_byte_offset) line_offset + selected.start else null,
            line[selected.start..selected.end],
            delimiter,
            null_filename,
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
    count: usize,
) !void {
    if (show_filename) {
        try writer.writeAll(path);
        try writer.writeByte(if (null_filename) 0 else ':');
    }
    try writer.printInt(count, 10, .lower, .{});
    try writer.writeByte('\n');
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
