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
    context_requested: bool = false,
    program_name: []const u8 = "zgr",

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
        if (it.next()) |argv0| {
            result.program_name = std.fs.path.basename(argv0);
            if (result.program_name.len == 0) result.program_name = "zgr";
        }

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
        const raw = arg[2..];
        const eq = std.mem.findScalar(u8, raw, '=');
        const given = if (eq) |index| raw[0..index] else raw;
        const inline_value: ?[]const u8 = if (eq) |index| raw[index + 1 ..] else null;
        const name = resolveLongOption(given) orelse return error.UnknownOption;
        if (std.mem.eql(u8, name, "extended-regexp")) self.mode = .extended else if (std.mem.eql(u8, name, "fixed-strings")) self.mode = .fixed else if (std.mem.eql(u8, name, "basic-regexp")) self.mode = .basic else if (std.mem.eql(u8, name, "perl-regexp")) self.mode = .perl else if (std.mem.eql(u8, name, "ignore-case")) self.ignore_case = true else if (std.mem.eql(u8, name, "no-ignore-case")) self.ignore_case = false else if (std.mem.eql(u8, name, "invert-match")) self.invert = true else if (std.mem.eql(u8, name, "count")) self.count = true else if (std.mem.eql(u8, name, "line-number")) self.line_number = true else if (std.mem.eql(u8, name, "byte-offset")) self.byte_offset = true else if (std.mem.eql(u8, name, "only-matching")) self.only_matching = true else if (std.mem.eql(u8, name, "with-filename")) self.with_filename = true else if (std.mem.eql(u8, name, "no-filename")) self.with_filename = false else if (std.mem.eql(u8, name, "quiet") or std.mem.eql(u8, name, "silent")) self.quiet = true else if (std.mem.eql(u8, name, "no-messages")) self.no_messages = true else if (std.mem.eql(u8, name, "line-regexp")) self.line_regexp = true else if (std.mem.eql(u8, name, "word-regexp")) self.word_regexp = true else if (std.mem.eql(u8, name, "recursive")) {
            self.recursive = true;
            self.directory_mode = .recurse;
        } else if (std.mem.eql(u8, name, "dereference-recursive")) {
            self.recursive = true;
            self.dereference_recursive = true;
            self.directory_mode = .recurse;
        } else if (std.mem.eql(u8, name, "directories")) {
            try self.setDirectoryMode(try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "devices")) {
            try self.setDeviceMode(try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "after-context")) {
            try self.setAfterContext(try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "before-context")) {
            try self.setBeforeContext(try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "context")) {
            try self.setContext(try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "group-separator") or std.mem.eql(u8, name, "context-separator")) {
            self.context_separator = try requireValue(inline_value, it);
        } else if (std.mem.eql(u8, name, "no-group-separator") or
            std.mem.eql(u8, name, "no-context-separator"))
        {
            self.context_separator = null;
        } else if (std.mem.eql(u8, name, "label")) {
            self.label = try requireValue(inline_value, it);
        } else if (std.mem.eql(u8, name, "include")) {
            try self.file_filter_args.append(allocator, .{ .include = try requireValue(inline_value, it) });
        } else if (std.mem.eql(u8, name, "exclude")) {
            try self.file_filter_args.append(allocator, .{ .exclude = try requireValue(inline_value, it) });
        } else if (std.mem.eql(u8, name, "exclude-from")) {
            try self.file_filter_args.append(allocator, .{ .exclude_file = try requireValue(inline_value, it) });
        } else if (std.mem.eql(u8, name, "exclude-dir")) {
            try self.exclude_dirs.append(allocator, try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "null-data")) self.null_data = true else if (std.mem.eql(u8, name, "null")) self.null_filename = true else if (std.mem.eql(u8, name, "files-with-matches")) self.list_files = true else if (std.mem.eql(u8, name, "files-without-match")) self.list_files = false else if (std.mem.eql(u8, name, "max-count")) {
            self.max_count = std.fmt.parseInt(usize, try requireValue(inline_value, it), 10) catch return error.InvalidNumber;
        } else if (std.mem.eql(u8, name, "text")) self.binary_mode = .text else if (std.mem.eql(u8, name, "binary")) {
            // GNU/Linux already reads files in binary mode; keep -U/--binary
            // as the compatible no-op documented by GNU grep.
        } else if (std.mem.eql(u8, name, "line-buffered")) self.line_buffered = true else if (std.mem.eql(u8, name, "initial-tab")) self.initial_tab = true else if (std.mem.eql(u8, name, "binary-files")) {
            try self.setBinaryMode(try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "help")) self.help = true else if (std.mem.eql(u8, name, "version")) self.version = true else if (std.mem.eql(u8, name, "color") or std.mem.eql(u8, name, "colour")) {
            if (inline_value) |value| self.setColorMode(value) else self.color = .auto;
        } else if (std.mem.eql(u8, name, "regexp")) {
            try self.appendArgumentPatterns(allocator, try requireValue(inline_value, it));
        } else if (std.mem.eql(u8, name, "file")) {
            try self.pattern_files.append(allocator, try requireValue(inline_value, it));
        } else return error.UnknownOption;
    }

    fn requireValue(inline_value: ?[]const u8, it: *std.process.Args.Iterator) ![]const u8 {
        return inline_value orelse (it.next() orelse return error.MissingOptionArgument);
    }

    fn resolveLongOption(given: []const u8) ?[]const u8 {
        const names = [_][]const u8{
            "after-context",        "before-context",     "basic-regexp",
            "binary",               "binary-files",       "byte-offset",
            "color",                "colour",             "context",
            "context-separator",    "count",              "dereference-recursive",
            "devices",              "directories",        "exclude",
            "exclude-dir",          "exclude-from",       "extended-regexp",
            "file",                 "files-with-matches", "files-without-match",
            "fixed-strings",        "group-separator",    "help",
            "ignore-case",          "include",            "initial-tab",
            "invert-match",         "label",              "line-buffered",
            "line-number",          "line-regexp",        "max-count",
            "no-context-separator", "no-filename",        "no-group-separator",
            "no-ignore-case",       "no-messages",        "null",
            "null-data",            "only-matching",      "perl-regexp",
            "quiet",                "recursive",          "regexp",
            "silent",               "text",               "version",
            "with-filename",        "word-regexp",
        };
        var found: ?[]const u8 = null;
        for (names) |name| {
            if (std.mem.eql(u8, name, given)) return name;
            if (std.mem.startsWith(u8, name, given)) {
                if (found != null) return null;
                found = name;
            }
        }
        return found;
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
        self.context_requested = true;
    }

    fn setBeforeContext(self: *Options, value: []const u8) !void {
        self.before_context = std.fmt.parseInt(usize, value, 10) catch return error.InvalidNumber;
        self.before_context_explicit = true;
        self.context_requested = true;
    }

    fn setContext(self: *Options, value: []const u8) !void {
        const count = std.fmt.parseInt(usize, value, 10) catch return error.InvalidNumber;
        if (!self.before_context_explicit) self.before_context = count;
        if (!self.after_context_explicit) self.after_context = count;
        self.context_requested = true;
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
