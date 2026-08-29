const std = @import("std");
const zgrep = @import("zgrep");

const version = "0.4.0";

const FileId = struct { ino: u64, dev: u64 };

var diagnostic_name: []const u8 = "zgr";
var stdout_identity: ?FileId = null;

fn writeDiagnostic(writer: *std.Io.Writer, path: ?[]const u8, msg: []const u8) !void {
    try writer.writeAll(diagnostic_name);
    try writer.writeAll(": ");
    if (path) |value| {
        try writer.writeAll(value);
        try writer.writeAll(": ");
    }
    try writer.writeAll(msg);
    try writer.writeByte('\n');
}

fn errnoMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.NoSpaceLeft => "write error: No space left on device",
        error.WriteFailed => "write error: No space left on device",
        error.BrokenPipe => "write error: Broken pipe",
        error.FileNotFound => "No such file or directory",
        error.IsDirectory => "Is a directory",
        error.AccessDenied => "Permission denied",
        error.InputIsOutput => "input file is also the output",
        error.MatchLimit => "Exceeded PCRE2 match limit",
        else => @errorName(err),
    };
}

pub fn main(init: std.process.Init) !void {
    const exit_code = run(init) catch |err| {
        var buffer: [4096]u8 = undefined;
        var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
        try writeDiagnostic(&stderr.interface, null, errnoMessage(err));
        try stderr.interface.flush();
        std.process.exit(2);
    };
    std.process.exit(exit_code);
}

fn run(init: std.process.Init) !u8 {
    diagnostic_name = programNameFromArgs(init.minimal.args);
    const utf8_locale = zgrep.matcher.initializeLocale();
    var options = zgrep.options.Options.parse(init.minimal.args, init.gpa) catch |err| {
        var buffer: [4096]u8 = undefined;
        var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
        const exit_status: u8 = if (err == error.InvalidDirectoryMode) 1 else 2;
        switch (err) {
            error.MissingPattern => try writeDiagnostic(&stderr.interface, null, "missing search pattern"),
            error.MissingOptionArgument => try writeDiagnostic(&stderr.interface, null, "option requires an argument"),
            error.UnknownOption => try writeDiagnostic(&stderr.interface, null, "unrecognized option"),
            error.InvalidNumber => try writeDiagnostic(&stderr.interface, null, "invalid maximum count"),
            error.InvalidBinaryMode => try writeDiagnostic(&stderr.interface, null, "invalid argument for --binary-files"),
            error.InvalidDirectoryMode => try writeDiagnostic(&stderr.interface, null, "invalid argument for --directories"),
            error.InvalidDeviceMode => try writeDiagnostic(&stderr.interface, null, "invalid argument for --devices"),
            else => return err,
        }
        var hint_buf: [96]u8 = undefined;
        const hint = std.fmt.bufPrint(
            &hint_buf,
            "Try '{s} --help' for more information.\n",
            .{diagnostic_name},
        ) catch "Try 'zgr --help' for more information.\n";
        try stderr.interface.writeAll(hint);
        try stderr.interface.flush();
        return exit_status;
    };
    defer options.deinit(init.gpa);

    if (options.help) {
        try std.Io.File.stdout().writeStreamingAll(init.io, help_text);
        return 0;
    }
    if (options.version) {
        var name_buf: [96]u8 = undefined;
        const printed_version = std.fmt.bufPrint(
            &name_buf,
            "{s} {s} (Zig 0.16)\n",
            .{ diagnostic_name, version },
        ) catch "zgr " ++ version ++ " (Zig 0.16)\n";
        try std.Io.File.stdout().writeStreamingAll(init.io, printed_version);
        var ver_buf: [128]u8 = undefined;
        const pcre_line = std.fmt.bufPrint(
            &ver_buf,
            "{s} -P uses PCRE2 {s}\n",
            .{ diagnostic_name, std.mem.span(zgrep.matcher.pcre2Version()) },
        ) catch "grep -P uses PCRE2 10\n";
        try std.Io.File.stdout().writeStreamingAll(init.io, pcre_line);
        return 0;
    }

    var pattern_storage: std.ArrayList([]u8) = .empty;
    defer {
        for (pattern_storage.items) |data| init.gpa.free(data);
        pattern_storage.deinit(init.gpa);
    }
    var pattern_origins: std.ArrayList(struct { path: []const u8, first: usize, count: usize }) = .empty;
    defer pattern_origins.deinit(init.gpa);
    for (options.pattern_files.items) |pattern_path| {
        const data = readPatternFile(init, pattern_path) catch |err| {
            var buffer: [4096]u8 = undefined;
            var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
            try writeDiagnostic(&stderr.interface, pattern_path, errnoMessage(err));
            try stderr.interface.flush();
            return 2;
        };
        try pattern_storage.append(init.gpa, data);
        const first = options.patterns.items.len;
        try appendPatterns(&options.patterns, init.gpa, data);
        try pattern_origins.append(init.gpa, .{
            .path = pattern_path,
            .first = first,
            .count = options.patterns.items.len - first,
        });
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
                try writeDiagnostic(&stderr.interface, filter_path, errnoMessage(err));
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

    var compiled_matchers: std.ArrayList(zgrep.matcher.Matcher) = .empty;
    defer {
        for (compiled_matchers.items) |*matcher| matcher.deinit();
        compiled_matchers.deinit(init.gpa);
    }
    var seen_patterns = std.StringHashMap(void).init(init.gpa);
    defer seen_patterns.deinit();
    var compile_failed = false;
    for (options.patterns.items, 0..) |pattern, index| {
        if (seen_patterns.contains(pattern)) continue;
        try seen_patterns.put(pattern, {});
        var error_buffer: [256]u8 = @splat(0);
        const matcher = zgrep.matcher.Matcher.init(
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
                var found_origin: ?struct { path: []const u8, line: usize } = null;
                for (pattern_origins.items) |origin| {
                    if (index >= origin.first and index < origin.first + origin.count) {
                        found_origin = .{ .path = origin.path, .line = index - origin.first + 1 };
                        break;
                    }
                }
                var err_buf: [4096]u8 = undefined;
                var err_writer = std.Io.File.stderr().writerStreaming(init.io, &err_buf);
                if (found_origin) |origin| {
                    if (std.mem.eql(u8, message, "stack overflow")) {
                        try writeDiagnostic(&err_writer.interface, null, message);
                    } else {
                        try err_writer.interface.print(
                            "{s}: {s}:{d}: {s}\n",
                            .{ diagnostic_name, origin.path, origin.line, message },
                        );
                    }
                } else {
                    try writeDiagnostic(&err_writer.interface, null, message);
                }
                try err_writer.interface.flush();
                compile_failed = true;
                continue;
            }
            return err;
        };
        try compiled_matchers.append(init.gpa, matcher);
    }
    if (compile_failed) return 2;
    const matchers = compiled_matchers.items;

    const stdout_file = std.Io.File.stdout();
    var output_buffer: [256 * 1024]u8 = undefined;
    var stdout = stdout_file.writerStreaming(init.io, &output_buffer);
    var diagnostic_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &diagnostic_buffer);

    const implicit_recursive = options.operands.items.len == 0 and options.recursive;
    if (implicit_recursive)
        try options.operands.append(init.gpa, ".");
    const file_count = options.operands.items.len;
    const show_filename = options.with_filename orelse (file_count > 1 or options.recursive);
    const stdin_path = options.label orelse "(standard input)";
    const color_enabled = if (options.color) |mode| switch (mode) {
        .always => true,
        .never => false,
        .auto => stdout_file.isTty(init.io) catch false,
    } else false;
    const color_config = zgrep.scanner.ColorConfig.fromEnvironment(init.environ_map);
    if (color_enabled and zgrep.scanner.ColorConfig.grepColorIsSet(init.environ_map)) {
        const color = init.environ_map.get("GREP_COLOR") orelse "";
        try stderr.interface.print(
            "{s}: warning: GREP_COLOR='{s}' is deprecated; use GREP_COLORS='mt={s}'\n",
            .{ diagnostic_name, color, color },
        );
    }
    var context_state: zgrep.scanner.ContextState = .{};
    const skip_contents = options.max_count == 0 or
        (options.patterns.items.len == 0 and !options.invert) or
        (options.invert and matchersMatchEveryLine(matchers));
    const stdout_id = regularFileId(stdout_file.handle);
    stdout_identity = stdout_id;
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
        .context_requested = options.context_requested,
        .context_separator = options.context_separator,
        .context_state = &context_state,
        .binary_mode = options.binary_mode,
        .line_buffered = options.line_buffered,
        .initial_tab_width = if (options.initial_tab)
            zgrep.scanner.unknown_initial_tab_width
        else
            0,
        .utf8_locale = utf8_locale,
        .delimiter = if (options.null_data) 0 else '\n',
        .null_filename = options.null_filename,
        .colors = if (color_enabled) &color_config else null,
        .skip_contents = skip_contents,
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
            if (err == error.WriteFailed) return stdout.err orelse err;
            if (!options.no_messages) try writeDiagnostic(&stderr.interface, "standard input", errnoMessage(err));
            had_error = true;
            break :blk null;
        };
        if (result) |value| {
            any_match = value.matched;
            if (value.match_error) had_error = true;
        }
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
                    options.device_mode,
                    options.no_messages,
                    &stdout.interface,
                    &stderr.interface,
                );
            const value = result catch |err| {
                if (err == error.WriteFailed) return stdout.err orelse err;
                if (!options.no_messages) try writeDiagnostic(&stderr.interface, path, errnoMessage(err));
                had_error = true;
                continue;
            };
            any_match = any_match or value.matched;
            had_error = had_error or value.had_error;
            if (options.quiet and any_match) break;
        }
    }

    try stdout.flush();
    try stderr.flush();
    if (had_error and !(options.quiet and any_match)) return 2;
    return if (any_match) 0 else 1;
}

const PathResult = struct {
    matched: bool = false,
    had_error: bool = false,
};

fn programNameFromArgs(args: std.process.Args) []const u8 {
    var it = std.process.Args.Iterator.init(args);
    const argv0 = it.next() orelse return "zgr";
    const base = std.fs.path.basename(argv0);
    return if (base.len == 0) "zgr" else base;
}

fn matchersMatchEveryLine(matchers: []const zgrep.matcher.Matcher) bool {
    if (matchers.len == 0) return false;
    for (matchers) |matcher| switch (matcher) {
        .literal => |literal| if (literal.pattern.len != 0) return false,
        else => return false,
    };
    return true;
}

fn sameFile(a: FileId, b: FileId) bool {
    return a.ino == b.ino and a.dev == b.dev;
}

fn regularFileId(fd: std.posix.fd_t) ?FileId {
    var stx: std.os.linux.Statx = undefined;
    const rc = std.os.linux.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        .BASIC_STATS,
        &stx,
    );
    if (std.posix.errno(rc) != .SUCCESS) return null;
    if ((stx.mode & std.os.linux.S.IFMT) != std.os.linux.S.IFREG) return null;
    return .{
        .ino = stx.ino,
        .dev = (@as(u64, stx.dev_major) << 32) | stx.dev_minor,
    };
}

fn shouldRejectSameFile(options: zgrep.scanner.ScanOptions) bool {
    if (options.quiet or options.list_files != null) return false;
    if (options.max_count) |limit| if (limit <= 1) return false;
    return true;
}

fn isDotPath(path: []const u8) bool {
    return std.mem.eql(u8, path, ".") or std.mem.eql(u8, path, "./");
}

fn shouldStreamAndStop(options: zgrep.scanner.ScanOptions) bool {
    return options.quiet or options.list_files != null or options.max_count != null;
}

fn rejectIfSameFile(
    file: std.Io.File,
    options: zgrep.scanner.ScanOptions,
    path: []const u8,
    diagnostic_writer: *std.Io.Writer,
) !?zgrep.scanner.Result {
    if (!shouldRejectSameFile(options)) return null;
    const out_id = stdout_identity orelse return null;
    const in_id = regularFileId(file.handle) orelse return null;
    if (!sameFile(out_id, in_id)) return null;
    try writeDiagnostic(diagnostic_writer, path, "input file is also the output");
    return .{ .match_error = true };
}

fn annotateMatchError(
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    diagnostic_writer: *std.Io.Writer,
    result: zgrep.scanner.Result,
) !zgrep.scanner.Result {
    var out = result;
    for (matchers) |*matcher| {
        if (matcher.hadMatchError()) {
            out.match_error = true;
            try writeDiagnostic(diagnostic_writer, path, "exceeded PCRE's backtracking limit");
            break;
        }
    }
    return out;
}

fn emitSkipContentsName(
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    if (options.list_files == false) {
        try zgrep.scanner.emitFilename(
            writer,
            path,
            options.null_filename,
            options.colors,
            options.line_buffered,
        );
    }
    return .{};
}

fn scanFileStreaming(
    init: std.process.Init,
    file: std.Io.File,
    path: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    var read_buffer: [256 * 1024]u8 = undefined;
    var reader = file.readerStreaming(init.io, &read_buffer);
    const result = try zgrep.scanner.scanReader(
        &reader.interface,
        init.gpa,
        matchers,
        path,
        options,
        writer,
    );
    if (result.binary_match)
        try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
    zgrep.scanner.rewindUnread(file, result.leftover_bytes);
    return annotateMatchError(matchers, path, diagnostic_writer, result);
}

fn scanStdinPath(
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !PathResult {
    const result = try scanStdin(init, matchers, path, options, writer, diagnostic_writer);
    return .{ .matched = result.matched, .had_error = result.match_error };
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
    return .{ .matched = result.matched, .had_error = result.match_error };
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
    device_mode: zgrep.options.DeviceMode,
    no_messages: bool,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !PathResult {
    if (options.skip_contents) {
        _ = try emitSkipContentsName(path, options, writer);
        return .{};
    }
    const stat = try std.Io.Dir.cwd().statFile(init.io, path, .{});
    if (stat.kind != .directory) {
        if (device_mode == .skip and stat.kind != .file) return .{};
        if (!filters.allowsFile(path)) return .{};
        const result = try scanFile(init, path, matchers, options, writer, diagnostic_writer);
        return .{ .matched = result.matched, .had_error = result.match_error };
    }
    if (!recursive) {
        if (skip_directories) return .{};
        return error.IsDirectory;
    }
    if (!isDotPath(path) and !filters.allowsDir(path)) return .{};

    if (options.list_files != null and !options.quiet and device_mode != .read) {
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
    if (parallelRecursiveOutputEligible(options) and device_mode != .read) {
        var output_ancestors = std.StringHashMap(void).init(init.gpa);
        defer output_ancestors.deinit();
        return scanDirectoryOutputParallel(
            init,
            path,
            matchers,
            options,
            filters,
            strip_dot_prefix,
            if (dereference_recursive) &output_ancestors else null,
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
        device_mode,
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
    device_mode: zgrep.options.DeviceMode,
    ancestors: ?*std.StringHashMap(void),
    no_messages: bool,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) anyerror!PathResult {
    var canonical: ?[:0]u8 = null;
    if (ancestors) |set| {
        const resolved = try std.Io.Dir.cwd().realPathFileAlloc(init.io, path, init.gpa);
        if (set.contains(resolved)) {
            if (!no_messages) try diagnostic_writer.print(
                "{s}: {s}: warning: recursive directory loop\n",
                .{ diagnostic_name, path },
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
                if (!no_messages) try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }
        if (kind == .sym_link) {
            if (ancestors == null) continue;
            const stat = directory.statFile(init.io, entry.name, .{}) catch |err| {
                if (!no_messages) try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }

        const result = switch (kind) {
            .file => if (filters.allowsFile(full_path))
                scanRegularPath(init, full_path, matchers, options, writer, diagnostic_writer)
            else
                continue,
            .directory => if (filters.allowsDir(full_path)) scanDirectory(
                init,
                full_path,
                matchers,
                options,
                filters,
                strip_dot_prefix,
                device_mode,
                ancestors,
                no_messages,
                writer,
                diagnostic_writer,
            ) else continue,
            else => if (device_mode == .read and filters.allowsFile(full_path))
                scanRegularPath(init, full_path, matchers, options, writer, diagnostic_writer)
            else
                continue,
        } catch |err| {
            if (!no_messages) try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, full_path, @errorName(err) });
            aggregate.had_error = true;
            continue;
        };
        aggregate.matched = aggregate.matched or result.matched;
        aggregate.had_error = aggregate.had_error or result.had_error;
        if (options.quiet and aggregate.matched) break;
    }
    return aggregate;
}

fn parallelRecursiveOutputEligible(options: zgrep.scanner.ScanOptions) bool {
    return !options.count and !options.quiet and options.list_files == null and
        options.max_count == null and !options.only_matching and
        options.before_context == 0 and options.after_context == 0 and
        options.colors == null and !options.line_buffered;
}

fn scanDirectoryOutputParallel(
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
    var path_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer path_arena.deinit();
    var items: std.ArrayList(*ParallelListItem) = .empty;
    defer items.deinit(init.gpa);
    defer for (items.items) |item| {
        if (item.output) |output| std.heap.c_allocator.free(output);
    };
    var discovery: ParallelListPipeline = undefined;
    discovery.init(init, matchers, options);
    discovery.context.capture_output = true;
    var collector: ParallelListCollector = .{
        .init = init,
        .items = &items,
        .pipeline = &discovery,
    };
    errdefer discovery.abort();
    var aggregate: PathResult = .{};
    try collectDirectoryFiles(
        init,
        path_arena.allocator(),
        null,
        path,
        filters,
        strip_dot_prefix,
        ancestors,
        no_messages,
        diagnostic_writer,
        &collector,
        &aggregate,
    );
    if (items.items.len == 0) return aggregate;

    const cpu_count = std.Thread.getCpuCount() catch 1;
    if (discovery.started) {
        try discovery.finish();
        if (discovery.context.setup_failed.load(.acquire)) return error.OutOfMemory;

        var matching_items: std.ArrayList(*ParallelListItem) = .empty;
        defer matching_items.deinit(init.gpa);
        var all_matching_captured = true;
        for (items.items) |item| {
            if (item.result.err) |err| {
                if (!no_messages)
                    try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, item.path, @errorName(err) });
                aggregate.had_error = true;
            } else if (item.result.matched) {
                try matching_items.append(init.gpa, item);
                all_matching_captured = all_matching_captured and item.output != null;
            }
        }
        if (matching_items.items.len == 0) return aggregate;
        if (all_matching_captured) {
            for (matching_items.items) |item| {
                try writer.writeAll(item.output.?[0..item.output_len]);
                if (item.output_binary_match)
                    try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, item.path });
            }
            aggregate.matched = true;
            return aggregate;
        }

        for (matching_items.items) |item| {
            const output = item.output orelse continue;
            std.heap.c_allocator.free(output);
            item.output = null;
            item.output_len = 0;
            item.output_binary_match = false;
        }

        const sparse_rescan_max = 16;
        if (matching_items.items.len <= sparse_rescan_max) {
            for (matching_items.items) |item| {
                const result = scanFile(
                    init,
                    item.path,
                    matchers,
                    options,
                    writer,
                    diagnostic_writer,
                ) catch |err| {
                    if (!no_messages)
                        try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, item.path, @errorName(err) });
                    aggregate.had_error = true;
                    continue;
                };
                aggregate.matched = aggregate.matched or result.matched;
            }
            return aggregate;
        }

        try scanCollectedOutputParallel(
            init,
            matching_items.items,
            matchers,
            options,
            @min(parallelListThreadLimit(matchers), cpu_count),
            no_messages,
            writer,
            diagnostic_writer,
            &aggregate,
        );
        return aggregate;
    }

    var benefits_from_parallelism = false;
    for (matchers) |*matcher| {
        if (matcher.benefitsFromLargeFileListParallelism()) {
            benefits_from_parallelism = true;
            break;
        }
    }
    if (items.items.len < 32 or cpu_count < 2 or !benefits_from_parallelism) {
        for (items.items) |item| {
            const result = scanFile(
                init,
                item.path,
                matchers,
                options,
                writer,
                diagnostic_writer,
            ) catch |err| {
                if (!no_messages)
                    try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, item.path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            aggregate.matched = aggregate.matched or result.matched;
        }
        return aggregate;
    }

    try scanCollectedOutputParallel(
        init,
        items.items,
        matchers,
        options,
        @min(parallelListThreadLimit(matchers), cpu_count),
        no_messages,
        writer,
        diagnostic_writer,
        &aggregate,
    );
    return aggregate;
}

const parallel_output_slot_count = 256;
const parallel_output_slot_bytes = 64 * 1024;
// Captured payload is globally bounded; each worker only keeps one temporary
// per-file buffer before reserving the exact number of bytes it produced.
const parallel_output_capture_bytes = parallel_output_slot_count * parallel_output_slot_bytes;
const ParallelOutputQueue = std.Io.Queue(*ParallelOutputTask);

const ParallelOutputTask = struct {
    item: *ParallelListItem = undefined,
    buffer: []u8 = undefined,
    output_len: usize = 0,
    result: zgrep.scanner.Result = .{},
    err: ?anyerror = null,
    fallback: bool = false,
    ready: std.atomic.Value(bool) = .init(false),

    fn prepare(self: *ParallelOutputTask, item: *ParallelListItem) void {
        self.item = item;
        self.output_len = 0;
        self.result = .{};
        self.err = null;
        self.fallback = false;
        self.ready.store(false, .monotonic);
    }
};

const ParallelOutputContext = struct {
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    queue: *ParallelOutputQueue,
};

fn scanCollectedOutputParallel(
    init: std.process.Init,
    items: []const *ParallelListItem,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    thread_count: usize,
    no_messages: bool,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
    aggregate: *PathResult,
) !void {
    const storage = try init.gpa.alloc(
        u8,
        parallel_output_capture_bytes,
    );
    defer init.gpa.free(storage);
    var tasks: [parallel_output_slot_count]ParallelOutputTask = undefined;
    for (&tasks, 0..) |*task, index| {
        task.* = .{
            .buffer = storage[index * parallel_output_slot_bytes ..][0..parallel_output_slot_bytes],
        };
    }

    var queue_buffer: [parallel_output_slot_count]*ParallelOutputTask = undefined;
    var queue: ParallelOutputQueue = .init(&queue_buffer);
    var context: ParallelOutputContext = .{
        .init = init,
        .matchers = matchers,
        .options = options,
        .queue = &queue,
    };
    var threads: [parallel_list_max_threads]std.Thread = undefined;
    var spawned: usize = 0;
    var joined = false;
    defer if (!joined) {
        queue.close(init.io);
        for (threads[0..spawned]) |thread| thread.join();
    };
    for (0..thread_count) |index| {
        threads[index] = try std.Thread.spawn(
            .{ .stack_size = 1024 * 1024 },
            parallelOutputWorker,
            .{&context},
        );
        spawned += 1;
    }

    const initial_count = @min(items.len, parallel_output_slot_count);
    for (0..initial_count) |index| {
        tasks[index].prepare(items[index]);
        try enqueueParallelOutputTask(init.io, &queue, &tasks[index]);
    }

    for (items, 0..) |item, index| {
        const task = &tasks[index % parallel_output_slot_count];
        var spin_count: usize = 0;
        while (!task.ready.load(.acquire)) {
            if (spin_count < 64) {
                std.atomic.spinLoopHint();
                spin_count += 1;
            } else {
                std.Thread.yield() catch {};
                spin_count = 0;
            }
        }
        std.debug.assert(task.item == item);
        if (task.fallback) {
            const result = scanFile(
                init,
                item.path,
                matchers,
                options,
                writer,
                diagnostic_writer,
            ) catch |err| {
                if (!no_messages)
                    try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, item.path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            aggregate.matched = aggregate.matched or result.matched;
        } else if (task.err) |err| {
            if (!no_messages)
                try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, item.path, @errorName(err) });
            aggregate.had_error = true;
        } else {
            try writer.writeAll(task.buffer[0..task.output_len]);
            if (task.result.binary_match)
                try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, item.path });
            aggregate.matched = aggregate.matched or task.result.matched;
        }

        const next_index = index + parallel_output_slot_count;
        if (next_index < items.len) {
            task.prepare(items[next_index]);
            try enqueueParallelOutputTask(init.io, &queue, task);
        }
    }
    queue.close(init.io);
    for (threads[0..spawned]) |thread| thread.join();
    joined = true;
}

fn enqueueParallelOutputTask(
    io: std.Io,
    queue: *ParallelOutputQueue,
    task: *ParallelOutputTask,
) !void {
    var one = [_]*ParallelOutputTask{task};
    const queued = try queue.putUncancelable(io, &one, 1);
    std.debug.assert(queued == 1);
}

fn parallelOutputWorker(context: *ParallelOutputContext) void {
    const thread_matchers = std.heap.c_allocator.alloc(
        zgrep.matcher.ThreadMatcher,
        context.matchers.len,
    ) catch {
        parallelOutputDrainFallback(context);
        return;
    };
    defer std.heap.c_allocator.free(thread_matchers);
    var initialized: usize = 0;
    defer for (thread_matchers[0..initialized]) |*matcher| matcher.deinit();
    for (context.matchers, 0..) |*matcher, index| {
        thread_matchers[index] = zgrep.matcher.ThreadMatcher.init(matcher) catch {
            parallelOutputDrainFallback(context);
            return;
        };
        initialized += 1;
    }

    var batch: [parallel_list_dequeue_batch]*ParallelOutputTask = undefined;
    while (true) {
        const count = context.queue.getUncancelable(context.init.io, &batch, 1) catch break;
        for (batch[0..count]) |task| {
            var output = std.Io.Writer.fixed(task.buffer);
            task.result = scanFileOutputThreadMatchers(
                context.init,
                task.item.path,
                thread_matchers,
                context.options,
                &output,
            ) catch |err| {
                if (err == error.WriteFailed or err == error.BinaryInput)
                    task.fallback = true
                else
                    task.err = err;
                task.ready.store(true, .release);
                continue;
            };
            task.output_len = output.end;
            task.ready.store(true, .release);
        }
    }
}

fn parallelOutputDrainFallback(context: *ParallelOutputContext) void {
    var batch: [parallel_list_dequeue_batch]*ParallelOutputTask = undefined;
    while (true) {
        const count = context.queue.getUncancelable(context.init.io, &batch, 1) catch break;
        for (batch[0..count]) |task| {
            task.fallback = true;
            task.ready.store(true, .release);
        }
    }
}

fn scanFileOutputThreadMatchers(
    init: std.process.Init,
    path: [:0]const u8,
    matchers: []const zgrep.matcher.ThreadMatcher,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    const file = try openTraversalFile(path);
    defer file.close(init.io);
    const stat = try file.stat(init.io);
    if (stat.kind != .file or stat.size == 0) return .{};
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;
    var file_options = options;
    if (options.initial_tab_width != 0)
        file_options.initial_tab_width = decimalDigitCount(stat.size);

    const small_file_bytes = 64 * 1024;
    if (stat.size <= small_file_bytes) {
        var small_buffer: [small_file_bytes]u8 = undefined;
        const bytes_read = try file.readPositionalAll(
            init.io,
            small_buffer[0..@intCast(stat.size)],
            0,
        );
        return scanOutputBufferThreadMatchers(
            small_buffer[0..bytes_read],
            matchers,
            path,
            file_options,
            writer,
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
    return scanOutputBufferThreadMatchers(
        mapped,
        matchers,
        path,
        file_options,
        writer,
    );
}

fn scanOutputBufferThreadMatchers(
    buffer: []const u8,
    matchers: []const zgrep.matcher.ThreadMatcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    if (options.delimiter != 0 and std.mem.findScalar(u8, buffer, 0) != null) {
        switch (options.binary_mode) {
            .binary => return error.BinaryInput,
            .without_match => return error.BinaryInput,
            .text => {},
        }
    }
    return zgrep.scanner.scanBufferOutputThreadMatchers(
        buffer,
        matchers,
        path,
        options,
        writer,
    );
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
    var path_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer path_arena.deinit();
    var items: std.ArrayList(*ParallelListItem) = .empty;
    defer items.deinit(init.gpa);
    var pipeline: ParallelListPipeline = undefined;
    pipeline.init(init, matchers, options);
    var collector: ParallelListCollector = .{
        .init = init,
        .items = &items,
        .pipeline = &pipeline,
    };
    errdefer pipeline.abort();
    var aggregate: PathResult = .{};
    try collectDirectoryFiles(
        init,
        path_arena.allocator(),
        null,
        path,
        filters,
        strip_dot_prefix,
        ancestors,
        no_messages,
        diagnostic_writer,
        &collector,
        &aggregate,
    );
    if (items.items.len == 0) return aggregate;

    if (pipeline.started) {
        try pipeline.finish();
        if (pipeline.context.setup_failed.load(.acquire)) return error.OutOfMemory;
    } else {
        var context: ParallelListContext = .{
            .init = init,
            .matchers = matchers,
            .items = items.items,
            .options = options,
            .probe_small_files_without_stat = items.items.len >= 32,
        };

        const cpu_count = std.Thread.getCpuCount() catch 1;
        var useful_threads = (items.items.len + 31) / 32;
        var benefits_from_large_file_parallelism = false;
        for (matchers) |*matcher| {
            if (matcher.benefitsFromLargeFileListParallelism()) {
                benefits_from_large_file_parallelism = true;
                break;
            }
        }
        if (benefits_from_large_file_parallelism and items.items.len > 1 and items.items.len < 32) {
            const bytes_per_thread = 2 * 1024 * 1024;
            var total_bytes: u64 = 0;
            for (items.items) |item| {
                const stat = std.Io.Dir.cwd().statFile(init.io, item.path, .{}) catch continue;
                total_bytes +|= stat.size;
            }
            const useful_by_bytes: usize = @intCast(@min(
                items.items.len,
                @max(1, (total_bytes + bytes_per_thread - 1) / bytes_per_thread),
            ));
            useful_threads = @max(useful_threads, useful_by_bytes);
        }
        const thread_count = @max(1, @min(
            parallelListThreadLimit(matchers),
            @min(cpu_count, useful_threads),
        ));
        var threads: [parallel_list_max_threads - 1]std.Thread = undefined;
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
    }

    const want_match = options.list_files.?;
    for (items.items) |item| {
        if (item.result.err) |err| {
            if (!no_messages)
                try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, item.path, @errorName(err) });
            aggregate.had_error = true;
            continue;
        }
        aggregate.matched = aggregate.matched or item.result.matched;
        if (item.result.matched == want_match)
            try zgrep.scanner.emitFilename(
                writer,
                item.path,
                options.null_filename,
                options.colors,
                options.line_buffered,
            );
    }
    return aggregate;
}

fn collectDirectoryFiles(
    init: std.process.Init,
    path_allocator: std.mem.Allocator,
    opened_directory: ?std.Io.Dir,
    path: []const u8,
    filters: zgrep.filter.Filters,
    strip_dot_prefix: bool,
    ancestors: ?*std.StringHashMap(void),
    no_messages: bool,
    diagnostic_writer: *std.Io.Writer,
    collector: *ParallelListCollector,
    aggregate: *PathResult,
) !void {
    var canonical: ?[:0]u8 = null;
    if (ancestors) |set| {
        const resolved = try std.Io.Dir.cwd().realPathFileAlloc(init.io, path, init.gpa);
        if (set.contains(resolved)) {
            if (!no_messages) try diagnostic_writer.print(
                "{s}: {s}: warning: recursive directory loop\n",
                .{ diagnostic_name, path },
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

    const directory = opened_directory orelse
        try std.Io.Dir.cwd().openDir(init.io, path, .{ .iterate = true });
    defer directory.close(init.io);
    var iterator = directory.iterateAssumeFirstIteration();
    while (try iterator.next(init.io)) |entry| {
        const full_path = try joinTraversalPath(path_allocator, path, entry.name, strip_dot_prefix);

        var kind = entry.kind;
        if (kind == .unknown) {
            const stat = directory.statFile(init.io, entry.name, .{ .follow_symlinks = false }) catch |err| {
                if (!no_messages)
                    try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }
        if (kind == .sym_link) {
            if (ancestors == null) continue;
            const stat = directory.statFile(init.io, entry.name, .{}) catch |err| {
                if (!no_messages)
                    try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, full_path, @errorName(err) });
                aggregate.had_error = true;
                continue;
            };
            kind = stat.kind;
        }

        switch (kind) {
            .file => {
                if (!filters.allowsFile(full_path)) continue;
                const item = try path_allocator.create(ParallelListItem);
                item.* = .{ .path = full_path };
                try collector.append(item);
            },
            .directory => if (filters.allowsDir(full_path)) {
                const child_directory = if (ancestors == null)
                    directory.openDir(init.io, entry.name, .{ .iterate = true }) catch |err| {
                        if (!no_messages)
                            try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, full_path, @errorName(err) });
                        aggregate.had_error = true;
                        continue;
                    }
                else
                    null;
                collectDirectoryFiles(
                    init,
                    path_allocator,
                    child_directory,
                    full_path,
                    filters,
                    strip_dot_prefix,
                    ancestors,
                    no_messages,
                    diagnostic_writer,
                    collector,
                    aggregate,
                ) catch |err| {
                    if (!no_messages)
                        try diagnostic_writer.print("{s}: {s}: {s}\n", .{ diagnostic_name, full_path, @errorName(err) });
                    aggregate.had_error = true;
                };
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
) ![:0]u8 {
    if (strip_dot_prefix and std.mem.eql(u8, path, ".")) return allocator.dupeZ(u8, name);
    return std.fs.path.joinZ(allocator, &.{ path, name });
}

const ParallelListResult = struct {
    matched: bool = false,
    err: ?anyerror = null,
};

const ParallelListItem = struct {
    path: [:0]const u8,
    result: ParallelListResult = .{},
    output: ?[]u8 = null,
    output_len: usize = 0,
    output_binary_match: bool = false,
};

const parallel_list_max_threads = 16;
// Fast matchers become queue- and I/O-bound before compute-heavy regexes do.
const parallel_list_fast_matcher_threads = 12;

fn parallelListThreadLimit(matchers: []const zgrep.matcher.Matcher) usize {
    for (matchers) |*matcher|
        if (matcher.benefitsFromExtraRecursiveWorkers()) return parallel_list_max_threads;
    return parallel_list_fast_matcher_threads;
}
// Medium source trees are faster with the post-traversal scheduler. Once a
// tree reaches this size, a bounded queue can hide serial directory walking
// behind file scans without changing traversal-order output.
const parallel_list_pipeline_threshold = 512;
const parallel_list_queue_capacity = 256;
const parallel_list_enqueue_batch = 128;
const parallel_list_dequeue_batch = 32;
const ParallelListQueue = std.Io.Queue(*ParallelListItem);

const ParallelListPipelineContext = struct {
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    queue: *ParallelListQueue,
    capture_output: bool = false,
    captured_bytes: std.atomic.Value(usize) = .init(0),
    setup_failed: std.atomic.Value(bool) = .init(false),
};

const ParallelListPipeline = struct {
    init_state: std.process.Init = undefined,
    context: ParallelListPipelineContext = undefined,
    queue: ParallelListQueue = undefined,
    queue_buffer: [parallel_list_queue_capacity]*ParallelListItem = undefined,
    pending: [parallel_list_enqueue_batch]*ParallelListItem = undefined,
    pending_len: usize = 0,
    threads: [parallel_list_max_threads]std.Thread = undefined,
    spawned: usize = 0,
    started: bool = false,
    closed: bool = false,

    fn init(
        self: *ParallelListPipeline,
        init_state: std.process.Init,
        matchers: []const zgrep.matcher.Matcher,
        options: zgrep.scanner.ScanOptions,
    ) void {
        self.* = .{ .init_state = init_state };
        self.queue = .init(&self.queue_buffer);
        self.context = .{
            .init = init_state,
            .matchers = matchers,
            .options = options,
            .queue = &self.queue,
        };
    }

    fn start(self: *ParallelListPipeline, items: []const *ParallelListItem) !void {
        std.debug.assert(!self.started);
        self.started = true;
        const cpu_count = std.Thread.getCpuCount() catch 1;
        const thread_count = @max(1, @min(
            parallelListThreadLimit(self.context.matchers),
            cpu_count,
        ));
        for (0..thread_count) |index| {
            self.threads[index] = try std.Thread.spawn(
                .{ .stack_size = 1024 * 1024 },
                parallelListPipelineWorker,
                .{&self.context},
            );
            self.spawned += 1;
        }
        try self.enqueueAll(items);
    }

    fn enqueue(self: *ParallelListPipeline, item: *ParallelListItem) !void {
        self.pending[self.pending_len] = item;
        self.pending_len += 1;
        if (self.pending_len == self.pending.len) try self.flush();
    }

    fn enqueueAll(self: *ParallelListPipeline, items: []const *ParallelListItem) !void {
        if (items.len == 0) return;
        const queued = try self.queue.putUncancelable(self.init_state.io, items, items.len);
        std.debug.assert(queued == items.len);
    }

    fn flush(self: *ParallelListPipeline) !void {
        try self.enqueueAll(self.pending[0..self.pending_len]);
        self.pending_len = 0;
    }

    fn finish(self: *ParallelListPipeline) !void {
        std.debug.assert(self.started and !self.closed);
        try self.flush();
        self.closeAndJoin();
    }

    fn abort(self: *ParallelListPipeline) void {
        if (!self.started or self.closed) return;
        self.pending_len = 0;
        self.closeAndJoin();
    }

    fn closeAndJoin(self: *ParallelListPipeline) void {
        self.queue.close(self.init_state.io);
        self.closed = true;
        for (self.threads[0..self.spawned]) |thread| thread.join();
        self.spawned = 0;
    }
};

const ParallelListCollector = struct {
    init: std.process.Init,
    items: *std.ArrayList(*ParallelListItem),
    pipeline: ?*ParallelListPipeline,

    fn append(self: *ParallelListCollector, item: *ParallelListItem) !void {
        try self.items.append(self.init.gpa, item);
        const pipeline = self.pipeline orelse return;
        if (pipeline.started) return pipeline.enqueue(item);
        if (self.items.items.len == parallel_list_pipeline_threshold and
            (std.Thread.getCpuCount() catch 1) > 1)
        {
            try pipeline.start(self.items.items);
        }
    }
};

const ParallelListContext = struct {
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    items: []const *ParallelListItem,
    options: zgrep.scanner.ScanOptions,
    probe_small_files_without_stat: bool,
    next: std.atomic.Value(usize) = .init(0),
    setup_failed: std.atomic.Value(bool) = .init(false),
};

fn parallelListPipelineWorker(context: *ParallelListPipelineContext) void {
    const thread_matchers = std.heap.c_allocator.alloc(
        zgrep.matcher.ThreadMatcher,
        context.matchers.len,
    ) catch {
        context.setup_failed.store(true, .release);
        parallelListPipelineDrainFailed(context);
        return;
    };
    defer std.heap.c_allocator.free(thread_matchers);
    var initialized: usize = 0;
    defer for (thread_matchers[0..initialized]) |*matcher| matcher.deinit();
    for (context.matchers, 0..) |*matcher, index| {
        thread_matchers[index] = zgrep.matcher.ThreadMatcher.init(matcher) catch {
            context.setup_failed.store(true, .release);
            parallelListPipelineDrainFailed(context);
            return;
        };
        initialized += 1;
    }

    var scan_options = context.options;
    scan_options.list_files = null;
    scan_options.quiet = true;
    scan_options.count = false;
    scan_options.context_state = null;
    var batch: [parallel_list_dequeue_batch]*ParallelListItem = undefined;
    while (true) {
        const count = context.queue.getUncancelable(context.init.io, &batch, 1) catch break;
        for (batch[0..count]) |item| {
            const result = scanFileThreadMatchers(
                context.init,
                item.path,
                thread_matchers,
                scan_options,
                true,
            ) catch |err| {
                item.result.err = err;
                continue;
            };
            item.result.matched = result.matched;
            if (context.capture_output and result.matched)
                captureParallelOutput(context, item, thread_matchers);
        }
    }
}

fn captureParallelOutput(
    context: *ParallelListPipelineContext,
    item: *ParallelListItem,
    matchers: []const zgrep.matcher.ThreadMatcher,
) void {
    var temporary: [parallel_output_slot_bytes]u8 = undefined;
    var output = std.Io.Writer.fixed(&temporary);
    const result = scanFileOutputThreadMatchers(
        context.init,
        item.path,
        matchers,
        context.options,
        &output,
    ) catch return;
    if (!result.matched) return;

    const reserved = context.captured_bytes.fetchAdd(output.end, .acq_rel);
    if (reserved > parallel_output_capture_bytes - output.end) {
        _ = context.captured_bytes.fetchSub(output.end, .acq_rel);
        return;
    }
    const buffer = std.heap.c_allocator.alloc(u8, output.end) catch {
        _ = context.captured_bytes.fetchSub(output.end, .acq_rel);
        return;
    };
    @memcpy(buffer, temporary[0..output.end]);
    item.output = buffer;
    item.output_len = output.end;
    item.output_binary_match = result.binary_match;
}

fn parallelListPipelineDrainFailed(context: *ParallelListPipelineContext) void {
    var batch: [parallel_list_dequeue_batch]*ParallelListItem = undefined;
    while (true) {
        const count = context.queue.getUncancelable(context.init.io, &batch, 1) catch break;
        for (batch[0..count]) |item| item.result.err = error.OutOfMemory;
    }
}

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
        if (index >= context.items.len) break;
        const item = context.items[index];
        const result = scanFileThreadMatchers(
            context.init,
            item.path,
            thread_matchers,
            scan_options,
            context.probe_small_files_without_stat,
        ) catch |err| {
            item.result.err = err;
            continue;
        };
        item.result.matched = result.matched;
    }
}

fn scanFileThreadMatchers(
    init: std.process.Init,
    path: [:0]const u8,
    matchers: []const zgrep.matcher.ThreadMatcher,
    options: zgrep.scanner.ScanOptions,
    probe_small_files_without_stat: bool,
) !zgrep.scanner.Result {
    const file = try openTraversalFile(path);
    defer file.close(init.io);
    const small_file_bytes = 64 * 1024;
    if (probe_small_files_without_stat) {
        var small_buffer: [small_file_bytes]u8 = undefined;
        const bytes_read = file.readPositionalAll(init.io, &small_buffer, 0) catch
            small_file_bytes;
        if (bytes_read < small_file_bytes) {
            if (bytes_read == 0) return .{};
            return zgrep.scanner.scanBufferQuietThreadMatchers(
                small_buffer[0..bytes_read],
                matchers,
                options,
            );
        }
    }

    const stat = try file.stat(init.io);
    if (stat.kind != .file or stat.size == 0) return .{};
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;
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

fn openTraversalFile(path: [:0]const u8) !std.Io.File {
    var flags: std.posix.O = .{ .ACCMODE = .RDONLY };
    if (@hasField(std.posix.O, "CLOEXEC")) flags.CLOEXEC = true;
    if (@hasField(std.posix.O, "LARGEFILE")) flags.LARGEFILE = true;
    if (@hasField(std.posix.O, "NOCTTY")) flags.NOCTTY = true;
    const handle = try std.posix.openatZ(std.posix.AT.FDCWD, path.ptr, flags, 0);
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}

fn scanFile(
    init: std.process.Init,
    path: []const u8,
    matchers: []const zgrep.matcher.Matcher,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    if (options.skip_contents) return emitSkipContentsName(path, options, writer);
    const file = try std.Io.Dir.cwd().openFile(init.io, path, .{});
    defer file.close(init.io);
    if (try rejectIfSameFile(file, options, path, diagnostic_writer)) |rejected|
        return rejected;
    const stat = try file.stat(init.io);
    var file_options = options;
    if (stat.kind == .file and options.initial_tab_width != 0)
        file_options.initial_tab_width = decimalDigitCount(stat.size);
    if (stat.kind == .file and stat.size > 0) {
        if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;
        const small_file_bytes = 64 * 1024;
        if (stat.size > small_file_bytes and shouldStreamAndStop(file_options) and
            file_options.binary_mode != .without_match)
        {
            return scanFileStreaming(init, file, path, matchers, file_options, writer, diagnostic_writer);
        }
        if (stat.size <= small_file_bytes) {
            var small_buffer: [small_file_bytes]u8 = undefined;
            const bytes_read = try file.readPositionalAll(
                init.io,
                small_buffer[0..@intCast(stat.size)],
                0,
            );
            return annotateMatchError(
                matchers,
                path,
                diagnostic_writer,
                try scanRegularBuffer(
                    small_buffer[0..bytes_read],
                    matchers,
                    path,
                    file_options,
                    writer,
                    diagnostic_writer,
                ),
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
        return annotateMatchError(
            matchers,
            path,
            diagnostic_writer,
            try scanRegularBuffer(mapped, matchers, path, file_options, writer, diagnostic_writer),
        );
    }
    if (stat.kind == .file) {
        return annotateMatchError(
            matchers,
            path,
            diagnostic_writer,
            try zgrep.scanner.scanBuffer(&.{}, matchers, path, file_options, writer),
        );
    }

    if (requiresBufferedScan(options)) {
        var read_buffer: [256 * 1024]u8 = undefined;
        var reader = file.readerStreaming(init.io, &read_buffer);
        const data = try reader.interface.allocRemaining(init.gpa, .unlimited);
        defer init.gpa.free(data);
        return annotateMatchError(
            matchers,
            path,
            diagnostic_writer,
            try scanBufferedData(data, matchers, path, options, writer, diagnostic_writer),
        );
    }

    if (try zgrep.scanner.scanFileLiteralCount(file, init.io, init.gpa, matchers, path, options, writer)) |result| {
        return annotateMatchError(matchers, path, diagnostic_writer, result);
    }
    if (try zgrep.scanner.scanFileLiteralOutput(file, init.io, init.gpa, matchers, path, options, writer)) |result| {
        if (result.binary_match) try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
        return annotateMatchError(matchers, path, diagnostic_writer, result);
    }
    return scanFileStreaming(init, file, path, matchers, options, writer, diagnostic_writer);
}

fn decimalDigitCount(value: u64) usize {
    var remaining = value;
    var digits: usize = 1;
    while (remaining >= 10) : (digits += 1) remaining /= 10;
    return digits;
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
        if (try zgrep.scanner.findNulParallel(buffer)) |nul_position|
            return scanWithoutMatchBinaryBuffer(
                buffer,
                nul_position,
                matchers,
                path,
                options,
                writer,
            );
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
    var scan_options = options;
    if (matchers.len == 1) switch (matchers[0]) {
        .regex => |*regex| {
            if (regex.ascii_class_sequence != null and options.count and !options.quiet and
                options.list_files == null and options.max_count == null)
                scan_options.ascii_input = try zgrep.scanner.isAsciiParallel(buffer);
        },
        .posix_regex => |*regex| {
            const needs_full_ascii = regex.ascii_literal != null or regex.ascii_alternation != null or
                regex.ascii_class_sequence != null or
                (regex.ascii_pcre and (options.count or regex.prefilter == null));
            if (needs_full_ascii)
                scan_options.ascii_input = try zgrep.scanner.isAsciiParallel(buffer);
        },
        else => {},
    };
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
                    options.colors,
                    count,
                    options.line_buffered,
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
                    options.colors,
                    count,
                    options.line_buffered,
                );
                return .{ .matched = count != 0, .selected_lines = count };
            },
            .regex => |*regex| {
                const count = try zgrep.scanner.parallelRegexCount(
                    buffer,
                    regex,
                    options.invert,
                    options.delimiter,
                    scan_options.ascii_input orelse false,
                );
                try zgrep.scanner.emitCount(
                    writer,
                    path,
                    options.show_filename,
                    options.null_filename,
                    options.colors,
                    count,
                    options.line_buffered,
                );
                return .{ .matched = count != 0, .selected_lines = count };
            },
            .posix_regex => |*regex| {
                const count: ?usize = if (scan_options.ascii_input orelse false) count: {
                    if (regex.ascii_literal) |*literal| {
                        if (!literal.whole_line)
                            break :count try zgrep.scanner.parallelLiteralCount(
                                buffer,
                                literal,
                                options.invert,
                                options.delimiter,
                            );
                    } else if (regex.ascii_alternation) |*alternation| {
                        break :count try zgrep.scanner.parallelAlternationCount(
                            buffer,
                            alternation,
                            options.invert,
                            options.delimiter,
                        );
                    } else if (regex.ascii_class_sequence != null or regex.ascii_pcre) {
                        break :count try zgrep.scanner.parallelRegexCount(
                            buffer,
                            regex,
                            options.invert,
                            options.delimiter,
                            true,
                        );
                    }
                    break :count null;
                } else null;
                if (count) |selected| {
                    try zgrep.scanner.emitCount(
                        writer,
                        path,
                        options.show_filename,
                        options.null_filename,
                        options.colors,
                        selected,
                        options.line_buffered,
                    );
                    return .{ .matched = selected != 0, .selected_lines = selected };
                }
            },
        }
    }
    if (try zgrep.scanner.parallelSelectedOutput(buffer, matchers, path, scan_options, writer)) |result| {
        if (result.binary_match)
            try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
        return result;
    }
    const result = try zgrep.scanner.scanBuffer(buffer, matchers, path, scan_options, writer);
    if (result.binary_match)
        try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
    return result;
}

fn scanStdin(
    init: std.process.Init,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
    diagnostic_writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    if (options.skip_contents) return emitSkipContentsName(path, options, writer);
    const stdin_file = std.Io.File.stdin();
    if (try rejectIfSameFile(stdin_file, options, path, diagnostic_writer)) |rejected|
        return rejected;
    var input_options = options;
    if (options.initial_tab_width != 0) {
        if (stdin_file.stat(init.io)) |stat| {
            if (stat.kind == .file)
                input_options.initial_tab_width = decimalDigitCount(stat.size);
        } else |_| {}
    }
    if (requiresBufferedScan(input_options)) {
        var read_buffer: [256 * 1024]u8 = undefined;
        var reader = stdin_file.readerStreaming(init.io, &read_buffer);
        const data = try reader.interface.allocRemaining(init.gpa, .unlimited);
        defer init.gpa.free(data);
        return annotateMatchError(
            matchers,
            path,
            diagnostic_writer,
            try scanBufferedData(
                data,
                matchers,
                path,
                input_options,
                writer,
                diagnostic_writer,
            ),
        );
    }
    if (try zgrep.scanner.scanFileLiteralCount(
        stdin_file,
        init.io,
        init.gpa,
        matchers,
        path,
        input_options,
        writer,
    )) |result| return annotateMatchError(matchers, path, diagnostic_writer, result);
    if (try zgrep.scanner.scanFileLiteralOutput(
        stdin_file,
        init.io,
        init.gpa,
        matchers,
        path,
        input_options,
        writer,
    )) |result| {
        if (result.binary_match)
            try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
        return annotateMatchError(matchers, path, diagnostic_writer, result);
    }

    return scanFileStreaming(
        init,
        stdin_file,
        path,
        matchers,
        input_options,
        writer,
        diagnostic_writer,
    );
}

fn requiresBufferedScan(options: zgrep.scanner.ScanOptions) bool {
    return options.delimiter != 0 and options.binary_mode == .without_match;
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
    if (options.delimiter == 0 or options.binary_mode == .text) {
        const result = try zgrep.scanner.scanBuffer(data, matchers, path, options, writer);
        if (result.binary_match)
            try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
        return result;
    }
    const nul_position = try zgrep.scanner.findNulParallel(data) orelse
        {
            const result = try zgrep.scanner.scanBuffer(data, matchers, path, options, writer);
            if (result.binary_match)
                try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
            return result;
        };
    if (options.binary_mode == .without_match)
        return scanWithoutMatchBinaryBuffer(
            data,
            nul_position,
            matchers,
            path,
            options,
            writer,
        );
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

fn scanWithoutMatchBinaryBuffer(
    buffer: []const u8,
    nul_position: usize,
    matchers: []const zgrep.matcher.Matcher,
    path: []const u8,
    options: zgrep.scanner.ScanOptions,
    writer: *std.Io.Writer,
) !zgrep.scanner.Result {
    const text_end = zgrep.scanner.binaryTextPrefixEnd(
        buffer,
        nul_position,
        options.delimiter,
    );
    if (text_end == 0 or options.count)
        return zgrep.scanner.scanBuffer(&.{}, matchers, path, options, writer);
    var result = try zgrep.scanner.scanBuffer(
        buffer[0..text_end],
        matchers,
        path,
        options,
        writer,
    );
    if (options.quiet or options.list_files != null) return result;
    if (options.max_count) |limit|
        if (result.selected_lines >= limit) return result;
    result.matched = false;
    result.selected_lines = 0;
    return result;
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
    const binary_start = zgrep.scanner.binaryTextPrefixEnd(
        buffer,
        nul_position,
        options.delimiter,
    );

    var aggregate: zgrep.scanner.Result = .{};
    if (binary_start != 0) {
        aggregate = try zgrep.scanner.scanBuffer(
            buffer[0..binary_start],
            matchers,
            path,
            options,
            writer,
        );
        if (aggregate.matched) {
            if (aggregate.binary_match)
                try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
            if (options.max_count) |limit|
                if (aggregate.selected_lines >= limit) return aggregate;
        }
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
    if (result.matched) try diagnostic_writer.print("{s}: {s}: binary file matches\n", .{ diagnostic_name, path });
    aggregate.matched = aggregate.matched or result.matched;
    aggregate.selected_lines += result.selected_lines;
    return aggregate;
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

const help_text = "zgr " ++ version ++ " (Zig 0.16)\n\n" ++
    \\Usage: zgr [OPTION]... PATTERN [FILE]...
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
    \\  -U, --binary             do not strip CR characters (no-op on GNU/Linux)
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
    \\      --line-buffered      flush output after every complete line
    \\  -T, --initial-tab        align line content on a tab stop
    \\  -A, --after-context=NUM  print NUM lines of trailing context
    \\  -B, --before-context=NUM print NUM lines of leading context
    \\  -C, --context=NUM        print NUM lines of output context
    \\      --group-separator=SEP use SEP between context groups
    \\      --no-group-separator suppress context group separators
    \\  -H, --with-filename      print file names
    \\  -h, --no-filename        suppress file names
    \\  -Z, --null               end printed file names with NUL
    \\      --label=LABEL        use LABEL for standard input
    \\  -q, --quiet, --silent    stop after the first match
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
    \\      --color[=WHEN]       highlight matches; WHEN is always, never, or auto
    \\      --colour[=WHEN]      same as --color
    \\      --help               display this help
    \\      --version            display version information
    \\  -V                       same as --version
;
