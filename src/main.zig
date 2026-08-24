const std = @import("std");
const zgrep = @import("zgrep");

const version = "0.1.0";

pub fn main(init: std.process.Init) !void {
    const exit_code = run(init) catch |err| {
        var buffer: [4096]u8 = undefined;
        var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
        try stderr.interface.print("zgrep: {s}\n", .{@errorName(err)});
        try stderr.interface.flush();
        std.process.exit(2);
    };
    std.process.exit(exit_code);
}

fn run(init: std.process.Init) !u8 {
    var options = zgrep.options.Options.parse(init.minimal.args, init.gpa) catch |err| {
        var buffer: [4096]u8 = undefined;
        var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
        const exit_status: u8 = if (err == error.InvalidDirectoryMode) 1 else 2;
        switch (err) {
            error.MissingPattern => try stderr.interface.writeAll("zgrep: missing search pattern\n"),
            error.MissingOptionArgument => try stderr.interface.writeAll("zgrep: option requires an argument\n"),
            error.UnknownOption => try stderr.interface.writeAll("zgrep: unrecognized option\n"),
            error.InvalidNumber => try stderr.interface.writeAll("zgrep: invalid maximum count\n"),
            error.InvalidBinaryMode => try stderr.interface.writeAll("zgrep: invalid argument for --binary-files\n"),
            error.InvalidDirectoryMode => try stderr.interface.writeAll("zgrep: invalid argument for --directories\n"),
            error.InvalidDeviceMode => try stderr.interface.writeAll("zgrep: invalid argument for --devices\n"),
            else => return err,
        }
        try stderr.interface.writeAll("Try 'zgrep --help' for more information.\n");
        try stderr.interface.flush();
        return exit_status;
    };
    defer options.deinit(init.gpa);

    if (options.help) {
        try std.Io.File.stdout().writeStreamingAll(init.io, help_text);
        return 0;
    }
    if (options.version) {
        var buffer: [128]u8 = undefined;
        var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
        try stdout.interface.print("zgrep {s} (Zig 0.16)\n", .{version});
        try stdout.interface.flush();
        return 0;
    }

    var pattern_storage: std.ArrayList([]u8) = .empty;
    defer {
        for (pattern_storage.items) |data| init.gpa.free(data);
        pattern_storage.deinit(init.gpa);
    }
    for (options.pattern_files.items) |pattern_path| {
        const data = readPatternFile(init, pattern_path) catch |err| {
            var buffer: [4096]u8 = undefined;
            var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
            try stderr.interface.print("zgrep: {s}: {s}\n", .{ pattern_path, @errorName(err) });
            try stderr.interface.flush();
            return 2;
        };
        try pattern_storage.append(init.gpa, data);
        try appendPatterns(&options.patterns, init.gpa, data);
    }

    var filter_storage: std.ArrayList([]u8) = .empty;
    defer {
        for (filter_storage.items) |data| init.gpa.free(data);
        filter_storage.deinit(init.gpa);
    }
    var filter_rules: std.ArrayList(zgrep.filter.Rule) = .empty;
    defer filter_rules.deinit(init.gpa);
    for (options.file_filter_args.items) |filter_arg| switch (filter_arg) {
        .include => |pattern| {
            try filter_rules.append(init.gpa, .{ .pattern = pattern, .include = true });
        },
        .exclude => |pattern| try filter_rules.append(
            init.gpa,
            .{ .pattern = pattern, .include = false },
        ),
        .exclude_file => |filter_path| {
            const data = readPatternFile(init, filter_path) catch |err| {
                var buffer: [4096]u8 = undefined;
                var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
                try stderr.interface.print("zgrep: {s}: {s}\n", .{ filter_path, @errorName(err) });
                try stderr.interface.flush();
                return 2;
            };
            try filter_storage.append(init.gpa, data);
            try appendFilterRules(&filter_rules, init.gpa, data, false);
        },
    };
    const file_filters: zgrep.filter.Filters = .{
        .rules = filter_rules.items,
        .exclude_dirs = options.exclude_dirs.items,
    };

    var matchers = try init.gpa.alloc(zgrep.matcher.Matcher, options.patterns.items.len);
    defer init.gpa.free(matchers);
    var initialized: usize = 0;
    defer for (matchers[0..initialized]) |*matcher| matcher.deinit();

    for (options.patterns.items, 0..) |pattern, index| {
        var error_buffer: [256]u8 = @splat(0);
        matchers[index] = zgrep.matcher.Matcher.init(
            init.gpa,
            pattern,
            options.mode,
            options.ignore_case,
            options.line_regexp,
            options.word_regexp,
            options.only_matching,
            options.null_data,
            &error_buffer,
        ) catch |err| {
            if (err == error.InvalidRegex) {
                const message = std.mem.sliceTo(&error_buffer, 0);
                try std.Io.File.stderr().writeStreamingAll(init.io, message);
                try std.Io.File.stderr().writeStreamingAll(init.io, "\n");
                return 2;
            }
            return err;
        };
        initialized += 1;
    }

    var output_buffer: [256 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var diagnostic_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &diagnostic_buffer);

    const implicit_recursive = options.operands.items.len == 0 and options.recursive;
    if (implicit_recursive)
        try options.operands.append(init.gpa, ".");
    const file_count = options.operands.items.len;
    const show_filename = options.with_filename orelse (file_count > 1 or options.recursive);
    const stdin_path = options.label orelse "(standard input)";
    var context_state: zgrep.scanner.ContextState = .{};
    const scan_options: zgrep.scanner.ScanOptions = .{
        .invert = options.invert,
        .count = options.count,
        .line_number = options.line_number,
        .show_filename = show_filename,
        .quiet = options.quiet,
        .list_files = options.list_files,
        .max_count = options.max_count,
        .byte_offset = options.byte_offset,
        .only_matching = options.only_matching,
        .before_context = options.before_context,
        .after_context = options.after_context,
        .context_separator = options.context_separator,
        .context_state = &context_state,
        .binary_mode = options.binary_mode,
        .delimiter = if (options.null_data) 0 else '\n',
        .null_filename = options.null_filename,
    };

    var any_match = false;
    var had_error = false;
    if (file_count == 0) {
        const result: ?zgrep.scanner.Result = scanStdin(
            init,
            matchers,
            stdin_path,
            scan_options,
            &stdout.interface,
            &stderr.interface,
        ) catch |err| blk: {
            if (!options.no_messages) try stderr.interface.print("zgrep: standard input: {s}\n", .{@errorName(err)});
            had_error = true;
            break :blk null;
        };
        if (result) |value| any_match = value.matched;
    } else {
        for (options.operands.items) |path| {
            const result = if (std.mem.eql(u8, path, "-"))
                scanStdinPath(init, matchers, stdin_path, scan_options, &stdout.interface, &stderr.interface)
            else
                scanPath(
                    init,
                    path,
                    matchers,
                    scan_options,
                    file_filters,
                    implicit_recursive,
                    options.recursive,
                    options.dereference_recursive,
                    options.directory_mode == .skip,
                    options.device_mode == .skip,
                    options.no_messages,
                    &stdout.interface,
                    &stderr.interface,
                );
            const value = result catch |err| {
                if (!options.no_messages) try stderr.interface.print("zgrep: {s}: {s}\n", .{ path, @errorName(err) });
                had_error = true;
                continue;
            };
            any_match = any_match or value.matched;
            had_error = had_error or value.had_error;
            if (options.quiet and any_match) break;
        }
    }

    try stdout.interface.flush();
    try stderr.interface.flush();
    if (had_error and !(options.quiet and any_match)) return 2;
    return if (any_match) 0 else 1;
}

const PathResult = struct {
    matched: bool = false,
    had_error: bool = false,
};

fn scanStdinPath(
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !PathResult {
    const result = try scanStdin(init, matchers, path, options, writer, diagnostic_writer);
    return .{ .matched = result.matched };
}

fn scanRegularPath(
    init: std.process.Init,
    path: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !PathResult {
    const result = try scanFile(init, path, matchers, options, writer, diagnostic_writer);
    return .{ .matched = result.matched };
}

fn scanPath(
    init: std.process.Init,
    path: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    filters: zgrep.filter.Filters,
    strip_dot_prefix: bool,
    recursive: bool,
    dereference_recursive: bool,
    skip_directories: bool,
    skip_devices: bool,
    no_messages: bool,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !PathResult {
    const stat = try std.Io.Dir.cwd().statFile(init.io, path, .{});
    if (stat.kind != .directory) {
        if (skip_devices and stat.kind != .file) return .{};
        if (!filters.allowsFile(std.fs.path.basename(path))) return .{};
        const result = try scanFile(init, path, matchers, options, writer, diagnostic_writer);
        return .{ .matched = result.matched };
    }
    if (!recursive) {
        if (skip_directories) return .{};
        return error.IsDirectory;
    }
    if (!filters.allowsDir(std.fs.path.basename(path))) return .{};

    if (options.list_files != null and !options.quiet) {
        var list_ancestors = std.StringHashMap(void).init(init.gpa);
        defer list_ancestors.deinit();
        return scanDirectoryListParallel(
            init,
            path,
            matchers,
            options,
            filters,
            strip_dot_prefix,
            if (dereference_recursive) &list_ancestors else null,
            no_messages,
            writer,
            diagnostic_writer,
        );
    }

    var ancestors = std.StringHashMap(void).init(init.gpa);
    defer ancestors.deinit();
    return scanDirectory(
        init,
        path,
        matchers,
        options,
        filters,
        strip_dot_prefix,
        if (dereference_recursive) &ancestors else null,
        no_messages,
        writer,
        diagnostic_writer,
    );
}

fn scanDirectory(
    init: std.process.Init,
    path: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    filters: zgrep.filter.Filters,
    strip_dot_prefix: bool,
    ancestors: ?*std.StringHashMap(void),
    no_messages: bool,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !PathResult {
    var canonical: ?[:0]u8 = null;
    if (ancestors) |set| {
        const resolved = try std.Io.Dir.cwd().realPathFileAlloc(init.io, path, init.gpa);
        if (set.contains(resolved)) {
            if (!no_messages) try diagnostic_writer.print(
                "zgrep: {s}: warning: recursive directory loop\n",
                .{path},
            );
            init.gpa.free(resolved);
            return .{};
        }
        errdefer init.gpa.free(resolved);
        try set.put(resolved, {});
        canonical = resolved;
    }
    defer if (canonical) |resolved| {
        _ = ancestors.?.remove(resolved);
        init.gpa.free(resolved);
    };

    const directory = try std.Io.Dir.cwd().openDir(init.io, path, .{ .iterate = true });
    defer directory.close(init.io);
    var iterator = directory.iterateAssumeFirstIteration();

    var aggregate: PathResult = .{};
    while (try iterator.next(init.io)) |entry| {
        const full_path = try joinTraversalPath(init.gpa, path, entry.name, strip_dot_prefix);
        defer init.gpa.free(full_path);

        var kind = entry.kind;
        if (kind == .unknown) {
            const stat = directory.statFile(init.io, entry.name, .{ .follow_symlinks = false }) catch |err| {
                if (!no_messages) try diagnostic_writer.print("zgrep: {s}: {s}\n", .{ full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }
        if (kind == .sym_link) {
            if (ancestors == null) continue;
            const stat = directory.statFile(init.io, entry.name, .{}) catch |err| {
                if (!no_messages) try diagnostic_writer.print("zgrep: {s}: {s}\n", .{ full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }

        const result = switch (kind) {
            .file => if (filters.allowsFile(entry.name))
                scanRegularPath(init, full_path, matchers, options, writer, diagnostic_writer)
            else
                continue,
            .directory => if (filters.allowsDir(entry.name)) scanDirectory(
                init,
                full_path,
                matchers,
                options,
                filters,
                strip_dot_prefix,
                ancestors,
                no_messages,
                writer,
                diagnostic_writer,
            ) else continue,
            else => continue,
        } catch |err| {
            if (!no_messages) try diagnostic_writer.print("zgrep: {s}: {s}\n", .{ full_path, @errorName(err) });
            aggregate.had_error = true;
            continue;
        };
        aggregate.matched = aggregate.matched or result.matched;
        aggregate.had_error = aggregate.had_error or result.had_error;
        if (options.quiet and aggregate.matched) break;
    }
    return aggregate;
}

fn scanDirectoryListParallel(
    init: std.process.Init,
    path: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    filters: zgrep.filter.Filters,
    strip_dot_prefix: bool,
    ancestors: ?*std.StringHashMap(void),
    no_messages: bool,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !PathResult {
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |file_path| init.gpa.free(file_path);
        paths.deinit(init.gpa);
    }
    var aggregate: PathResult = .{};
    try collectDirectoryFiles(
        init,
        path,
        filters,
        strip_dot_prefix,
        ancestors,
        no_messages,
        diagnostic_writer,
        &paths,
        &aggregate,
    );
    if (paths.items.len == 0) return aggregate;

    const results = try init.gpa.alloc(ParallelListResult, paths.items.len);
    defer init.gpa.free(results);
    @memset(results, .{});
    var context: ParallelListContext = .{
        .init = init,
        .matchers = matchers,
        .paths = paths.items,
        .options = options,
        .results = results,
    };

    const max_threads = 16;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const useful_threads = (paths.items.len + 31) / 32;
    const thread_count = @max(1, @min(max_threads, @min(cpu_count, useful_threads)));
    var threads: [max_threads - 1]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();
    for (0..thread_count - 1) |index| {
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            parallelListWorker,
            .{&context},
        );
        spawned += 1;
    }
    parallelListWorker(&context);
    for (threads[0..spawned]) |thread| thread.join();
    if (context.setup_failed.load(.acquire)) return error.OutOfMemory;

    const want_match = options.list_files.?;
    for (paths.items, results) |file_path, result| {
        if (result.err) |err| {
            if (!no_messages)
                try diagnostic_writer.print("zgrep: {s}: {s}\n", .{ file_path, @errorName(err) });
            aggregate.had_error = true;
            continue;
        }
        aggregate.matched = aggregate.matched or result.matched;
        if (result.matched == want_match) {
            try writer.writeAll(file_path);
            try writer.writeByte(if (options.null_filename) 0 else '\n');
        }
    }
    return aggregate;
}

fn collectDirectoryFiles(
    init: std.process.Init,
    path: []const u8,
    filters: zgrep.filter.Filters,
    strip_dot_prefix: bool,
    ancestors: ?*std.StringHashMap(void),
    no_messages: bool,
    diagnostic_writer: *std.Io.Writer,
    paths: *std.ArrayList([]u8),
    aggregate: *PathResult,
) !void {
    var canonical: ?[:0]u8 = null;
    if (ancestors) |set| {
        const resolved = try std.Io.Dir.cwd().realPathFileAlloc(init.io, path, init.gpa);
        if (set.contains(resolved)) {
            if (!no_messages) try diagnostic_writer.print(
                "zgrep: {s}: warning: recursive directory loop\n",
                .{path},
            );
            init.gpa.free(resolved);
            return;
        }
        errdefer init.gpa.free(resolved);
        try set.put(resolved, {});
        canonical = resolved;
    }
    defer if (canonical) |resolved| {
        _ = ancestors.?.remove(resolved);
        init.gpa.free(resolved);
    };

    const directory = try std.Io.Dir.cwd().openDir(init.io, path, .{ .iterate = true });
    defer directory.close(init.io);
    var iterator = directory.iterateAssumeFirstIteration();
    while (try iterator.next(init.io)) |entry| {
        const full_path = try joinTraversalPath(init.gpa, path, entry.name, strip_dot_prefix);
        var keep_path = false;
        defer if (!keep_path) init.gpa.free(full_path);

        var kind = entry.kind;
        if (kind == .unknown) {
            const stat = directory.statFile(init.io, entry.name, .{ .follow_symlinks = false }) catch |err| {
                if (!no_messages)
                    try diagnostic_writer.print("zgrep: {s}: {s}\n", .{ full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }
        if (kind == .sym_link) {
            if (ancestors == null) continue;
            const stat = directory.statFile(init.io, entry.name, .{}) catch |err| {
                if (!no_messages)
                    try diagnostic_writer.print("zgrep: {s}: {s}\n", .{ full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }

        switch (kind) {
            .file => {
                if (!filters.allowsFile(entry.name)) continue;
                try paths.append(init.gpa, full_path);
                keep_path = true;
            },
            .directory => if (filters.allowsDir(entry.name)) collectDirectoryFiles(
                init,
                full_path,
                filters,
                strip_dot_prefix,
                ancestors,
                no_messages,
                diagnostic_writer,
                paths,
                aggregate,
            ) catch |err| {
                if (!no_messages)
                    try diagnostic_writer.print("zgrep: {s}: {s}\n", .{ full_path, @errorName(err) });
                aggregate.had_error = true;
            } else continue,
            else => {},
        }
    }
}

fn joinTraversalPath(
    allocator: std.mem.Allocator,
    path: []const u8,
    name: []const u8,
    strip_dot_prefix: bool,
) ![]u8 {
    if (strip_dot_prefix and std.mem.eql(u8, path, ".")) return allocator.dupe(u8, name);
    return std.fs.path.join(allocator, &.{ path, name });
}

const ParallelListResult = struct {
    matched: bool = false,
    err: ?anyerror = null,
};

const ParallelListContext = struct {
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    paths: []const []u8,
    options: zgrep.scanner.ScanOptions,
    results: []ParallelListResult,
    next: std.atomic.Value(usize) = .init(0),
    setup_failed: std.atomic.Value(bool) = .init(false),
};

fn parallelListWorker(context: *ParallelListContext) void {
    const thread_matchers = std.heap.c_allocator.alloc(
        zgrep.matcher.ThreadMatcher,
        context.matchers.len,
    ) catch {
        context.setup_failed.store(true, .release);
        return;
    };
    defer std.heap.c_allocator.free(thread_matchers);
    var initialized: usize = 0;
    defer for (thread_matchers[0..initialized]) |*matcher| matcher.deinit();
    for (context.matchers, 0..) |*matcher, index| {
        thread_matchers[index] = zgrep.matcher.ThreadMatcher.init(matcher) catch {
            context.setup_failed.store(true, .release);
            return;
        };
        initialized += 1;
    }

    var scan_options = context.options;
    scan_options.list_files = null;
    scan_options.quiet = true;
    scan_options.count = false;
    scan_options.context_state = null;
    while (true) {
        const index = context.next.fetchAdd(1, .monotonic);
        if (index >= context.paths.len) break;
        const result = scanFileThreadMatchers(
            context.init,
            context.paths[index],
            thread_matchers,
            scan_options,
        ) catch |err| {
            context.results[index].err = err;
            continue;
        };
        context.results[index].matched = result.matched;
    }
}

fn scanFileThreadMatchers(
    init: std.process.Init,
    path: []const u8,
    matchers: []const zgrep.matcher.ThreadMatcher,
    options: zgrep.scanner.ScanOptions,
) !zgrep.scanner.Result {
    const file = try std.Io.Dir.cwd().openFile(init.io, path, .{});
    defer file.close(init.io);
    const stat = try file.stat(init.io);
    if (stat.kind != .file or stat.size == 0) return .{};
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;

    const small_file_bytes = 64 * 1024;
    if (stat.size <= small_file_bytes) {
        var small_buffer: [small_file_bytes]u8 = undefined;
        const bytes_read = try file.readPositionalAll(
            init.io,
            small_buffer[0..@intCast(stat.size)],
            0,
        );
        return zgrep.scanner.scanBufferQuietThreadMatchers(
            small_buffer[0..bytes_read],
            matchers,
            options,
        );
    }

    const mapped = try std.posix.mmap(
        null,
        @intCast(stat.size),
        .{ .READ = true },
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    );
    defer std.posix.munmap(mapped);
    return zgrep.scanner.scanBufferQuietThreadMatchers(mapped, matchers, options);
}

fn scanFile(
    init: std.process.Init,
    path: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    const file = try std.Io.Dir.cwd().openFile(init.io, path, .{});
    defer file.close(init.io);
    const stat = try file.stat(init.io);
    if (stat.kind == .file and stat.size > 0) {
        if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;
        const small_file_bytes = 64 * 1024;
        if (stat.size > small_file_bytes and options.quiet and options.binary_mode != .without_match) {
            var quiet_buffer: [64 * 1024]u8 = undefined;
            var quiet_reader = file.readerStreaming(init.io, &quiet_buffer);
            return zgrep.scanner.scanReader(
                &quiet_reader.interface,
                init.gpa,
                matchers,
                path,
                options,
                writer,
            );
        }
        if (stat.size <= small_file_bytes) {
            var small_buffer: [small_file_bytes]u8 = undefined;
            const bytes_read = try file.readPositionalAll(
                init.io,
                small_buffer[0..@intCast(stat.size)],
                0,
            );
            return scanRegularBuffer(
                small_buffer[0..bytes_read],
                matchers,
                path,
                options,
                writer,
                diagnostic_writer,
            );
        }
        const mapped = try std.posix.mmap(
            null,
            @intCast(stat.size),
            .{ .READ = true },
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );
        defer std.posix.munmap(mapped);
        return scanRegularBuffer(mapped, matchers, path, options, writer, diagnostic_writer);
    }
    if (stat.kind == .file) return zgrep.scanner.scanBuffer(&.{}, matchers, path, options, writer);

    if (requiresBufferedScan(options)) {
        var read_buffer: [256 * 1024]u8 = undefined;
        var reader = file.readerStreaming(init.io, &read_buffer);
        const data = try reader.interface.allocRemaining(init.gpa, .unlimited);
        defer init.gpa.free(data);
        return scanBufferedData(data, matchers, path, options, writer, diagnostic_writer);
    }

    if (try zgrep.scanner.scanFileLiteralCount(file, init.io, init.gpa, matchers, path, options, writer)) |result| {
        return result;
    }
    if (try zgrep.scanner.scanFileLiteralOutput(file, init.io, init.gpa, matchers, path, options, writer)) |result| {
        if (result.binary_match) try diagnostic_writer.print("zgrep: {s}: binary file matches\n", .{path});
        return result;
    }
    var read_buffer: [256 * 1024]u8 = undefined;
    var reader = file.readerStreaming(init.io, &read_buffer);
    const result = try zgrep.scanner.scanReader(&reader.interface, init.gpa, matchers, path, options, writer);
    if (result.binary_match) try diagnostic_writer.print("zgrep: {s}: binary file matches\n", .{path});
    return result;
}

fn scanRegularBuffer(
    buffer: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    if (options.delimiter != 0 and options.binary_mode == .without_match) {
        if (try zgrep.scanner.findNulParallel(buffer) != null)
            return zgrep.scanner.scanBuffer(&.{}, matchers, path, options, writer);
    } else if (options.binary_mode == .binary and shouldSummarizeBinary(options)) {
        if (try zgrep.scanner.findNulParallel(buffer)) |nul_position| {
            return scanBinaryBuffer(
                buffer,
                nul_position,
                matchers,
                path,
                options,
                writer,
                diagnostic_writer,
            );
        }
    }
    if (options.count and !options.quiet and options.list_files == null and
        options.max_count == null and matchers.len == 1)
    {
        switch (matchers[0]) {
            .literal => |*literal| if (!literal.whole_line) {
                const count = try zgrep.scanner.parallelLiteralCount(
                    buffer,
                    literal,
                    options.invert,
                    options.delimiter,
                );
                try zgrep.scanner.emitCount(
                    writer,
                    path,
                    options.show_filename,
                    options.null_filename,
                    count,
                );
                return .{ .matched = count != 0, .selected_lines = count };
            },
            .alternation => |*alternation| {
                const count = try zgrep.scanner.parallelAlternationCount(
                    buffer,
                    alternation,
                    options.invert,
                    options.delimiter,
                );
                try zgrep.scanner.emitCount(
                    writer,
                    path,
                    options.show_filename,
                    options.null_filename,
                    count,
                );
                return .{ .matched = count != 0, .selected_lines = count };
            },
            .regex => |*regex| {
                const count = try zgrep.scanner.parallelRegexCount(
                    buffer,
                    regex,
                    options.invert,
                    options.delimiter,
                );
                try zgrep.scanner.emitCount(
                    writer,
                    path,
                    options.show_filename,
                    options.null_filename,
                    count,
                );
                return .{ .matched = count != 0, .selected_lines = count };
            },
            .posix_regex => {},
        }
    }
    if (try zgrep.scanner.parallelSelectedOutput(buffer, matchers, path, options, writer)) |result|
        return result;
    return zgrep.scanner.scanBuffer(buffer, matchers, path, options, writer);
}

fn scanStdin(
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    if (requiresBufferedScan(options)) {
        var read_buffer: [256 * 1024]u8 = undefined;
        var reader = std.Io.File.stdin().readerStreaming(init.io, &read_buffer);
        const data = try reader.interface.allocRemaining(init.gpa, .unlimited);
        defer init.gpa.free(data);
        return scanBufferedData(
            data,
            matchers,
            path,
            options,
            writer,
            diagnostic_writer,
        );
    }
    if (try zgrep.scanner.scanFileLiteralCount(
        std.Io.File.stdin(),
        init.io,
        init.gpa,
        matchers,
        path,
        options,
        writer,
    )) |result| return result;
    if (try zgrep.scanner.scanFileLiteralOutput(
        std.Io.File.stdin(),
        init.io,
        init.gpa,
        matchers,
        path,
        options,
        writer,
    )) |result| {
        if (result.binary_match)
            try diagnostic_writer.print("zgrep: {s}: binary file matches\n", .{path});
        return result;
    }

    var read_buffer: [256 * 1024]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &read_buffer);
    const result = try zgrep.scanner.scanReader(
        &reader.interface,
        init.gpa,
        matchers,
        path,
        options,
        writer,
    );
    if (result.binary_match)
        try diagnostic_writer.print("zgrep: {s}: binary file matches\n", .{path});
    return result;
}

fn requiresBufferedScan(options: zgrep.scanner.ScanOptions) bool {
    return contextOutputEnabled(options) or
        (options.delimiter != 0 and options.binary_mode == .without_match);
}

fn contextOutputEnabled(options: zgrep.scanner.ScanOptions) bool {
    return (options.before_context != 0 or options.after_context != 0) and
        !options.count and !options.quiet and options.list_files == null and !options.only_matching;
}

fn shouldSummarizeBinary(options: zgrep.scanner.ScanOptions) bool {
    return options.delimiter != 0 and
        !options.count and options.list_files == null and !options.quiet;
}

fn scanBufferedData(
    data: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    if (options.delimiter == 0 or options.binary_mode == .text)
        return zgrep.scanner.scanBuffer(data, matchers, path, options, writer);
    const nul_position = try zgrep.scanner.findNulParallel(data) orelse
        return zgrep.scanner.scanBuffer(data, matchers, path, options, writer);
    if (options.binary_mode == .without_match)
        return zgrep.scanner.scanBuffer(&.{}, matchers, path, options, writer);
    return scanBinaryBuffer(
        data,
        nul_position,
        matchers,
        path,
        options,
        writer,
        diagnostic_writer,
    );
}

fn scanBinaryBuffer(
    buffer: []const u8,
    nul_position: usize,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    const detection_block_bytes = 256 * 1024;
    const nominal_start = nul_position / detection_block_bytes * detection_block_bytes;
    const binary_start = if (nominal_start == 0)
        0
    else if (std.mem.findScalarLast(u8, buffer[0..nominal_start], options.delimiter)) |record_end|
        record_end + 1
    else
        0;

    if (binary_start != 0) {
        const text_result = try zgrep.scanner.scanBuffer(
            buffer[0..binary_start],
            matchers,
            path,
            options,
            writer,
        );
        if (text_result.matched) return text_result;
    }

    var quiet_options = options;
    quiet_options.quiet = true;
    quiet_options.count = false;
    quiet_options.list_files = null;
    const result = try zgrep.scanner.scanBuffer(
        buffer[binary_start..],
        matchers,
        path,
        quiet_options,
        writer,
    );
    if (result.matched) try diagnostic_writer.print("zgrep: {s}: binary file matches\n", .{path});
    return result;
}

fn readPatternFile(init: std.process.Init, path: []const u8) ![]u8 {
    const file = if (std.mem.eql(u8, path, "-"))
        std.Io.File.stdin()
    else
        try std.Io.Dir.cwd().openFile(init.io, path, .{});
    defer if (!std.mem.eql(u8, path, "-")) file.close(init.io);

    var read_buffer: [64 * 1024]u8 = undefined;
    var reader = file.readerStreaming(init.io, &read_buffer);
    return reader.interface.allocRemaining(init.gpa, .unlimited);
}

fn appendPatterns(
    patterns: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    data: []const u8,
) !void {
    var start: usize = 0;
    while (start < data.len) {
        const end = std.mem.findScalarPos(u8, data, start, '\n') orelse data.len;
        try patterns.append(allocator, data[start..end]);
        if (end == data.len) break;
        start = end + 1;
    }
}

fn appendFilterRules(
    rules: *std.ArrayList(zgrep.filter.Rule),
    allocator: std.mem.Allocator,
    data: []const u8,
    include: bool,
) !void {
    var start: usize = 0;
    while (start < data.len) {
        const end = std.mem.findScalarPos(u8, data, start, '\n') orelse data.len;
        try rules.append(allocator, .{ .pattern = data[start..end], .include = include });
        if (end == data.len) break;
        start = end + 1;
    }
}

const help_text =
    \\Usage: zgrep [OPTION]... PATTERN [FILE]...
    \\Search for PATTERN in each FILE (or standard input).
    \\
    \\Pattern syntax:
    \\  -G, --basic-regexp       use basic regular expressions (default)
    \\  -E, --extended-regexp    use extended regular expressions
    \\  -F, --fixed-strings      treat patterns as fixed strings
    \\  -P, --perl-regexp        use Perl-compatible regular expressions
    \\  -e, --regexp=PATTERN     add a search pattern
    \\  -f, --file=FILE          read patterns from FILE
    \\  -i, --ignore-case        ignore ASCII case distinctions
    \\      --no-ignore-case     restore case-sensitive matching
    \\  -w, --word-regexp        match only whole words
    \\  -x, --line-regexp        match only whole lines
    \\  -z, --null-data         end input records with NUL, not newline
    \\  -a, --text               process binary files as text
    \\  -I                       assume binary files have no matches
    \\      --binary-files=TYPE  TYPE is binary, text, or without-match
    \\
    \\Output control:
    \\  -v, --invert-match       select non-matching lines
    \\  -c, --count              print only selected-line counts
    \\  -m, --max-count=NUM      stop after NUM selected lines per file
    \\  -n, --line-number        print line numbers
    \\  -b, --byte-offset        print byte offsets
    \\  -o, --only-matching      print only non-empty matching parts
    \\  -A, --after-context=NUM  print NUM lines of trailing context
    \\  -B, --before-context=NUM print NUM lines of leading context
    \\  -C, --context=NUM        print NUM lines of output context
    \\  -H, --with-filename      print file names
    \\  -h, --no-filename        suppress file names
    \\  -Z, --null               end printed file names with NUL
    \\      --label=LABEL        use LABEL for standard input
    \\  -q, --quiet              stop after the first match
    \\  -s, --no-messages        suppress file error messages
    \\  -l, --files-with-matches print only names of matching files
    \\  -L, --files-without-match
    \\                            print only names of non-matching files
    \\  -r, --recursive          search directories recursively
    \\  -R, --dereference-recursive
    \\                            follow symbolic links recursively
    \\  -d, --directories=ACTION read, recurse, or skip directories
    \\  -D, --devices=ACTION     read or skip device operands
    \\      --include=GLOB       search only files matching GLOB
    \\      --exclude=GLOB       skip files matching GLOB
    \\      --exclude-from=FILE  read exclude globs from FILE
    \\      --exclude-dir=GLOB   skip directories matching GLOB
    \\      --help               display this help
    \\      --version            display version information
    \\  -V                       same as --version
;
