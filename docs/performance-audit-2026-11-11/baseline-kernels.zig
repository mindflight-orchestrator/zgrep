const std = @import("std");
const zgrep = @import("zgrep");
export fn measure_kernel(ptr: [*]const u8, len: usize, mode: u32) usize {
    const bytes = ptr[0..len];
    if (mode == 0) return (zgrep.scanner.findNulParallel(bytes) catch unreachable) orelse len;
    if (mode == 1) return @intFromBool(zgrep.matcher.isAscii(bytes));
    if (mode == 2) return std.mem.countScalar(u8, bytes, '\n');
    const pattern: []const u8 = switch (mode) {
        8 => "not-present-anywhere",
        10 => "RARE-NEEDLE",
        11 => "INFO",
        else => "rare-needle",
    };
    const literal = zgrep.matcher.Literal.init(pattern, mode == 10, false, mode == 9);
    if (mode == 3) {
        var cursor: usize = 0;
        var found: usize = 0;
        while (literal.find(bytes, cursor)) |pos| {
            found += 1;
            cursor = pos + literal.pattern.len;
        }
        return found;
    }
    if (mode == 4 or mode >= 8) return zgrep.scanner.parallelLiteralCount(bytes, &literal, false, '\n') catch unreachable;
    const matcher: zgrep.matcher.Matcher = .{ .literal = literal };
    var buffer: [4096]u8 = undefined;
    var output: std.Io.Writer.Discarding = .init(&buffer);
    const result = zgrep.scanner.scanBuffer(bytes, &.{matcher}, "input", .{
        .invert = false, .count = mode == 5, .line_number = mode == 7,
        .show_filename = false, .quiet = false, .list_files = null,
        .max_count = null, .byte_offset = false, .only_matching = false,
        .binary_mode = .text,
    }, &output.writer) catch unreachable;
    return if (mode == 5) result.selected_lines else @intCast(output.fullCount());
}
