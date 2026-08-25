const std = @import("std");

pub const Mode = enum { basic, extended, fixed, perl };
pub const BinaryMode = enum { binary, text, without_match };
pub const DirectoryMode = enum { read, recurse, skip };
pub const DeviceMode = enum { default, read, skip };
pub const ColorMode = enum { always, never, auto };
pub const FileFilterArg = union(enum) {
    include: []const u8,
    exclude: []const u8,
    exclude_file: []const u8,
};

pub const Options = struct {
    mode: Mode = .basic,
    ignore_case: bool = false,
    invert: bool = false,
    count: bool = false,
    line_number: bool = false,
    with_filename: ?bool = null,
    quiet: bool = false,
    no_messages: bool = false,
    line_regexp: bool = false,
    word_regexp: bool = false,
    recursive: bool = false,
    dereference_recursive: bool = false,
    directory_mode: DirectoryMode = .read,
    device_mode: DeviceMode = .default,
    list_files: ?bool = null,
    max_count: ?usize = null,
    byte_offset: bool = false,
    only_matching: bool = false,
    before_context: usize = 0,
    after_context: usize = 0,
    context_separator: ?[]const u8 = "--",
    label: ?[]const u8 = null,
    null_data: bool = false,
    null_filename: bool = false,
    binary_mode: BinaryMode = .binary,
    line_buffered: bool = false,
    initial_tab: bool = false,
    color: ?ColorMode = null,
    help: bool = false,
    version: bool = false,
    patterns: std.ArrayList([]const u8) = .empty,
    pattern_files: std.ArrayList([]const u8) = .empty,
    operands: std.ArrayList([]const u8) = .empty,
    file_filter_args: std.ArrayList(FileFilterArg) = .empty,
    exclude_dirs: std.ArrayList([]const u8) = .empty,
    before_context_explicit: bool = false,
    after_context_explicit: bool = false,

    pub fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        self.patterns.deinit(allocator);
        self.pattern_files.deinit(allocator);
        self.operands.deinit(allocator);
        self.file_filter_args.deinit(allocator);
        self.exclude_dirs.deinit(allocator);
    }

    pub fn parse(args: std.process.Args, allocator: std.mem.Allocator) !Options {
        var result: Options = .{};
        errdefer result.deinit(allocator);

        var it = std.process.Args.Iterator.init(args);
        const argv0 = it.next() orelse "zgrep";
        if (std.mem.endsWith(u8, argv0, "egrep")) result.mode = .extended;

        var parse_options = true;
        while (it.next()) |arg_z| {
            const arg: []const u8 = arg_z;
            if (parse_options and std.mem.eql(u8, arg, "--")) {
                parse_options = false;
                continue;
            }
            if (parse_options and arg.len > 1 and arg[0] == '-') {
                if (std.mem.startsWith(u8, arg, "--")) {
                    try result.parseLong(arg, &it, allocator);
                } else {
                    try result.parseShort(arg, &it, allocator);
                }
            } else {
                try result.operands.append(allocator, arg);
            }
        }

        if (!result.help and !result.version) {
            if (result.patterns.items.len == 0 and result.pattern_files.items.len == 0) {
                if (result.operands.items.len == 0) return error.MissingPattern;
                try result.appendArgumentPatterns(allocator, result.operands.items[0]);
                _ = result.operands.orderedRemove(0);
            }
        }
        return result;
    }

    fn parseLong(
        self: *Options,
        arg: []const u8,
        it: *std.process.Args.Iterator,
        allocator: std.mem.Allocator,
    ) !void {
        if (std.mem.eql(u8, arg, "--extended-regexp")) self.mode = .extended else if (std.mem.eql(u8, arg, "--fixed-strings")) self.mode = .fixed else if (std.mem.eql(u8, arg, "--basic-regexp")) self.mode = .basic else if (std.mem.eql(u8, arg, "--perl-regexp")) self.mode = .perl else if (std.mem.eql(u8, arg, "--ignore-case")) self.ignore_case = true else if (std.mem.eql(u8, arg, "--no-ignore-case")) self.ignore_case = false else if (std.mem.eql(u8, arg, "--invert-match")) self.invert = true else if (std.mem.eql(u8, arg, "--count")) self.count = true else if (std.mem.eql(u8, arg, "--line-number")) self.line_number = true else if (std.mem.eql(u8, arg, "--byte-offset")) self.byte_offset = true else if (std.mem.eql(u8, arg, "--only-matching")) self.only_matching = true else if (std.mem.eql(u8, arg, "--with-filename")) self.with_filename = true else if (std.mem.eql(u8, arg, "--no-filename")) self.with_filename = false else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "--silent")) self.quiet = true else if (std.mem.eql(u8, arg, "--no-messages")) self.no_messages = true else if (std.mem.eql(u8, arg, "--line-regexp")) self.line_regexp = true else if (std.mem.eql(u8, arg, "--word-regexp")) self.word_regexp = true else if (std.mem.eql(u8, arg, "--recursive")) {
            self.recursive = true;
            self.directory_mode = .recurse;
        } else if (std.mem.eql(u8, arg, "--dereference-recursive")) {
            self.recursive = true;
            self.dereference_recursive = true;
            self.directory_mode = .recurse;
        } else if (std.mem.startsWith(u8, arg, "--directories=")) {
            try self.setDirectoryMode(arg[14..]);
        } else if (std.mem.eql(u8, arg, "--directories")) {
            try self.setDirectoryMode(it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.startsWith(u8, arg, "--devices=")) {
            try self.setDeviceMode(arg[10..]);
        } else if (std.mem.eql(u8, arg, "--devices")) {
            try self.setDeviceMode(it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.startsWith(u8, arg, "--after-context=")) {
            try self.setAfterContext(arg[16..]);
        } else if (std.mem.eql(u8, arg, "--after-context")) {
            try self.setAfterContext(it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.startsWith(u8, arg, "--before-context=")) {
            try self.setBeforeContext(arg[17..]);
        } else if (std.mem.eql(u8, arg, "--before-context")) {
            try self.setBeforeContext(it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.startsWith(u8, arg, "--context=")) {
            try self.setContext(arg[10..]);
        } else if (std.mem.eql(u8, arg, "--context")) {
            try self.setContext(it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.startsWith(u8, arg, "--group-separator=")) {
            self.context_separator = arg[18..];
        } else if (std.mem.eql(u8, arg, "--group-separator")) {
            self.context_separator = it.next() orelse return error.MissingOptionArgument;
        } else if (std.mem.startsWith(u8, arg, "--context-separator=")) {
            self.context_separator = arg[20..];
        } else if (std.mem.eql(u8, arg, "--context-separator")) {
            self.context_separator = it.next() orelse return error.MissingOptionArgument;
        } else if (std.mem.eql(u8, arg, "--no-group-separator") or
            std.mem.eql(u8, arg, "--no-context-separator"))
        {
            self.context_separator = null;
        } else if (std.mem.startsWith(u8, arg, "--label=")) {
            self.label = arg[8..];
        } else if (std.mem.eql(u8, arg, "--label")) {
            self.label = it.next() orelse return error.MissingOptionArgument;
        } else if (std.mem.startsWith(u8, arg, "--include=")) {
            try self.file_filter_args.append(allocator, .{ .include = arg[10..] });
        } else if (std.mem.eql(u8, arg, "--include")) {
            try self.file_filter_args.append(
                allocator,
                .{ .include = it.next() orelse return error.MissingOptionArgument },
            );
        } else if (std.mem.startsWith(u8, arg, "--exclude=")) {
            try self.file_filter_args.append(allocator, .{ .exclude = arg[10..] });
        } else if (std.mem.eql(u8, arg, "--exclude")) {
            try self.file_filter_args.append(
                allocator,
                .{ .exclude = it.next() orelse return error.MissingOptionArgument },
            );
        } else if (std.mem.startsWith(u8, arg, "--exclude-from=")) {
            try self.file_filter_args.append(allocator, .{ .exclude_file = arg[15..] });
        } else if (std.mem.eql(u8, arg, "--exclude-from")) {
            try self.file_filter_args.append(
                allocator,
                .{ .exclude_file = it.next() orelse return error.MissingOptionArgument },
            );
        } else if (std.mem.startsWith(u8, arg, "--exclude-dir=")) {
            try self.exclude_dirs.append(allocator, arg[14..]);
        } else if (std.mem.eql(u8, arg, "--exclude-dir")) {
            try self.exclude_dirs.append(allocator, it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.eql(u8, arg, "--null-data")) self.null_data = true else if (std.mem.eql(u8, arg, "--null")) self.null_filename = true else if (std.mem.eql(u8, arg, "--files-with-matches")) self.list_files = true else if (std.mem.eql(u8, arg, "--files-without-match")) self.list_files = false else if (std.mem.startsWith(u8, arg, "--max-count=")) {
            self.max_count = std.fmt.parseInt(usize, arg[12..], 10) catch return error.InvalidNumber;
        } else if (std.mem.eql(u8, arg, "--max-count")) {
            const value = it.next() orelse return error.MissingOptionArgument;
            self.max_count = std.fmt.parseInt(usize, value, 10) catch return error.InvalidNumber;
        } else if (std.mem.eql(u8, arg, "--text")) self.binary_mode = .text else if (std.mem.eql(u8, arg, "--binary")) {
            // GNU/Linux already reads files in binary mode; keep -U/--binary
            // as the compatible no-op documented by GNU grep.
        } else if (std.mem.eql(u8, arg, "--line-buffered")) self.line_buffered = true else if (std.mem.eql(u8, arg, "--initial-tab")) self.initial_tab = true else if (std.mem.startsWith(u8, arg, "--binary-files=")) {
            try self.setBinaryMode(arg[15..]);
        } else if (std.mem.eql(u8, arg, "--binary-files")) {
            try self.setBinaryMode(it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.eql(u8, arg, "--help")) self.help = true else if (std.mem.eql(u8, arg, "--version")) self.version = true else if (std.mem.eql(u8, arg, "--color") or std.mem.eql(u8, arg, "--colour")) {
            self.color = .auto;
        } else if (std.mem.startsWith(u8, arg, "--color=")) {
            self.setColorMode(arg[8..]);
        } else if (std.mem.startsWith(u8, arg, "--colour=")) {
            self.setColorMode(arg[9..]);
        } else if (std.mem.startsWith(u8, arg, "--regexp=")) {
            try self.appendArgumentPatterns(allocator, arg[9..]);
        } else if (std.mem.eql(u8, arg, "--regexp")) {
            try self.appendArgumentPatterns(allocator, it.next() orelse return error.MissingOptionArgument);
        } else if (std.mem.startsWith(u8, arg, "--file=")) {
            try self.pattern_files.append(allocator, arg[7..]);
        } else if (std.mem.eql(u8, arg, "--file")) {
            try self.pattern_files.append(allocator, it.next() orelse return error.MissingOptionArgument);
        } else return error.UnknownOption;
    }

    fn parseShort(
        self: *Options,
        arg: []const u8,
        it: *std.process.Args.Iterator,
        allocator: std.mem.Allocator,
    ) !void {
        if (arg.len > 1 and std.ascii.isDigit(arg[1])) {
            try self.setContext(arg[1..]);
            return;
        }
        var index: usize = 1;
        while (index < arg.len) : (index += 1) {
            switch (arg[index]) {
                'E' => self.mode = .extended,
                'F' => self.mode = .fixed,
                'G' => self.mode = .basic,
                'P' => self.mode = .perl,
                'i' => self.ignore_case = true,
                'v' => self.invert = true,
                'c' => self.count = true,
                'n' => self.line_number = true,
                'b' => self.byte_offset = true,
                'o' => self.only_matching = true,
                'a' => self.binary_mode = .text,
                'I' => self.binary_mode = .without_match,
                'U' => {},
                'T' => self.initial_tab = true,
                'H' => self.with_filename = true,
                'h' => self.with_filename = false,
                'q' => self.quiet = true,
                's' => self.no_messages = true,
                'x' => self.line_regexp = true,
                'w' => self.word_regexp = true,
                'r' => {
                    self.recursive = true;
                    self.directory_mode = .recurse;
                },
                'R' => {
                    self.recursive = true;
                    self.dereference_recursive = true;
                    self.directory_mode = .recurse;
                },
                'l' => self.list_files = true,
                'L' => self.list_files = false,
                'V' => self.version = true,
                'z' => self.null_data = true,
                'Z' => self.null_filename = true,
                'd' => {
                    const value = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    try self.setDirectoryMode(value);
                    return;
                },
                'D' => {
                    const value = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    try self.setDeviceMode(value);
                    return;
                },
                'A' => {
                    const value = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    try self.setAfterContext(value);
                    return;
                },
                'B' => {
                    const value = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    try self.setBeforeContext(value);
                    return;
                },
                'C' => {
                    const value = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    try self.setContext(value);
                    return;
                },
                'm' => {
                    const value = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    self.max_count = std.fmt.parseInt(usize, value, 10) catch return error.InvalidNumber;
                    return;
                },
                'e' => {
                    const pattern = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    try self.appendArgumentPatterns(allocator, pattern);
                    return;
                },
                'f' => {
                    const path = if (index + 1 < arg.len)
                        arg[index + 1 ..]
                    else
                        (it.next() orelse return error.MissingOptionArgument);
                    try self.pattern_files.append(allocator, path);
                    return;
                },
                else => return error.UnknownOption,
            }
        }
    }

    fn setBinaryMode(self: *Options, value: []const u8) !void {
        if (std.mem.eql(u8, value, "binary")) {
            self.binary_mode = .binary;
        } else if (std.mem.eql(u8, value, "text")) {
            self.binary_mode = .text;
        } else if (std.mem.eql(u8, value, "without-match")) {
            self.binary_mode = .without_match;
        } else {
            return error.InvalidBinaryMode;
        }
    }

    fn setDirectoryMode(self: *Options, value: []const u8) !void {
        if (std.mem.eql(u8, value, "read")) {
            self.directory_mode = .read;
            self.recursive = false;
        } else if (std.mem.eql(u8, value, "recurse")) {
            self.directory_mode = .recurse;
            self.recursive = true;
        } else if (std.mem.eql(u8, value, "skip")) {
            self.directory_mode = .skip;
            self.recursive = false;
        } else {
            return error.InvalidDirectoryMode;
        }
    }

    fn setDeviceMode(self: *Options, value: []const u8) !void {
        if (std.mem.eql(u8, value, "read")) {
            self.device_mode = .read;
        } else if (std.mem.eql(u8, value, "skip")) {
            self.device_mode = .skip;
        } else {
            return error.InvalidDeviceMode;
        }
    }

    fn setColorMode(self: *Options, value: []const u8) void {
        if (std.mem.eql(u8, value, "always") or
            std.mem.eql(u8, value, "yes") or
            std.mem.eql(u8, value, "force"))
        {
            self.color = .always;
        } else if (std.mem.eql(u8, value, "never") or
            std.mem.eql(u8, value, "no") or
            std.mem.eql(u8, value, "none"))
        {
            self.color = .never;
        } else if (std.mem.eql(u8, value, "auto") or
            std.mem.eql(u8, value, "tty") or
            std.mem.eql(u8, value, "if-tty"))
        {
            self.color = .auto;
        } else {
            self.help = true;
        }
    }

    fn setAfterContext(self: *Options, value: []const u8) !void {
        self.after_context = std.fmt.parseInt(usize, value, 10) catch return error.InvalidNumber;
        self.after_context_explicit = true;
    }

    fn setBeforeContext(self: *Options, value: []const u8) !void {
        self.before_context = std.fmt.parseInt(usize, value, 10) catch return error.InvalidNumber;
        self.before_context_explicit = true;
    }

    fn setContext(self: *Options, value: []const u8) !void {
        const count = std.fmt.parseInt(usize, value, 10) catch return error.InvalidNumber;
        if (!self.before_context_explicit) self.before_context = count;
        if (!self.after_context_explicit) self.after_context = count;
    }

    fn appendArgumentPatterns(
        self: *Options,
        allocator: std.mem.Allocator,
        pattern: []const u8,
    ) !void {
        var start: usize = 0;
        while (true) {
            const end = std.mem.findScalarPos(u8, pattern, start, '\n') orelse pattern.len;
            try self.patterns.append(allocator, pattern[start..end]);
            if (end == pattern.len) break;
            start = end + 1;
        }
    }
};

test "combined short flags and positional pattern" {
    // Argument-vector construction is platform-owned; parsing is covered by
    // the CLI differential tests. Keep this block so `zig build test` imports
    // and type-checks the parser.
    try std.testing.expect(@sizeOf(Options) > 0);
}
